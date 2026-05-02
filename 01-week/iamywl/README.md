# 01-week iamywl 실행 환경 기록

## Host

- Host OS: macOS
- VM runner: Tart
- 작업 디렉토리: `<repo-root>`
- 공유된 repo 경로: host repo를 VM 내부 `/work`에 mount

macOS에서는 Linux network namespace 기능인 `CLONE_NEWNET`을 직접 실행할 수 없어서 Tart 기반 Ubuntu VM에서 빌드와 동작 검증을 수행했다.

## Tart VM

- VM 이름: `ossca-ebpf`
- 생성 원본 이미지: `ghcr.io/cirruslabs/ubuntu:latest`
- VM 설정: 4 CPU, 4096 MB memory, 20 GB disk
- Guest OS: Ubuntu Linux
- Kernel: `Linux ubuntu 6.17.0-14-generic #14~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Fri Jan 16 09:16:28 UTC 2 aarch64`
- Architecture: `aarch64`
- VM IP 확인 결과: `192.168.66.21`
  - VM IP는 재시작 후 변경될 수 있으므로 `tart ip ossca-ebpf`로 다시 확인한다.
- SSH 접속 계정: `admin`

초기 테스트 중 guest agent가 응답하지 않는 VM은 `ossca-ebpf-old`로 보존하고, 같은 이미지에서 `ossca-ebpf`를 다시 생성했다.

VM 생성:

```bash
tart clone ghcr.io/cirruslabs/ubuntu:latest ossca-ebpf
```

VM 실행:

```bash
tart run --no-graphics --dir=<repo-root>:tag=repo ossca-ebpf
```

VM 내부 repo mount:

```bash
tart exec ossca-ebpf sudo mkdir -p /work
tart exec ossca-ebpf sudo mount -t virtiofs repo /work
```

## VM 실행 방법

`tart exec`는 VM이 `running` 상태일 때만 사용할 수 있다. VM이 꺼져 있으면 다음과 같은 에러가 발생한다.

```text
VM "ossca-ebpf" is not running
```

현재 VM 상태 확인:

```bash
tart list
```

VM IP 확인:

```bash
tart ip ossca-ebpf
```

### Foreground 실행

다음 명령은 VM을 현재 터미널에서 foreground로 실행한다.

```bash
tart run --no-graphics --dir=<repo-root>:tag=repo ossca-ebpf
```

이 방식은 명령이 성공해도 프롬프트가 돌아오지 않는다. 터미널이 멈춘 것이 아니라 VM 실행 프로세스가 해당 터미널을 점유하고 있는 상태다.

이 경우 다른 터미널을 하나 더 열어서 다음 명령을 실행한다.

```bash
tart exec ossca-ebpf uname -a
```

VM을 종료하려면 foreground로 실행 중인 터미널에서 `Ctrl+C`를 누르거나 다른 터미널에서 다음 명령을 실행한다.

```bash
tart stop ossca-ebpf
```

### Background 실행

한 터미널에서 계속 작업하고 싶다면 VM을 background로 실행한다.

```bash
tart run --no-graphics --dir=<repo-root>:tag=repo ossca-ebpf > /tmp/ossca-ebpf.log 2>&1 &
```

실행 후 상태를 확인한다.

```bash
tart list
tart ip ossca-ebpf
```

`ossca-ebpf`가 `running`이면 같은 터미널에서 `tart exec`를 사용할 수 있다.

```bash
tart exec ossca-ebpf uname -a
```

### Repo mount

`--dir=<repo-root>:tag=repo` 옵션으로 VM을 실행한 뒤, VM 내부에서 공유 디렉토리를 `/work`에 mount한다.

```bash
tart exec ossca-ebpf sudo mkdir -p /work
tart exec ossca-ebpf sudo mount -t virtiofs repo /work
```

mount 확인:

```bash
tart exec ossca-ebpf ls -la /work/01-week/iamywl
```

이미 `/work`에 mount되어 있는 상태에서 다시 mount하면 실패할 수 있다. 이 경우 그대로 사용하거나 필요하면 unmount 후 다시 mount한다.

```bash
tart exec ossca-ebpf sudo umount /work
tart exec ossca-ebpf sudo mount -t virtiofs repo /work
```

