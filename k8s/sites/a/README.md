# A 거점 k3s 배포 기준

A CP 1대·App 1대에 구성한 k3s의 공유용 기본 설정이다.
실제 설치 버전은 `v1.37.2+k3s1`이며, 이 디렉터리는 기존 클러스터에 적용할 namespace와 테스트용 RBAC 기준을 둔다(k3s 자동 설치기가 아니다).
이전 MVP `collector.yaml` 매니페스트(`sha-6178eb1`)는 제거되었으며, 애플리케이션 배포 구성은 [jammy-application](https://github.com/cloud4-final/jammy-application)(`deploy/helm/jammy-platform`)에서 관리한다.

## 구성과 선행 조건

- `a-cp-01`과 `a-app-01`이 Ready인 A 클러스터. Data VM은 k3s 노드가 아니다.
- 기본 Flannel VXLAN, 현재 인터페이스 ens2. Traefik·ServiceLB는 초기 설치에서 비활성화했다.
- `namespace.yaml`: `jammy` namespace 선언.
- `backend-test-rbac.yaml`: jammy 조회·로그·port-forward만 허용하는 선택적 테스트 권한. 앱 배포와 분리했다.
- `bootstrap/`: 실제 설치 구성의 주소를 제거한 참고 예시. 그대로 설치하지 않는다.

## 검토와 적용

저장소 루트에서 실행한다. `A_CONTEXT`는 **기존 A 클러스터의 관리자 context 이름**으로 지정한다.

```sh
kubectl --context "$A_CONTEXT" get nodes -o wide
kubectl kustomize k8s/sites/a
kubectl --context "$A_CONTEXT" apply -k k8s/sites/a
```

## 테스트 담당자 권한 인계

관리자만 `kubectl --context "$A_CONTEXT" apply -f k8s/sites/a/backend-test-rbac.yaml`을 실행한다.
`backend-tester` ServiceAccount의 단기 TokenRequest 토큰으로 별도 kubeconfig를 만든다. 토큰·CA·서버 검증과 만료 시각을 확인하고 개인 안전 경로로 전달한다. 정적 Secret 토큰을 생성하지 않는다.

검증 기준: jammy Pod 조회·로그·port-forward 허용, Secret·exec·다른 namespace·배포 수정 거부.
테스트 종료 시 RoleBinding을 제거해 권한을 회수하고 발급 토큰은 만료시킨다. 이 권한은 Argo CD 배포 권한이 아니다.

## 되돌리기

- 테스트 접근 회수: `kubectl --context "$A_CONTEXT" -n jammy delete rolebinding backend-test-observer`.
- namespace 삭제·Secret 삭제·DB 데이터 삭제를 롤백으로 사용하지 않는다.

관련: [Jira MWGL-3](https://teamjammyjammy.atlassian.net/browse/MWGL-3), [MWGL-6](https://teamjammyjammy.atlassian.net/browse/MWGL-6), [실제 연동 기록](https://teamjammyjammy.atlassian.net/wiki/spaces/MFS/pages/12943361), [기준 수정 PR](https://github.com/cloud4-final/jammy-docs/pull/9).
