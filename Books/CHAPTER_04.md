<!-- 
[조판 및 폰트 지정 규격 (Typography Specification)]
- 책 본문 (Body Text): Noto Sans KR
- 장/절 제목 (Headings): Noto Sans KR Bold
- 표 (Table): Noto Sans KR
- 캡션 (Caption): Noto Sans KR
- 영문 기술 용어 (Technical Terms): Noto Sans KR
- 코드 및 SQL 블록 (Code & SQL Blocks): DejaVu Sans Mono
-->

# CHAPTER 04. CLI 기반 Oracle Pre-installation 및 커널 최적화

Oracle Database 19c를 Oracle Linux 9(UEK R7) 운영체제에 안정적으로 구축하려면 데이터베이스 엔진 바이너리를 설치하기 전에 OS 사용자 계정과 권한 그룹, 커널 파라미터, 사용자 세션 리소스 제한(`limits`), 대형 메모리 페이지(HugePages), 그리고 비동기 입출력(AIO) 서브시스템을 정밀하게 구성해야 합니다[1].

이 장에서는 **`oracle-database-preinstall-19c`** RPM 패키지를 통한 사전 환경 자동화, 직무 분리(Job Role Separation) 보안 모델에 따른 OS 계정 및 그룹 구성, `/etc/sysctl.d/` 및 `/etc/security/limits.d/` 파라미터 최적화, Transparent HugePages(THP) 비활성화와 Static HugePages 산정, 그리고 UEK R7 커널 환경에서 `io_uring`(`KABI_V3`) 기반의 **ASMLib v3**를 CLI로 구성하는 모범 사례를 단계별로 다룹니다.

---

## 4.1 Automated Pre-installation 패키지 적용

### 4.1.1 `oracle-database-preinstall-19c` RPM의 역할 및 설치

Oracle Linux 9의 기본 AppStream 리포지토리(`ol9_appstream`)는 오라클 데이터베이스 설치에 필요한 필수 OS 패키지 의존성 해결과 커널·리소스 파라미터 자동 구성을 수행하는 **`oracle-database-preinstall-19c`** RPM을 기본 제공합니다[1].

CUI 터미널 환경에서 `dnf` 패키지 관리자를 통해 이 패키지를 설치하면 수십 가지의 사전 요구사항 설정 작업을 일관되고 안전하게 자동화할 수 있습니다[1].

```bash
# oracle-database-preinstall-19c RPM 설치
$ sudo dnf install -y oracle-database-preinstall-19c
```

*표 4-1. `oracle-database-preinstall-19c` RPM의 주요 자동 구성 항목*

| 구성 영역 | 자동 반영되는 상세 내용 |
| :--- | :--- |
| **필수 의존성 패키지** | `bc`, `binutils`, `elfutils-libelf`, `glibc-devel`, `ksh`, `libaio-devel`, `libXrender`, `sysstat`, `smartmontools` 등 필수 라이브러리 자동 설치 |
| **OS 사용자 및 그룹** | 설치 소유자 계정 `oracle`(UID `54321`) 및 표준 관리 그룹(`oinstall`, `dba`, `oper`, `backupdba`, `dgdba`, `kmdba`, `racdba`) 자동 생성 |
| **커널 파라미터(`sysctl`)** | `/etc/sysctl.d/99-oracle-database-preinstall-19c-sysctl.conf` 파일 생성 및 공유 메모리·세마포어·네트워크·AIO 커널 파라미터 즉시 반영 |
| **사용자 리소스 제한(`limits`)** | `/etc/security/limits.d/oracle-database-preinstall-19c.conf` 파일 생성 및 `nofile`, `nproc`, `stack`, `memlock` 상한 설정 |
| **커널 부트 파라미터** | `numa=off` 및 `transparent_hugepage=never` 부트 옵션 설정, 변경 로그를 `/var/log/oracle-database-preinstall-19c/backup/`에 백업 |

---

### 4.1.2 자동 구성 항목의 수동 검증 및 반영 상태 확인

Pre-installation RPM 설치가 완료되면 자동 생성된 `sysctl` 및 `limits` 설정 파일과 백업 로그를 조회하여 시스템 사양에 맞게 파라미터가 정상 반영되었는지 검증합니다[1].

