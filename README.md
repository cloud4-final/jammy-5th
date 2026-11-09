# jammy-5th

3거점 온프레미스(OpenStack + k3s)와 AWS를 잇는 하이브리드 클라우드 프로젝트

## 폴더 구조
| 폴더 | 내용 |
|---|---|
| infra/aws | AWS 리소스 Terraform (입구, Route 53, S3·CloudFront, burst) |
| infra/openstack | 거점 OpenStack·VM 구성 |
| k8s | 쿠버네티스 매니페스트 |
| [jammy-collector](https://github.com/cloud4-final/jammy-collector) | 조회·수집 API (별도 저장소) |
| [jammy-observability](https://github.com/cloud4-final/jammy-observability) | Prometheus·Grafana·Loki·Alertmanager (별도 저장소) |
| loadtest | k6 시나리오, 이벤트 생성기 |
| docs/adr | 설계 결정 기록 |

## 브랜치 규칙
- main 직접 push 금지, PR + 승인 1명 필수
- 브랜치 이름: `종류/내용` (예: `feat/aws-haproxy`, `fix/route53-health`, `docs/adr-001`)

## 커밋 메시지
`종류: 내용` — feat(기능), fix(수정), docs(문서), chore(설정·정리), refactor(구조 개선)

## 금지
- AWS 키, `*.tfstate`, `*.tfvars`, kubeconfig 커밋 금지
