#!/bin/bash

# 1. 변수 설정
VM_NAME="ossca-ebpf-work"
GUEST_USER="ebpf"
GUEST_PASS="1234"
PROJECT_ROOT=$(realpath .)
SSH_PUB_KEY="$HOME/.ssh/eBPF_sshkey.pub"

echo "[-] 고성능 인프라 구성 시작 (M4 Max Optimized)..."

# 2. 기존 인스턴스 정리 및 재생성
tart stop $VM_NAME 2>/dev/null
tart delete $VM_NAME 2>/dev/null
tart clone ghcr.io/cirruslabs/ubuntu:latest $VM_NAME

# 3. 리소스 할당 (8GB RAM, 4 CPU, 50GB Disk)
echo "[-] 리소스 할당 중: 8GB RAM / 50GB Disk..."
tart set $VM_NAME --cpu 4 --memory 8192
tart resize $VM_NAME --disk 50

# 4. VM 실행
echo "[-] VM 부팅 중..."
tart run --no-graphics --dir="$PROJECT_ROOT:tag=repo" $VM_NAME > /tmp/ossca_vm.log 2>&1 &

# 5. Guest Agent 응답 대기
echo "[-] Guest Agent 응답 대기 중..."
while ! tart exec $VM_NAME ls / >/dev/null 2>&1; do sleep 3; done

# 6. 사용자 계정(ebpf) 생성 및 권한 설정
echo "[-] 계정 설정 중: user '$GUEST_USER'..."
tart exec $VM_NAME sudo useradd -m -s /bin/bash $GUEST_USER
tart exec $VM_NAME sh -c "echo '$GUEST_USER:$GUEST_PASS' | sudo chpasswd"
tart exec $VM_NAME sudo usermod -aG sudo $GUEST_USER
tart exec $VM_NAME sh -c "echo '$GUEST_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$GUEST_USER"

# 7. SSH 공개키 주입
echo "[-] SSH 키 주입 중..."
tart exec $VM_NAME sudo mkdir -p /home/$GUEST_USER/.ssh
tart exec $VM_NAME sudo chmod 700 /home/$GUEST_USER/.ssh
tart exec $VM_NAME sh -c "echo '$(cat $SSH_PUB_KEY)' | sudo tee /home/$GUEST_USER/.ssh/authorized_keys"
tart exec $VM_NAME sudo chown -R $GUEST_USER:$GUEST_USER /home/$GUEST_USER/.ssh
tart exec $VM_NAME sudo chmod 600 /home/$GUEST_USER/.ssh/authorized_keys

# 8. 개발 환경 구성 및 마운트
echo "[-] 필수 패키지 설치 및 과제 마운트..."
tart exec $VM_NAME sudo apt-get update
tart exec $VM_NAME sudo apt-get install -y golang-go make curl
tart exec $VM_NAME sudo mkdir -p /work
tart exec $VM_NAME sudo mount -t virtiofs repo /work

# 9. 빌드 및 실행
echo "[-] 과제 빌드 중..."
tart exec $VM_NAME make -C /work build

echo "[+] 모든 설정 완료!"
echo "[*] IP 주소: $(tart ip $VM_NAME)"
echo "[*] 접속 명령어: ssh -i ~/.ssh/eBPF_sshkey $GUEST_USER@$(tart ip $VM_NAME)"
echo "--------------------------------------------------"
echo "[!] 서버를 실행합니다..."
tart exec $VM_NAME sudo /work/app