```bash
# 1. preinstall 패키지가 생성한 sysctl 커널 파라미터 설정 파일 확인
$ grep -vE '^#|^$' /etc/sysctl.d/99-oracle-database-preinstall-19c-sysctl.conf

# 2. preinstall 패키지가 생성한 oracle 사용자 리소스 제한(limits) 설정 확인
$ grep -vE '^#|^$' /etc/security/limits.d/oracle-database-preinstall-19c.conf

# 3. preinstall 패키지 작업 이력 로그 확인
$ sudo tail -n 20 /var/log/oracle-database-preinstall-19c/results/orakernel.log
```

---

## 4.2 사용자, 그룹 및 디렉터리 권한 매핑

### 4.2.1 직무 분리(Job Role Separation) 보안 모델 기반 OS 그룹 체계

엔터프라이즈 환경에서는 최소 권한 원칙(Principle of Least Privilege)에 따라 단일 `SYSDBA` 권한에 모든 관리 권한이 집중되는 것을 방지하고, 백업·복구·암호화 키 관리·스토리지 관리 등 직무별로 OS 그룹과 데이터베이스 시스템 권한을 분리하는 **직무 분리(Job Role Separation)** 모델을 적용합니다[1, 2].

`oracle-database-preinstall-19c` 패키지는 데이터베이스 관리 그룹(`oinstall`, `dba`, `oper`, `backupdba`, `dgdba`, `kmdba`, `racdba`)을 자동으로 생성하지만, Oracle Grid Infrastructure(SEHA 또는 Oracle ASM) 운영을 위한 **ASM 전용 그룹(`asmadmin`, `asmdba`, `asmoper`)**은 수동으로 추가 구성해야 합니다[1, 2].

*표 4-2. Oracle Database 19c 및 Grid Infrastructure 표준 OS 권한 그룹 체계*

| OS 그룹명 | 표준 GID | 오라클 권한 명칭 (연동 시스템 권한) | 역할 및 담당 권한 범위 |
| :--- | :---: | :--- | :--- |
| **`oinstall`** | `54321` | **Oracle Inventory Group** | 중앙 인벤토리(`oraInventory`) 및 오라클 소프트웨어 바이너리 소유 기본 그룹(Primary Group) |
| **`dba`** | `54322` | **OSDBA (`SYSDBA`)** | 데이터베이스 인스턴스 전체 관리 및 최고 관리자 권한 |
| **`oper`** | `54323` | **OSOPER (`SYSOPER`)** | 데이터베이스 기동/종료(`STARTUP`/`SHUTDOWN`), 마운트, 백업 등 제한적 운영 권한 |
| **`backupdba`** | `54324` | **OSBACKUPDBA (`SYSBACKUP`)** | RMAN 및 데이터 펌프 기반 백업·복구 작업 전용 권한 |
| **`dgdba`** | `54325` | **OSDGDBA (`SYSDG`)** | Oracle Data Guard 구성 및 운영 전용 권한 (Enterprise Edition 대상) |
| **`kmdba`** | `54326` | **OSKMDBA (`SYSKM`)** | Transparent Data Encryption(TDE) 키스토어 및 암호화 키 관리 권한 |
| **`asmdba`** | `54327` | **OSDBA for ASM (`SYSDBA`)** | DB 인스턴스 및 관리자가 Oracle ASM 스토리지 디스크 그룹에 접근하기 위한 권한 |
| **`asmoper`** | `54328` | **OSOPER for ASM (`SYSOPER`)** | Oracle ASM 인스턴스 기동/종료 및 디스크 그룹 마운트 제한 권한 |
| **`asmadmin`** | `54329` | **OSASM (`SYSASM`)** | Oracle ASM 스토리지 및 디스크 그룹 전체 관리 최고 권한 |
| **`racdba`** | `54330` | **OSRACDBA (`SYSRAC`)** | 클러스터 데이터베이스 일상 관리 권한 (`preinstall` 기본 생성, 19c SE2는 RAC 미지원) |

---

### 4.2.2 CLI 그룹 구성 확인 및 `oracle` 계정 권한 매핑

`-f`(`--force`: 이미 그룹이 존재하면 오류 없이 통과) 옵션을 사용하여 표준 GID 체계를 보장하고, ASM 연동 그룹(`asmdba`, `asmoper`, `asmadmin`)까지 포함하여 `oracle` 계정의 보조 그룹(Secondary Groups)을 완성합니다[1, 2].

