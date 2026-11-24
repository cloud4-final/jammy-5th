"""Offline invariants; not Kubernetes admission or a live cluster test.

Run: python -m unittest discover -s k8s/tests -v
Dependency: PyYAML==6.0.3
"""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1] / 'sites/a'


class ADeploymentTests(unittest.TestCase):
    def test_rbac_exact_minimum(self):
        objects = list(yaml.safe_load_all((ROOT / 'backend-test-rbac.yaml').read_text(encoding='utf-8')))
        sa, role, binding = objects
        self.assertEqual(sa['kind'], 'ServiceAccount')
        self.assertEqual(role['kind'], 'Role')
        self.assertEqual(binding['kind'], 'RoleBinding')
        self.assertTrue(all(o['metadata']['namespace'] == 'jammy' for o in objects))
        actual = {(g, r, v) for rule in role['rules'] for g in rule['apiGroups'] for r in rule['resources'] for v in rule['verbs']}
        expected = {('', r, v) for r in ['pods', 'services', 'endpoints', 'events'] for v in ['get', 'list', 'watch']}
        expected |= {('apps', r, v) for r in ['deployments', 'replicasets'] for v in ['get', 'list', 'watch']}
        expected |= {('', 'pods/log', 'get'), ('', 'pods/portforward', 'create')}
        self.assertEqual(actual, expected)
        self.assertEqual(binding['roleRef']['name'], role['metadata']['name'])
        self.assertEqual(binding['subjects'], [{'kind': 'ServiceAccount', 'name': sa['metadata']['name'], 'namespace': 'jammy'}])

    def test_rbac_and_bootstrap_not_automatically_applied(self):
        self.assertFalse((ROOT / 'collector.yaml').exists())
        config = yaml.safe_load((ROOT / 'kustomization.yaml').read_text(encoding='utf-8'))
        self.assertEqual(config['resources'], ['namespace.yaml'])
        for path in config['resources']:
            for obj in yaml.safe_load_all((ROOT / path).read_text(encoding='utf-8')):
                self.assertIn(obj['kind'], ['Namespace'])


if __name__ == '__main__':
    unittest.main()
