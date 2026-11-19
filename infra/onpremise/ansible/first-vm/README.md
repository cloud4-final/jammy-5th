# 온프레미스 VM 생성 코드

KVM·libvirt 기기에서 Ubuntu cloud image와 cloud-init으로 VM을 만드는 Ansible 플레이북입니다.
2026-11-17 거점 A 기기 3대(jammy-main, jammy-a1, jammy-a2)에 VM 11대를 이 코드로 만들었습니다.

## 파일 구성

- create-vm-common.yml: VM 1대를 만드는 플레이북
- host_vars/<기기>.yml: 기기별 값 (기기 이름, 저장 장치, 이미지 경로와 SHA-256, 폴더, VM 계정, DNS). 자동으로 읽습니다.
- vms/<기기>/<vm>.yml: VM별 값 (이름, CPU, 메모리, 디스크, 브리지, IP, 게이트웨이, MAC, 추가 디스크). 실행할 때 지정합니다.
- vm-vars.yml: 변수 설명용 예시 (플레이북은 읽지 않음)
- templates/: cloud-init 설정 틀 (user-data, network-config, meta-data)
- inventory.example.ini: 인벤토리 예시. 실제 inventory.ini는 Git에 올리지 않습니다.

## 실행

0. WSL에 `~/.ssh/id_ed25519.pub`가 있어야 합니다. 없으면 `ssh-keygen -t ed25519`로 먼저 만듭니다. (없으면 생성 도중 멈추고, 이미 만든 작업 폴더 때문에 재실행도 멈춥니다.)
1. inventory.example.ini를 inventory.ini로 복사하고 기기 주소를 넣습니다.
2. 미리 보기: ansible-playbook -i inventory.ini create-vm-common.yml -K -l <기기> -e @vms/<기기>/<새 VM>.yml --check
   - 이미 만든 VM의 파일로 실행하면 기존 VM 검사에서 멈춥니다. 새로 만들 VM 파일로 미리 봅니다.
3. 생성: 같은 명령에서 --check 대신 -e confirm_vm_create=true 를 붙입니다.

## 안전장치

- confirm_vm_create=true 없이는 만들지 않고, 한 번에 기기 한 대에만 실행합니다.
- 기기 이름, VM 저장소 파티션, 기본 이미지 SHA-256을 확인합니다.
- 같은 이름의 VM, 디스크, seed, 작업 폴더가 있으면 멈춥니다.
- 추가 디스크는 블록 장치인지, 다른 VM(실행 중·다음 부팅 설정 모두)이 같은 장치를 쓰고 있는지 장치 번호로 확인한 뒤 연결합니다.
- vm_autostart: false인 VM(js2)은 자동 시작에서 제외합니다.
- WSL의 공개 키만 읽고 개인 키는 읽지 않습니다.

## VM 추가

vms/<기기>/ 의 파일 하나를 복사해 이름, IP, MAC, 사양을 바꿉니다.
MAC은 52:54:00 뒤에 IP 끝 세 자리를 16진수로 붙입니다. (예: 10.11.11.1 → 52:54:00:0b:0b:01)
추가 디스크는 기기의 vg-fast에 LV를 먼저 만든 뒤 vm_extra_disks에 경로를 적습니다.

## 검증 범위

- 거점 A 기기 3대에 VM 11대 생성, 기기 재부팅 후 VM 자동 시작, VM 인터넷 접속, 추가 디스크 연결을 확인했습니다.
- cloud-init 설정에서 VM 사용자에게 비밀번호 없는 sudo 권한을 줍니다. 팀 정책과 맞는지 확인이 필요합니다.
- 수신 VM의 공유기 쪽 망(VLAN 10·20) NIC는 아직 지원하지 않습니다.