```bash
# 1. 데이터베이스 및 ASM 직무 분리 그룹 생성 확인 (-f 옵션으로 기존 그룹 존재 시 정상 통과)
$ sudo groupadd -f -g 54321 oinstall
$ sudo groupadd -f -g 54322 dba
$ sudo groupadd -f -g 54323 oper
$ sudo groupadd -f -g 54324 backupdba
$ sudo groupadd -f -g 54325 dgdba
$ sudo groupadd -f -g 54326 kmdba
$ sudo groupadd -f -g 54327 asmdba
$ sudo groupadd -f -g 54328 asmoper
$ sudo groupadd -f -g 54329 asmadmin
$ sudo groupadd -f -g 54330 racdba

# 2. oracle 계정에 기본 그룹(oinstall) 및 전체 보조 관리 그룹 할당
$ sudo usermod -g oinstall -G dba,oper,backupdba,dgdba,kmdba,asmdba,asmoper,asmadmin,racdba oracle

# 3. oracle 계정 UID/GID 매핑 결과 검증
$ id oracle
uid=54321(oracle) gid=54321(oinstall) groups=54321(oinstall),54322(dba),54323(oper),54324(backupdba),54325(dgdba),54326(kmdba),54327(asmdba),54328(asmoper),54329(asmadmin),54330(racdba)

# 4. oracle 계정 비밀번호 설정
$ sudo passwd oracle
```

---

### 4.2.3 OFA(Optimal Flexible Architecture) 디렉터리 생성 및 소유권 지정

오라클 표준 디렉터리 체계인 **OFA(Optimal Flexible Architecture)** 규격과 Chapter 3에서 마운트한 5개 볼륨 레이아웃에 맞춰 엔진 설치 경로, 인벤토리 경로, 데이터 및 복구 디렉터리를 생성하고 `oracle:oinstall` 소유권과 `775` 접근 권한을 부여합니다[1].

```bash
# 1. OFA 표준 디렉터리 구조 생성
$ sudo mkdir -p /u01/app/oracle/product/19.0.0/dbhome_1
$ sudo mkdir -p /u01/app/oraInventory
$ sudo mkdir -p /u02/oradata
$ sudo mkdir -p /u03/oraredo1
$ sudo mkdir -p /u04/oraredo2
$ sudo mkdir -p /u05/fast_recovery_area

# 2. 디렉터리 소유권(oracle:oinstall) 및 권한(775) 일괄 설정
$ sudo chown -R oracle:oinstall /u01 /u02 /u03 /u04 /u05
$ sudo chmod -R 775 /u01 /u02 /u03 /u04 /u05

# 3. 디렉터리 소유권 및 권한 매핑 검증
$ ls -ld /u01/app/oracle /u01/app/oraInventory /u02/oradata /u03/oraredo1 /u04/oraredo2 /u05/fast_recovery_area
drwxrwxr-x. 3 oracle oinstall 21 Sep 30 10:00 /u01/app/oracle
drwxrwxr-x. 2 oracle oinstall  6 Sep 30 10:00 /u01/app/oraInventory
drwxrwxr-x. 2 oracle oinstall  6 Sep 30 10:00 /u02/oradata
drwxrwxr-x. 2 oracle oinstall  6 Sep 30 10:00 /u03/oraredo1
drwxrwxr-x. 2 oracle oinstall  6 Sep 30 10:00 /u04/oraredo2
drwxrwxr-x. 2 oracle oinstall  6 Sep 30 10:00 /u05/fast_recovery_area
```

---

## 4.3 커널 파라미터 및 사용자 리소스 제한(`limits.conf`) 정밀 설정

### 4.3.1 `/etc/sysctl.d/` 커널 파라미터 검증 및 커스텀 튜닝

`oracle-database-preinstall-19c` 패키지는 `/etc/sysctl.d/99-oracle-database-preinstall-19c-sysctl.conf` 파일에 오라클 공식 권장 커널 파라미터를 자동으로 구성합니다[1]. 서버의 물리 메모리 규모에 맞춰 공유 메모리 파라미터나 HugePages 설정을 추가로 정의할 때는 사전 순(Lexicographical Order)으로 가장 마지막에 로드되도록 `/etc/sysctl.d/99-zz-oracle-custom.conf` 파일에 작성하거나 기본 파일을 점검합니다.

