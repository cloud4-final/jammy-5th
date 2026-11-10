# A 거점 collector 배포 기준

A CP 1대·App 1대에 구성한 k3s와 collector의 공유용 배포 설정이다.
실제 설치 버전은 `v1.37.2+k3s1`, 배포 이미지는 `sha-6178eb1`의 고정 digest다.
이 디렉터리는 기존 클러스터에 적용할 앱 설정이며 k3s 자동 설치기는 아니다.

## 구성과 선행 조건

- `a-cp-01`과 `a-app-01`이 Ready인 A 클러스터. Data VM은 k3s 노드가 아니다.
- 기본 Flannel VXLAN, 현재 인터페이스 ens2. Traefik·ServiceLB는 초기 설치에서 비활성화했다.
- `collector.yaml`: Deployment 2 replicas, ClusterIP Service 8000, App 노드만 배치.
- 두 Pod는 현재 같은 App 1에서 실행된다. App 2는 SSH/가입 검증 후 별도 추가한다. 노드 HA 완료가 아니다.
- `backend-test-rbac.yaml`: jammy 조회·로그·port-forward만 허용하는 선택적 테스트 권한. 앱 배포와 분리했다.
- `bootstrap/`: 실제 설치 구성의 주소를 제거한 참고 예시. 그대로 설치하지 않는다.
- App/Pod→A DB 경로·pg_hba·TLS가 준비돼 있어야 한다. CP→DB 허용이나 Data exporter 직접 접근을 추가하지 않는다.

## Secret 준비

관리자가 안전한 경로로 아래 Secret을 `jammy`에 준비한다. Secret 값·kubeconfig·노드 토큰은 저장소에 넣지 않는다.

| Secret | 키/형식 | 용도 |
|---|---|---|
| ghcr-pull | type: `kubernetes.io/dockerconfigjson`, 필수 data 키: `.dockerconfigjson` | private GHCR 읽기 권한 |
| collector-db | DATABASE_URL | A jammy DB의 jammy_writer, sslmode=require |
| collector-db | DATABASE_READ_URL | 초기 A 시험은 같은 A DB의 jammy_reader, sslmode=require |

접속 주소는 내부 인계 문서를 따른다. `public.events`는 이미 준비됐으므로 migrate·DDL·초기화 Job을 실행하지 않는다.
배포 버전 `6178eb1`은 읽기·쓰기 연결 풀을 각각 생성하고 각 풀에 `DB_POOL_MAX=10`을 적용한다. 정상 2 Pod 기준 읽기 최대 20개 + 쓰기 최대 20개 = **A DB에 최대 40개**다(워커 1개/Pod 기준). 기본 RollingUpdate의 surge Pod 1개까지 포함하면 3 Pod·최대 60개이며 종료 중 Pod가 연결을 유지하면 일시적으로 더 늘 수 있다. 다른 앱·복제·관측·관리 연결과 PostgreSQL 예약 연결 여유까지 현서 담당자와 확인한다. URL이 같은 DB를 가리켜도 두 풀은 합쳐지지 않는다.

## 검토와 적용

저장소 루트에서 실행한다. `A_CONTEXT`는 **기존 A 클러스터의 관리자 context 이름**으로 지정한다.
현재 context·노드·namespace와 이미지 digest를 확인한 뒤 진행하며, B/C에는 적용하지 않는다.

```sh
kubectl --context "$A_CONTEXT" get nodes -o wide
kubectl kustomize k8s/sites/a
kubectl --context "$A_CONTEXT" apply -f k8s/sites/a/namespace.yaml
# 위 표의 Secret을 별도 안전한 경로로 준비한 다음 진행
kubectl --context "$A_CONTEXT" apply --dry-run=server -k k8s/sites/a
kubectl --context "$A_CONTEXT" diff -k k8s/sites/a
kubectl --context "$A_CONTEXT" apply -k k8s/sites/a
kubectl --context "$A_CONTEXT" -n jammy rollout status deployment/mobility-collector --timeout=120s
kubectl --context "$A_CONTEXT" -n jammy get pods -o wide
```

`diff`의 exit 1은 차이 존재를 뜻한다. 오류와 구분한다. PR 작성 중 위 원격 적용 명령을 재실행하지 않았다.
서버 dry-run/admission은 실제 대상에서 적용 전에 확인한다. 기존 배포의 필드 관리 충돌이 있으면 강제 덮어쓰지 않는다.

## 읽기 중심 확인

```sh
kubectl --context "$A_CONTEXT" -n jammy port-forward --address 127.0.0.1 service/mobility-collector 18080:8000
# 다른 터미널
curl --fail --max-time 5 http://127.0.0.1:18080/healthz
curl --fail --max-time 5 http://127.0.0.1:18080/ready
curl --fail --max-time 5 'http://127.0.0.1:18080/api/v1/events?limit=1'
```

시험 후 port-forward를 종료한다. 한 Pod로 전달되므로 외부 입구·부하 분산 성능을 증명하지 않는다.
scrape annotation만으로 중앙 Prometheus 수집이 보장되지 않는다. OTEL exporter 주소도 설정하지 않았으므로 trace 연동 완료가 아니다.


## 쓰기 경로 별도 확인

배포 버전의 `/ready`는 읽기 풀의 `SELECT 1`만 확인한다. Ready/GET 성공만으로 writer의 연결·INSERT 권한을 확인한 것으로 처리하지 않는다. 아래 시험은 **쓰기 가능한 시험 범위와 시간을 담당자와 확인한 후에만** 수행한다.

