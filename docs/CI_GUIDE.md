# 공통 CI 가이드

## 1. 현재 워크플로
- **Terraform (`.github/workflows/terraform.yml`)**: `infra/aws/**` 변경 시 `fmt`, `init`, `validate` 실행
- **ShellCheck (`.github/workflows/shellcheck.yml`)**: `scripts/**` 변경 시 셸 스크립트 린트 실행 (`infra/aws/userdata/*.tftpl`은 템플릿이므로 정적 분석 제외)

## 2. 로컬 사전 검증
```bash
# Terraform (infra/aws)
terraform fmt -check -diff && terraform init -backend=false && terraform validate

# Shell 스크립트 (scripts)
bash -n scripts/*.sh && shellcheck scripts/*.sh
```

## 3. 신규 파트 CI 추가
본인 파트 디렉터리(예: `k8s/**`)를 감시하는 독립 워크플로 파일(`.github/workflows/<파트>.yml`)을 생성하고 `on.pull_request.paths` 및 `on.push.paths`를 지정하여 필요한 검증 Job을 작성합니다.

## 4. 운영 안내
현재 PR 필수 상태 체크(Required Check) 및 브랜치 보호 승인 규칙은 아직 설정되지 않았으며, 팀 합의 후 적용 예정입니다.
백엔드·모니터링 CI는 각 repo([jammy-application](https://github.com/cloud4-final/jammy-application), [jammy-observability](https://github.com/cloud4-final/jammy-observability))에서 별도 관리합니다.