```ini
# /etc/sysctl.d/99-oracle-database-preinstall-19c-sysctl.conf 주요 표준 파라미터
# 1. 파일 핸들 및 비동기 I/O(AIO) 동시 요청 상한
fs.file-max = 6815744
fs.aio-max-nr = 1048576

# 2. 세마포어 파라미터 (semmsl semmns semopm semmni)
kernel.sem = 250 32000 100 128

# 3. System V 공유 메모리 상한 (32 GB RAM 기준 예시: shmmax는 바이트 단위, shmall은 4 KB 페이지 단위)
kernel.shmmax = 34359738368
kernel.shmall = 8388608
kernel.shmmni = 4096

# 4. 커널 패닉 발생 시 자동 재부팅 대기 시간(초) 및 OOM 보호
kernel.panic_on_oops = 1

# 5. 네트워크 소켓 수신(rmem) 및 송신(wmem) 버퍼 크기
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576

# 6. 로컬 임시 포트(Ephemeral Port) 할당 범위
net.ipv4.ip_local_port_range = 9000 65500
```

커널 파라미터 수정 후에는 `sysctl --system` 명령을 실행하여 전체 `/etc/sysctl.d/*.conf` 구성을 커널에 즉시 동기화합니다[1].

```bash
$ sudo sysctl --system
```

---

### 4.3.2 `/etc/security/limits.d/` 사용자 리소스 제한 쿼터 설정

오라클 데이터베이스 백그라운드 프로세스와 서버 프로세스가 수많은 데이터 파일과 클라이언트 소켓을 동시에 처리할 수 있도록 `/etc/security/limits.d/oracle-database-preinstall-19c.conf`에 정의된 오픈 파일 디스크립터 수(`nofile`), 최대 프로세스 수(`nproc`), 스택 크기(`stack`), 메모리 잠금 한계(`memlock`)를 확인합니다[1].

```ini
# /etc/security/limits.d/oracle-database-preinstall-19c.conf
# 오픈 파일 디스크립터 개수 제한 (Soft / Hard)
oracle   soft   nofile    1024
oracle   hard   nofile    65536

# 사용자당 최대 프로세스/스레드 생성 개수 제한 (Soft / Hard)
oracle   soft   nproc     16384
oracle   hard   nproc     16384

# 프로세스 스택 크기 제한 (KB 단위)
oracle   soft   stack     10240
oracle   hard   stack     32768

# 물리 메모리 잠금 한계 (KB 단위: 32 GB RAM의 90%인 약 28.8 GB = 30198988 KB 예시)
oracle   soft   memlock   30198988
oracle   hard   memlock   30198988
```

> ⚠️ **주의(Caution)**: **`memlock` 파라미터 산정 공식 및 주의사항**
> *Oracle Database Installation Guide 19c for Linux*에 따르면 `memlock`(단위: **KB**)은 HugePages를 활성화한 환경에서 **전체 물리 RAM 용량의 최소 90% 이상**(HugePages 미사용 시에도 최소 `3145728` KB = 3 GB 이상)으로 설정해야 하며, 반드시 **Static HugePages 전체 할당 크기($\text{vm.nr\_hugepages} \times 2,048\text{ KB}$)보다 커야 합니다**[1]. 만약 `memlock` 값이 SGA 또는 HugePages 예약 크기보다 작으면 오라클 인스턴스가 기동 시점에 공유 메모리를 잠그지(Lock) 못해 HugePages 할당에 실패하거나 인스턴스 부팅이 거부됩니다.

---

## 4.4 메모리 성능 최적화: Static HugePages 구성 및 THP 비활성화

### 4.4.1 Transparent HugePages(THP) 비활성화 검증

Linux 커널의 **Transparent HugePages(THP)**는 실행 중인 프로세스의 메모리를 커널 백그라운드 스레드(`khugepaged`)가 실시간으로 스캔하여 4 KB 기본 페이지를 2 MB 대형 페이지로 동적 병합(Defragmentation/Compaction)하고 분할하는 기능입니다[1].

그러나 오라클 데이터베이스의 대규모 SGA 공유 메모리 환경에서 THP가 작동하면, 동적 페이지 병합 과정에서 심각한 메모리 할당 락(Lock) 경합과 CPU 스파이크, 디스크 I/O 지연이 발생하며 클러스터 환경에서는 노드 재기동(Node Eviction)을 유발할 수 있습니다[1]. 따라서 오라클 공식 설치 가이드에 따라 **THP는 반드시 비활성화(`never`)**하고 **Static HugePages**를 사용해야 합니다[1].