1. 승인된 시험 이벤트 JSON 파일을 준비한다. 필수 필드는 `event_id`, `region`, `vehicle_id`이며 `region`은 `site-a/site-b/site-c/aws` 중 하나다. 이번 실행의 새 ID와 기대 업무 필드를 기록하고 기존 ID/원본 자료를 덮어쓰지 않는다.
2. 위 localhost port-forward를 유지한 상태에서 아래 명령을 실행한다. `EVENT_FILE`은 승인된 JSON 파일 경로, `EVENT_ID`는 그 파일의 ID다. ID는 URL 경로에 안전한 영문·숫자·하이픈으로 준비한다.

```sh
curl --silent --show-error --max-time 10 -o write-result.json -w '%{http_code}\n' \
  -H 'Content-Type: application/json' --data-binary "@${EVENT_FILE}" \
  http://127.0.0.1:18080/api/v1/events
# 같은 파일을 재전송해 중복 처리 확인
curl --silent --show-error --max-time 10 -o duplicate-result.json -w '%{http_code}\n' \
  -H 'Content-Type: application/json' --data-binary "@${EVENT_FILE}" \
  http://127.0.0.1:18080/api/v1/events
curl --silent --show-error --max-time 10 -o readback-result.json -w '%{http_code}\n' \
  "http://127.0.0.1:18080/api/v1/events/${EVENT_ID}"
```

3. **신규 201/accepted → 재전송 200/duplicate → 조회 200**과 동일 event_id·업무 필드를 대조한다. HTTP 200만으로 합격 처리하지 않는다. 첫 요청이 duplicate면 신규 쓰기 증거가 아니므로 기존 ID 여부를 확인한다. 타임아웃은 미저장을 뜻하지 않으므로 같은 ID 조회로 상태를 확인한 뒤 재시도한다.
4. 실패·503이면 배포 인수를 완료 처리하지 않고 writer 설정·권한·DB 여유를 확인한다. 결과에는 시각·대상·이미지·event_id·응답 코드를 기록하고 파일은 내부 보관한다. 자동 DELETE/migrate/테이블 초기화는 하지 않는다.

이 절차는 향후 재배포 시 확인용이다. 이번 리뷰 보완에서는 실제 POST를 재실행하지 않았으며, 기존 10건 실환경 시험 증거와 구분한다. [고정 버전 DB 코드](https://github.com/cloud4-final/jammy-collector/blob/6178eb1/src/db.py)와 [API 코드](https://github.com/cloud4-final/jammy-collector/blob/6178eb1/src/main.py)를 근거로 작성했다.

## 테스트 담당자 권한 인계

관리자만 `kubectl --context "$A_CONTEXT" apply -f k8s/sites/a/backend-test-rbac.yaml`을 실행한다.
`backend-tester` ServiceAccount의 단기 TokenRequest 토큰으로 별도 kubeconfig를 만든다. 토큰·CA·서버 검증과 만료 시각을 확인하고 개인 안전 경로로 전달한다. 정적 Secret 토큰을 생성하지 않는다.

검증 기준: jammy Pod 조회·로그·port-forward 허용, Secret·exec·다른 namespace·배포 수정 거부.
테스트 종료 시 RoleBinding을 제거해 권한을 회수하고 발급 토큰은 만료시킨다. 이 권한은 Argo CD 배포 권한이 아니다.

## 검증 증거와 한계

| 구분 | 결과 |
|---|---|
| 2026-11-09 기존 실환경 실행 | CP/App Ready, 두 Pod health/ready 정상, 양 Pod reader/writer TLS 확인 |
| 기존 API 기능 시험 | health/ready 2 + 신규 POST 10 + 중복 POST 10 + GET 10 = 32요청 통과 |
| 기존 DB 독립 대조 | 시험 전 0→후 10행, 고유 ID 10·업무 필드 5개 일치 |
| 기존 제한 권한 시험 | jammy 조회 허용, Secret·다른 namespace 거부, logs/forward 허용·exec/배포 수정 거부 |
| 이번 PR 로컬 검증 | Kustomize 렌더링, YAML·RBAC·Secret 참조·고정 이미지·배치 제약 회귀 검사 |
| 미검증 | 새 클러스터 전체 재구축, 이 PR의 서버 dry-run/재적용, B/C·App2, 재부팅·노드 HA, Ingress/HTTPS, 중앙 관측, 대표 부하 p95 |

manifest는 검증 당시 설정을 기준으로 하며 이미지에 추적용 sha-tag를 병기했다. 실제 콘텐츠 digest는 동일하다.
원본 로그에는 내부 정보가 있어 커밋하지 않고 내부 문서에 보관한다.

## 되돌리기와 후속

- 변경 전 매니페스트를 안전한 로컬 위치에 보존하고 문제가 생기면 이전 선언을 재적용한다. `rollout undo`만으로 Service/RBAC 변경은 복구되지 않는다.
- 테스트 접근 회수: `kubectl --context "$A_CONTEXT" -n jammy delete rolebinding backend-test-observer`.
- namespace 삭제·Secret 삭제·DB 데이터 삭제를 롤백으로 사용하지 않는다.
- 후속: App2 가입, 입구/Ingress health 계약(C-API-006), 중앙 수집, method/결과별 지연 계측, k6 기준선, Argo CD 관리 인계.
- 기존 bootstrap의 node label `jammy.io/site=site-a`는 관측 label/env의 `site=jammy-a`와 다른 값이다. 이 PR은 노드 label을 변경하지 않으며 관측 relabel에 그대로 사용하지 않는다. 사용처 확인 후 별도 정리한다.

관련: [Jira MWGL-3](https://teamjammyjammy.atlassian.net/browse/MWGL-3), [MWGL-6](https://teamjammyjammy.atlassian.net/browse/MWGL-6), [실제 연동 기록](https://teamjammyjammy.atlassian.net/wiki/spaces/MFS/pages/12943361), [기준 수정 PR](https://github.com/cloud4-final/jammy-docs/pull/9).

