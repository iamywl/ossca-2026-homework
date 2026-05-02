#!/bin/bash

# 1. 변수 설정
VM_NAME="ossca-ebpf-work"
GUEST_USER="ebpf"
GUEST_PASS="1234"
PROJECT_ROOT=$(realpath .)
SSH_PUB_KEY="$HOME/.ssh/eBPF_sshkey.pub"

echo "[-] 고성능 인프라 구성 시작 (M4 Max Optimized - v1)..."

# SSH 키 존재 여부 확인
if [ ! -f "$SSH_PUB_KEY" ]; then
    echo "[!] 오류: SSH 공개키를 찾을 수 없습니다 ($SSH_PUB_KEY)"
    exit 1
fi

# 2. 기존 인스턴스 정리 및 재생성
echo "[-] 기존 인스턴스 정리 중..."
tart stop $VM_NAME 2>/dev/null
tart delete $VM_NAME 2>/dev/null

echo "[-] 새 인스턴스 복제 중 (ghcr.io/cirruslabs/ubuntu:latest)..."
tart clone ghcr.io/cirruslabs/ubuntu:latest $VM_NAME

# 3. 리소스 할당 (8GB RAM, 4 CPU, 50GB Disk)
echo "[-] 리소스 할당 중: 4 CPU / 8GB RAM / 50GB Disk..."
tart set $VM_NAME --cpu 4 --memory 8192 --disk-size 50

# 4. VM 실행
echo "[-] VM 부팅 시작..."
tart run --no-graphics --dir="$PROJECT_ROOT:tag=repo" $VM_NAME > /tmp/ossca_vm.log 2>&1 &
VM_PID=$!

# 5. Guest Agent 응답 대기 (최대 2분)
echo "[-] Guest Agent 응답 대기 중..."
MAX_RETRIES=40
RETRY_COUNT=0
while ! tart exec $VM_NAME ls / >/dev/null 2>&1; do
    if ! kill -0 $VM_PID 2>/dev/null; then
        echo "[!] 오류: VM 프로세스가 예기치 않게 종료되었습니다. /tmp/ossca_vm.log 를 확인하세요."
        exit 1
    fi
    sleep 3
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[!] 오류: Guest Agent 응답 대기 시간 초과"
        exit 1
    fi
done
echo "[+] Guest Agent 연결 성공."

# 6. 사용자 계정(ebpf) 생성 및 권한 설정
echo "[-] 계정 설정 중: user '$GUEST_USER'..."
tart exec $VM_NAME sudo useradd -m -s /bin/bash $GUEST_USER 2>/dev/null || true
tart exec $VM_NAME sh -c "echo '$GUEST_USER:$GUEST_PASS' | sudo chpasswd"
tart exec $VM_NAME sudo usermod -aG sudo $GUEST_USER
tart exec $VM_NAME sh -c "echo '$GUEST_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$GUEST_USER"

# 7. SSH 공개키 주입 (tart exec -i 사용으로 안전하게 주입)
echo "[-] SSH 키 주입 중..."
tart exec $VM_NAME sudo mkdir -p /home/$GUEST_USER/.ssh
tart exec $VM_NAME sudo chmod 700 /home/$GUEST_USER/.ssh
cat "$SSH_PUB_KEY" | tart exec -i $VM_NAME sh -c "sudo tee /home/$GUEST_USER/.ssh/authorized_keys > /dev/null"
tart exec $VM_NAME sudo chown -R $GUEST_USER:$GUEST_USER /home/$GUEST_USER/.ssh
tart exec $VM_NAME sudo chmod 600 /home/$GUEST_USER/.ssh/authorized_keys

# 8. 개발 환경 구성 및 마운트
echo "[-] 필수 패키지 설치 중 (APT 락 대기 포함)..."
# APT 락이 해제될 때까지 대기하는 루프
tart exec $VM_NAME sh -c "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do echo 'Waiting for apt lock...'; sleep 2; done"

tart exec $VM_NAME sh -c "sudo DEBIAN_FRONTEND=noninteractive apt-get update -y"
tart exec $VM_NAME sh -c "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go make curl"

echo "[-] 과제 디렉토리 마운트..."
tart exec $VM_NAME sudo mkdir -p /work
tart exec $VM_NAME sh -c "sudo mount -t virtiofs repo /work 2>/dev/null || mountpoint -q /work"

# 9. 빌드 및 실행
echo "[-] 과제 빌드 중..."
tart exec $VM_NAME make -C /work build

VM_IP=$(tart ip $VM_NAME)
echo "[+] 모든 설정 완료!"
echo "[*] IP 주소: $VM_IP"
echo "[*] 접속 명령어: ssh -i ${SSH_PUB_KEY%.pub} $GUEST_USER@$VM_IP"
echo "--------------------------------------------------"
echo "[!] 서버를 실행합니다... (종료하려면 Ctrl+C)"
tart exec $VM_NAME sudo /work/app