```mermaid
flowchart TD
    subgraph THP["Transparent HugePages (THP - 비권장)"]
        T1["런타임 중 khugepaged 스레드가<br/>4 KB 페이지를 동적 병합/분할"]
        T2["메모리 락(Lock) 경합, I/O 지연 발생<br/>및 클러스터 노드 응답 정지 위험"]
        T1 --> T2
    end

    subgraph SHP["Static HugePages (오라클 공식 권장)"]
        S1["부팅/초기화 시점에 2 MB 연속 물리 페이지 선점<br/>및 메모리에 영구 고정 (Pinned)"]
        S2["CPU TLB 히트율 극대화, 페이지 테이블 축소,<br/>SGA 영역 Swapping 원천 차단"]
        S1 --> S2
    end
```
*그림 4-1. Transparent HugePages(THP)와 Static HugePages의 동작 메커니즘 비교*

#### THP 비활성화 상태 확인 및 `grubby`를 통한 영구 적용

`oracle-database-preinstall-19c` 패키지를 설치하면 커널 부트 인자에 `transparent_hugepage=never`가 자동 추가되지만, 재부팅 후 실제 커널 메모리 서브시스템에 `[never]`가 적용되었는지 반드시 검증해야 합니다[1, 3].

```bash
# 1. 현재 실행 중인 커널의 THP 활성화 상태 확인 ([never]에 대괄호가 있어야 비활성화 상태)
$ cat /sys/kernel/mm/transparent_hugepage/enabled
always madvise [never]

# 2. 만약 [always] 또는 [madvise]로 표시된다면 grubby로 모든 커널에 영구 비활성화 적용
$ sudo grubby --update-kernel=ALL --args="transparent_hugepage=never"

# 3. 부트 파라미터 반영 확인 (변경 시 재부팅 후 적용됨)
$ sudo grubby --info=DEFAULT | grep transparent_hugepage
args="ro ... console=tty0 console=ttyS0,115200n8 transparent_hugepage=never"
```

---

### 4.4.2 Static HugePages 수식 계산 및 커널 메모리 고정

**Static HugePages**는 운영체제 부팅 또는 커널 파라미터 적용 시점에 물리 메모리에 2 MB(`2048 kB`) 단위의 연속된 대형 페이지 풀을 미리 예약하고 고정(Pinning)하는 기술입니다[1]. 일반 4 KB 페이지 대신 2 MB HugePages를 사용하면 페이지 테이블 엔트리(PTE) 개수가 $\frac{1}{512}$로 줄어들어 수 기가바이트에 달하던 페이지 테이블 메모리 오버헤드가 수십 메가바이트 수준으로 감소하며, CPU의 TLB(Translation Lookaside Buffer) 캐시 히트율이 극대화됩니다[1].

#### 1. Static HugePages 개수(`vm.nr_hugepages`) 산정 공식

Linux x86_64 아키텍처의 기본 `Hugepagesize`인 **2 MB(`2048 kB`)** 환경에서 인스턴스의 최대 SGA 크기(`SGA_MAX_SIZE`)를 수용하기 위한 `vm.nr_hugepages` 계산식은 다음과 같습니다[1].

$$\text{vm.nr\_hugepages} = \left\lceil \frac{\text{SGA\_MAX\_SIZE (MB)}}{\text{Hugepagesize (2 MB)}} \right\rceil + \text{Safety Buffer (10 Pages)}$$

* **산정 예시**: `SGA_MAX_SIZE`(및 `SGA_TARGET`)를 **16 GB(`16,384 MB`)**로 설계한 경우
  $$\text{vm.nr\_hugepages} = \left\lceil \frac{16,384\text{ MB}}{2\text{ MB}} \right\rceil + 10 = 8,192 + 10 = 8,202$$
  *(프로세스 오버헤드 및 SGA 내부 세그먼트 정렬 여유분으로 약 10페이지(20 MB)를 추가합니다.)*

#### 2. `vm.nr_hugepages` 커널 반영 및 할당 검증

```bash
# 1. 커널 파라미터 설정 파일에 vm.nr_hugepages 등록
$ echo "vm.nr_hugepages = 8202" | sudo tee -a /etc/sysctl.d/99-oracle-database-preinstall-19c-sysctl.conf

# 2. 커널 파라미터 즉시 적용
$ sudo sysctl --system

# 3. /proc/meminfo를 통해 HugePages 할당 결과 확인
$ grep Huge /proc/meminfo
AnonHugePages:         0 kB
ShmemHugePages:        0 kB
FileHugePages:         0 kB
HugePages_Total:    8202
HugePages_Free:     8202
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:        16797696 kB
```

