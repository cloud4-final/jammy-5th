"""Offline invariants; not Kubernetes admission or a live cluster test.

Run: python -m unittest discover -s k8s/tests -v
Dependency: PyYAML==6.0.3
"""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1] / 'sites/a'

class ADeploymentTests(unittest.TestCase):
    def setUp(self):
        self.objects = list(yaml.safe_load_all((ROOT / 'collector.yaml').read_text(encoding='utf-8')))
        self.deployment, self.service = self.objects
        self.pod = self.deployment['spec']['template']['spec']
        self.container = self.pod['containers'][0]

    def test_service_selects_deployment_and_probe_port(self):
        self.assertEqual(self.service['spec']['selector'], self.deployment['spec']['template']['metadata']['labels'])
        port = self.container['ports'][0]
        self.assertEqual(port['containerPort'], 8000)
        self.assertEqual(self.service['spec']['ports'][0]['targetPort'], port['name'])
        for probe in ['readinessProbe', 'livenessProbe']:
            self.assertEqual(self.container[probe]['httpGet']['port'], port['name'])
        self.assertEqual(self.service['spec']['type'], 'ClusterIP')

    def test_only_app_nodes_and_fixed_image(self):
        image = self.container['image']
        self.assertRegex(image, r'^ghcr.io/cloud4-final/jammy-collector:sha-6178eb1@sha256:[0-9a-f]{64}$')
        terms = self.pod['affinity']['nodeAffinity']['requiredDuringSchedulingIgnoredDuringExecution']['nodeSelectorTerms']
        self.assertEqual(terms, [{'matchExpressions': [{'key': 'kubernetes.io/hostname', 'operator': 'In', 'values': ['a-app-01', 'a-app-02']}]}])

    def test_secret_refs_and_no_migration(self):
        env = {e['name']: e for e in self.container['env']}
        for key in ['DATABASE_URL', 'DATABASE_READ_URL']:
            self.assertNotIn('value', env[key])
            self.assertEqual(env[key]['valueFrom']['secretKeyRef'], {'name': 'collector-db', 'key': key})
        self.assertEqual(env['SITE_ID']['value'], 'jammy-a')
        self.assertFalse(self.pod.get('initContainers'))
        self.assertFalse(self.pod['automountServiceAccountToken'])

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
        config = yaml.safe_load((ROOT / 'kustomization.yaml').read_text())
        self.assertEqual(config['resources'], ['namespace.yaml', 'collector.yaml'])
        for path in config['resources']:
            for obj in yaml.safe_load_all((ROOT / path).read_text()):
                self.assertIn(obj['kind'], ['Namespace', 'Deployment', 'Service'])

if __name__ == '__main__':
    unittest.main()

