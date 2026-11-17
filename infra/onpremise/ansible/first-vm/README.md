# 온프레미스 VM 생성 코드

KVM·libvirt 환경에서 Ubuntu cloud image와 cloud-init을 사용해
VM을 생성하기 위한 Ansible 공통 플레이북입니다.

## 파일 구성

- `create-vm-common.yml`: VM 생성 공통 플레이북 (한 번에 VM 1대)
- `host_vars/<호스트>.yml`: 호스트 공통 값 (호스트 이름, 저장 장치, 이미지와 SHA-256)
- `vms/<호스트>/<vm>.yml`: VM별 값 (이름, 사양, 브리지, 주소, MAC, 추가 디스크)
- `inventory.example.ini`: 인벤토리 예시. `inventory.ini`로 복사해서 사용 (Git 제외)
- `vm-vars.yml`: 변수 설명용 예시 (플레이북이 읽지 않음)
- `templates/`: cloud-init 설정 템플릿

## 거점 A 본체 VM (구축 가이드 0단계 표 기준)

| VM | 주소 | 브리지 | 추가 디스크 |
|---|---|---|---|
| cp1 | 10.11.10.1 | br-svc | - |
| collect1 (수집) | 10.11.10.2 | br-svc | /dev/vg-fast/raw |
| ops1 (관제) | 10.11.10.3 | br-svc | - |
| js1 (JetStream) | 10.11.10.4 | br-svc | /dev/vg-fast/js |
| db1 (주 DB) | 10.11.11.1 | br-data | /dev/vg-fast/pg-data |

게이트웨이는 호스트 브리지 주소(.254)입니다. MAC은 `52:54:00` 뒤에 IP 2~4번째 칸을 16진수로 붙였습니다.
vCPU·메모리는 본체 사양을 확인한 뒤 조정합니다.

## 실행 (WSL에서)

```
cp inventory.example.ini inventory.ini   # 본체 주소 입력
# host_vars/jammy-main.yml 의 base_image_sha256 입력

ansible-playbook -i inventory.ini create-vm-common.yml -K \
  -e @vms/jammy-main/cp1.yml --check
ansible-playbook -i inventory.ini create-vm-common.yml -K \
  -e @vms/jammy-main/cp1.yml -e confirm_vm_create=true
```

- `-K`: 본체 sudo 비밀번호
- VM에는 WSL의 `~/.ssh/id_ed25519.pub`가 들어갑니다.
- VM 접속: `ssh -J jammy@<본체 주소> jammy@10.11.10.1`

## 검증 범위

- 기존 VM 구축에 사용한 코드를 정리했습니다.
- 새 환경에서 전체 재구축 시험은 아직 하지 않았습니다.
- 수신 VM의 VLAN 브리지(br-v10·br-v20) 연결은 스위치 작업 뒤에 추가합니다.