> 💡 **노트(Note)**: **`HugePages_Total`이 요청 개수보다 적게 할당될 때의 조치**
> 서버가 장시간 가동되어 물리 메모리 단편화(Fragmentation)가 진행된 상태에서 `sysctl`로 `vm.nr_hugepages`를 동적 변경하면, 연속된 2 MB 공간이 부족하여 `HugePages_Total`이 설정값(`8202`)보다 적게 잡힐 수 있습니다. 이 경우 서버를 **재부팅(`sudo systemctl reboot`)**하면 부팅 초기 단계에서 단편화 없이 전체 HugePages가 100% 정확하게 예약됩니다[1].

---

### 4.4.3 오라클 인스턴스 파라미터 연동 (`USE_LARGE_PAGES = ONLY`)

OS 수준에서 Static HugePages 예약을 마쳤다면, 오라클 데이터베이스 인스턴스가 기동할 때 반드시 HugePages 메모리만 사용하도록 초기화 파라미터 **`USE_LARGE_PAGES`**를 설정합니다[1, 4].

* **`USE_LARGE_PAGES = TRUE`** (기본값): 시스템에 HugePages가 구성되어 있으면 우선 사용하되, 만약 HugePages 여유 공간이 부족하면 남는 SGA 영역을 일반 4 KB 소형 페이지로 혼합 할당하여 기동합니다[4].
* **`USE_LARGE_PAGES = ONLY`** (엔터프라이즈 권장 설정): SGA 전체가 100% HugePages에 매핑될 수 있을 때만 인스턴스 기동을 허용합니다[4]. 만약 HugePages가 부족하면 소형 페이지로 폴백(Fallback)하여 성능이 저하되는 대신 명시적인 오류를 발생시켜 DBA가 즉시 메모리 설정을 교정할 수 있도록 보장합니다(단, `MEMORY_TARGET = 0`이어야 합니다)[1, 4].

```sql
-- 데이터베이스 생성 후 SPFILE에 USE_LARGE_PAGES = ONLY 설정 반영
ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = SPFILE;
ALTER SYSTEM SET USE_LARGE_PAGES = ONLY SCOPE = SPFILE;
```

---

## 4.5 Storage 및 ASMLib v3 구성 모범 사례 (CLI)

### 4.5.1 UEK R7 커널 환경에서의 ASMLib v3(`KABI_V3`) 동작 특성

단일 서버(Oracle Restart) 또는 SEHA 클러스터 환경에서 파일시스템 대신 **Oracle Automatic Storage Management(ASM)**를 사용하는 경우, 디스크 디바이스의 영구적인 이름 유지(Device Persistence)와 권한 관리를 위해 **Oracle ASMLib**(또는 `udev` 규칙)을 구성합니다[2, 5].

Chapter 1에서 살펴본 바와 같이, Oracle Linux 9 및 UEK R7 커널 환경에서는 과거의 커널 모듈 드라이버(`kmod-oracleasm`, `KABI_V2`)가 완전히 제거되었으며, 커널 내장 **`io_uring` 인터페이스(`KABI_V3`)**와 **eBPF 기반 I/O 필터링**을 사용하는 **ASMLib v3(`oracleasm-support` 3.0/3.1 및 `oracleasmlib` 3.0/3.1)**로 아키텍처가 전환되었습니다[5, 6].

*표 4-3. 커널 세대별 Oracle ASMLib 아키텍처 비교*

| 비교 항목 | UEK R6 이하 (ASMLib v2 / Legacy) | Oracle Linux 9 UEK R7 (ASMLib v3 / Current) |
| :--- | :--- | :--- |
| **커널 I/O 인터페이스** | `oracleasm` 전용 커널 모듈 (`KABI_V2`) | 커널 내장 **`io_uring` (`KABI_V3`)** |
| **설치 대상 패키지** | `kmod-oracleasm`, `oracleasm-support`, `oracleasmlib` | **`oracleasm-support`**, **`oracleasmlib`** (커널 모듈 불필요) |
| **I/O 보호 필터링** | 미지원 (별도 ASMFD 드라이버 필요) | **eBPF 기반 I/O Filter 기본 내장** (`--iofilter y`) |
| **디스크 식별 및 Thin Provisioning** | 장치 번호(Major/Minor) 기반 식별 | SCSI/NVMe 하드웨어 UUID 디스커버리 및 UNMAP 지원 |