### SSH 접속 준비

VS Code Remote SSH로 접속하려면 VM 안에 SSH server가 실행 중이어야 한다.

```bash
tart exec ossca-ebpf sudo apt-get install -y openssh-server
tart exec ossca-ebpf sudo systemctl enable --now ssh
```

Mac의 공개키를 VM의 `admin` 계정에 등록한다. 공개키는 host에서 확인한다.

```bash
cat ~/.ssh/id_ed25519.pub
```

출력된 공개키 문자열을 사용해 VM에 등록한다.

```bash
tart exec ossca-ebpf mkdir -p /home/admin/.ssh
tart exec ossca-ebpf chmod 700 /home/admin/.ssh
tart exec ossca-ebpf sh -c 'echo "<public-key>" >> /home/admin/.ssh/authorized_keys'
tart exec ossca-ebpf chmod 600 /home/admin/.ssh/authorized_keys
```

SSH 접속 테스트:

```bash
ssh admin@<vm-ip>
```

VS Code에서 사용하려면 host의 `~/.ssh/config`에 다음처럼 등록한다.

```sshconfig
Host ossca-ebpf
  HostName <vm-ip>
  User admin
  IdentityFile ~/.ssh/id_ed25519
```

VM IP는 재시작 후 바뀔 수 있으므로 접속이 안 되면 `tart ip ossca-ebpf`로 다시 확인한다.

현재 `ossca-ebpf`에는 `openssh-server`가 설치되어 있고, host의 SSH 공개키가 `admin` 계정에 등록되어 있다. VM을 실행한 뒤 다음 명령으로 접속할 수 있다.

```bash
ssh admin@<vm-ip>
```

## 설치한 패키지

VM 기본 이미지에는 Go가 없어서 다음 패키지를 설치했다.

```bash
tart exec ossca-ebpf-work sudo apt-get update
tart exec ossca-ebpf-work sudo apt-get install -y golang-go make curl procps iproute2
```

설치 후 Go 버전:

```text
go version go1.22.2 linux/arm64
```

## Build

VM 내부에서 다음 명령으로 빌드했다.

```bash
tart exec ossca-ebpf make -C /work/01-week/iamywl build
```

빌드 결과:

```text
make: Entering directory '/work/01-week/iamywl'
go build -o app main.go
make: Leaving directory '/work/01-week/iamywl'
```

생성된 결과물:

```text
/work/01-week/iamywl/app
```

Host에서 확인한 바이너리 정보:

```text
ELF 64-bit LSB executable, ARM aarch64, dynamically linked, interpreter /lib/ld-linux-aarch64.so.1
```

## 실행 및 검증

서버 실행:

```bash
tart exec ossca-ebpf sudo /work/01-week/iamywl/app
```

API 요청:

```bash
tart exec ossca-ebpf curl -s -X POST http://127.0.0.1:8080/unshare/netns \
  -H 'Content-Type: application/json' \
  -d '{"path":"/bin/sleep","args":["30"]}'
```

응답:

```json
{"parent_pid":3133,"child_pid":3140}
```

부모 프로세스와 자식 프로세스의 network namespace 확인:

```bash
tart exec ossca-ebpf sudo readlink /proc/3133/ns/net /proc/3140/ns/net
```

결과:

```text
net:[4026531833]
net:[4026532450]
```

두 inode가 다르므로 HTTP API 서버 프로세스와 `/bin/sleep` 자식 프로세스가 서로 다른 network namespace에서 실행됨을 확인했다.

자식 프로세스 종료 후 zombie 확인:

```bash
tart exec ossca-ebpf sh -c 'sleep 35; ps -o pid,ppid,stat,comm -p 3140 || true'
```

결과:

```text
    PID    PPID STAT COMMAND
```

PID `3140`이 남아 있지 않아 `cmd.Wait()`에 의해 종료 처리가 되었음을 확인했다.

## 정리

테스트 후 실행 중인 서버 프로세스를 종료했다.

```bash
tart exec ossca-ebpf sudo kill 3133
```

VM 정지:

```bash
tart stop ossca-ebpf
```

최종 상태 확인 시 `ossca-ebpf`는 `stopped` 상태였다.