---

### 4.5.2 `io_uring` 보안 그룹 권한 설정 (`/etc/sysctl.d/io_uring.conf`)

ASMLib v3가 `io_uring` 시스템 콜 인터페이스를 통해 ASM 디스크에 접근할 수 있도록 `/etc/sysctl.d/io_uring.conf` 파일에 보안 그룹 권한을 설정합니다[6]. 이때 `kernel.io_uring_group`에 지정하는 GID는 `oracleasm configure`에서 지정할 ASM 디스크 소유 그룹(예: `dba` 그룹 `54322` 또는 `asmadmin` 그룹 `54329`, 기본 그룹 `oinstall` `54321`)과 일치시켜야 합니다[6].

```bash
# 1. io_uring 보안 그룹 권한 설정 파일 생성 (dba 그룹 GID 54322 기준)
$ cat << 'EOF' | sudo tee /etc/sysctl.d/io_uring.conf
kernel.io_uring_disabled = 1
kernel.io_uring_group = 54322
EOF

# 2. sysctl 파라미터 즉시 반영 및 확인
$ sudo sysctl -p /etc/sysctl.d/io_uring.conf
kernel.io_uring_disabled = 1
kernel.io_uring_group = 54322
```

---

### 4.5.3 ASMLib v3 패키지 설치, 초기화 및 ASM 디스크 라벨링 절차

#### 1. `ol9_addons` 리포지토리 활성화 및 ASMLib v3 패키지 설치

Oracle Linux 9에서 `oracleasm-support` 패키지는 **`ol9_addons`** 리포지토리에서 제공되며, 사용자 공간 디스커버리 라이브러리인 `oracleasmlib` 패키지는 ULN(Unbreakable Linux Network) 또는 오라클 공식 ASMLib 다운로드 페이지(`https://www.oracle.com/linux/downloads/linux-asmlib-v9-downloads.html`)에서 확보하여 설치합니다[6].

```bash
# 1. ol9_addons 리포지토리 활성화 및 oracleasm-support 설치
$ sudo dnf config-manager --set-enabled ol9_addons
$ sudo dnf install -y oracleasm-support

# 2. 다운로드한 oracleasmlib 3.1 RPM 패키지 설치 (또는 ULN 리포지토리에서 직접 설치)
$ sudo dnf install -y https://yum.oracle.com/repo/OracleLinux/OL9/addons/x86_64/getPackage/oracleasmlib-3.1.0-1.el9.x86_64.rpm
```

#### 2. `oracleasm configure` 비대화형 초기화 및 서비스 활성화

비대화형(Non-interactive) CLI 옵션을 사용하여 디스크 소유자(`-u oracle`), 소유 그룹(`-g dba` 또는 `asmadmin`), 부팅 시 자동 활성화(`-e`), 부팅 시 디스크 자동 스캔(`-s y`), 그리고 eBPF 기반 I/O 필터(`--iofilter y`)를 한 번에 구성합니다[6].

```bash
# 1. 비대화형 CLI 옵션으로 ASMLib v3 환경 설정 구성
$ sudo oracleasm configure -u oracle -g dba -e -s y --iofilter y
Writing Oracle ASM library driver configuration: done

# 2. oracleasm systemd 서비스 활성화 및 시작
$ sudo systemctl enable --now oracleasm

# 3. oracleasm init 실행으로 io_uring 인터페이스 초기화 확인
$ sudo oracleasm init
Checking if the oracleasm kernel module is loaded: no (Not required with kernel 5.15.0)
Checking if /dev/oracleasm is mounted: no (Not required with kernel 5.15.0)
Checking which I/O Interface is in use: io_uring (KABI_V3)
Checking if io_uring is enabled: yes
Checking if io_uring is accessible to the configured DB user: yes
```

#### 3. ASM 전용 디스크 라벨링(`createdisk`) 및 상태 검증

ASM 디스크 그룹으로 사용할 전용 물리 파티션(예: `/dev/sdd1`, `/dev/sde1`)에 ASM 디스크 라벨을 기록하고 `scandisks`, `listdisks`, `status` 명령으로 정상 작동 여부를 검증합니다[6].

```bash
# 1. ASM 전용 파티션에 디스크 라벨 생성 (createdisk)
$ sudo oracleasm createdisk DATA1 /dev/sdd1
Writing disk header: done
Instantiating disk: done

$ sudo oracleasm createdisk FRA1 /dev/sde1
Writing disk header: done
Instantiating disk: done

# 2. ASM 디스크 스캔 및 등록된 디스크 목록 확인
$ sudo oracleasm scandisks
Reloading disk partitions: done
Cleaning any stale ASM disks...
Setting up iofilter map for ASM disks: done
Scanning system for ASM disks...

$ sudo oracleasm listdisks
DATA1
FRA1

# 3. ASMLib v3 및 io_uring / eBPF I/O 필터 종합 상태 검증
$ sudo oracleasm status
Checking if the oracleasm kernel module is loaded: no (Not required with kernel 5.15.0)
Checking if /dev/oracleasm is mounted: no (Not required with kernel 5.15.0)
Checking which I/O Interface is in use: io_uring (KABI_V3)
Checking if ASMLIB can be loaded: yes
Checking if io_uring is enabled: yes
Checking if io_uring is accessible to the configured DB user: yes
Checking if ASM disks have the correct ownership and permissions: yes
Checking if ASM I/O filter is set up: yes
```

---

## 4.6 장 요약 (Chapter Summary)

이 장에서는 Oracle Database 19c 엔진 설치에 앞서 Oracle Linux 9(UEK R7) 운영체제의 커널 및 보안·메모리 환경을 최적화하는 전 과정을 수행했습니다.

* **Automated Pre-installation 및 직무 분리 그룹**: `oracle-database-preinstall-19c` RPM을 통해 필수 패키지와 기본 계정을 자동 구성하고, 최소 권한 원칙에 입각한 직무 분리(Job Role Separation) 그룹(`oinstall`, `dba`, `oper`, `backupdba`, `dgdba`, `kmdba`, `asmdba`, `asmoper`, `asmadmin`, `racdba`) 및 OFA 디렉터리 권한을 확립했습니다.
* **커널 파라미터 및 리소스 제한(`limits`)**: `/etc/sysctl.d/`와 `/etc/security/limits.d/`를 통해 공유 메모리, 세마포어, 비동기 I/O(`fs.aio-max-nr`), 파일 디스크립터(`nofile`), 그리고 전체 RAM의 90% 이상을 허용하는 `memlock` 쿼터를 구성했습니다.
* **THP 비활성화 및 Static HugePages 고정**: 런타임 메모리 지연을 유발하는 Transparent HugePages(THP)가 `[never]` 상태임을 검증하고, 목표 SGA 크기에 맞춘 `vm.nr_hugepages` 예약과 오라클 `USE_LARGE_PAGES = ONLY` 파라미터 연동을 통해 메모리 성능을 극대화했습니다.
* **UEK R7 기반 ASMLib v3(`KABI_V3`) 구성**: ASM 스토리지를 사용하는 환경을 위해 `kernel.io_uring_group` 보안 설정과 `oracleasm-support`·`oracleasmlib` v3 패키지를 구성하고, 커널 모듈 없이 `io_uring`과 eBPF I/O 필터링 기반으로 ASM 디스크를 라벨링했습니다.

다음 **CHAPTER 05**에서는 준비된 OS 환경 위에 오라클 계정 환경 변수(`.bash_profile`)를 설정하고, Oracle Database 19c 골드 이미지 압축 해제, `db_install.rsp` 응답 파일 작성, `runInstaller -silent -applyRU`를 통한 무인 엔진 설치 및 `root.sh` 스크립트 실행 절차를 상세히 다룹니다.

---

# References

[1] Oracle. 2024. *Oracle Database Installation Guide 19c for Linux (E96272)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/
[2] Oracle. 2024. *Oracle Grid Infrastructure Installation and Upgrade Guide 19c for Linux (E96273)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/database/oracle/oracle-database/19/cwlin/
[3] Oracle. 2024. *Oracle Linux 9: Managing Kernels and System Boot (F52963)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/operating-systems/oracle-linux/9/boot/
[4] Oracle. 2024. *Oracle Database Reference 19c (E96200)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/
[5] Oracle. 2024. *Oracle Automatic Storage Management Administrator's Guide 19c (E96190)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/database/oracle/oracle-database/19/ostmg/
[6] Oracle. 2024. *Oracle Linux 9: Managing Storage Devices and ASMLib v3 (io_uring KABI_V3) Documentation*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/operating-systems/oracle-linux/9/
