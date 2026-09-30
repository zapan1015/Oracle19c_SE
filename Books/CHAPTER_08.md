# CHAPTER 08. Oracle Linux 9 환경에서의 19c 메모리 최적화

Oracle Database 19c 인스턴스의 안정성과 처리 성능은 운영체제(OS)의 물리 메모리 관리 방식과 오라클 내부 메모리 아키텍처의 유기적 결합에 의해 결정됩니다. 특히 Oracle Linux 9 UEK R7 환경에서 대용량 데이터베이스를 운영할 때는 가상 메모리 페이징(Paging) 및 스와핑(Swapping) 오버헤드를 방지하기 위한 정밀한 메모리 커널 튜닝이 필수적입니다.

본 장에서는 AMM과 ASMM 메모리 관리 아키텍처의 차이와 Linux 제약사항, Static HugePages와 `USE_LARGE_PAGES=ONLY` 파라미터를 활용한 SGA 메모리 고정 매핑 기법, 그리고 `/dev/shm` (tmpfs) 공유 메모리 파일시스템 튜닝 절차를 단계별로 다룹니다.

---

## 8.1 메모리 관리 방식 선택: AMM vs ASMM (Linux 제약)

### AMM과 ASMM 아키텍처 비교

Oracle Database는 오라클 인스턴스의 System Global Area(SGA)와 Program Global Area(PGA) 메모리를 관리하기 위한 자동화 메커니즘을 제공합니다.

1. **자동 메모리 관리 (AMM, Automatic Memory Management)**: `MEMORY_TARGET` 및 `MEMORY_MAX_TARGET` 파라미터를 설정하여 오라클이 워크로드 변화에 따라 SGA와 PGA 간 메모리를 동적으로 재배분하는 방식입니다.
2. **자동 공유 메모리 관리 (ASMM, Automatic Shared Memory Management)**: `SGA_TARGET` 파라미터로 SGA 통합 크기를 제어하고, `PGA_AGGREGATE_TARGET` 파라미터로 PGA 메모리를 독립적으로 자동 관리하는 방식입니다.

```
[ AMM 방식 (MEMORY_TARGET) ]
┌────────────────────────────────────────────────────────┐
│ Total Memory Target (SGA ↔ PGA Dynamic Exchange)        │
└────────────────────────────────────────────────────────┘
  * Linux 환경에서 4GB 이하 및 Small Page(4KB) 전용

[ ASMM 방식 (SGA_TARGET + PGA_AGGREGATE_TARGET) ]
┌──────────────────────────────┐  ┌──────────────────────┐
│ SGA Target (Static HugePages)│  │ PGA Aggregate Target │
└──────────────────────────────┘  └──────────────────────┘
  * 엔터프라이즈 환경 권장 (Static HugePages 2MB 매핑)
```

---

### Linux 플랫폼에서의 AMM 4GB 한계 및 제약사항

엔터프라이즈 데이터베이스 구축 시 Linux OS 환경에서는 다음과 같은 기술적 제약으로 인해 AMM(`MEMORY_TARGET`) 사용이 엄격히 제한되므로 **ASMM 방식을 채택해야 합니다**.

* **물리 메모리 4GB 초과 시 AMM 사용 불가**: 인스턴스의 물리 메모리가 **4GB를 초과**하면 오라클 설치 프로그램(OUI) 및 DBCA 생성 과정에서 AMM(`AUTO` / `MEMORY_TARGET`) 옵션을 선택할 수 없습니다.
* **HugePages 호환성 상충**: Linux 환경에서 AMM은 SGA 메모리를 `/dev/shm` 상의 가상 파일 형태로 할당받으므로, Linux 커널의 Static HugePages(대형 페이지) 메모리 영역을 사용할 수 없습니다.
* **소형 페이지(4KB) 할당 및 Page Table 오버헤드**: AMM을 사용할 경우 SGA 메모리가 기본 4KB 소형 페이지 단위로 쪼개어 매핑되므로, 대용량 SGA 환경에서 OS의 Page Table 관리에 과도한 CPU 및 메모리 자원이 낭비됩니다.
* **`LOCK_SGA` 및 `USE_LARGE_PAGES=ONLY` 제약**: `LOCK_SGA = TRUE` 또는 `USE_LARGE_PAGES = ONLY` 설정이 적용된 상태에서 `MEMORY_TARGET`을 지정하면 오라클 인스턴스가 기동에 실패합니다.

#### 표 8-1. AMM과 ASMM 성능 및 구성 제약 비교

| 항목 | 자동 메모리 관리 (AMM) | 자동 공유 메모리 관리 (ASMM) |
| :--- | :--- | :--- |
| **제어 파라미터** | `MEMORY_TARGET`, `MEMORY_MAX_TARGET` | `SGA_TARGET`, `PGA_AGGREGATE_TARGET` |
| **RAM 4GB 초과 환경** | 사용 불가 (DBCA 및 OUI 제한) | **필수 채택 권장** |
| **Linux HugePages 지원** | 미지원 (`/dev/shm` 파일 할당 방식) | **완벽 지원** (Static HugePages 2MB 연동) |
| **메모리 고정 (`LOCK_SGA`)** | 동시 사용 불가 | 동시 사용 가능 |
| **권장 워크로드** | 4GB 이하 소규모 테스트 인스턴스 | 중대형 엔터프라이즈 OLTP / DW 시스템 |

---

### AMM에서 ASMM으로의 전환 SQL 절차

기존에 AMM으로 생성된 데이터베이스를 ASMM 방식으로 전환하기 위해 `MEMORY_TARGET`을 0으로 비활성화하고 `SGA_TARGET` 및 `PGA_AGGREGATE_TARGET` 파라미터를 명시적으로 할당합니다.

```sql
-- 1. 현재 메모리 구성 상태 점검
SQL> SHOW PARAMETER TARGET

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
memory_max_target                    big integer 8G
memory_target                        big integer 8G
pga_aggregate_target                 big integer 0
sga_target                           big integer 0

-- 2. AMM 비활성화 및 ASMM 파라미터 설정 (SPFILE 반영)
SQL> ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = SPFILE;
SQL> ALTER SYSTEM SET MEMORY_MAX_TARGET = 0 SCOPE = SPFILE;
SQL> ALTER SYSTEM SET SGA_TARGET = 6G SCOPE = SPFILE;
SQL> ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 2G SCOPE = SPFILE;

-- 3. 인스턴스 재부팅을 통한 파라미터 적용
SQL> SHUTDOWN IMMEDIATE;
SQL> STARTUP;

-- 4. 전환 결과 검증
SQL> SHOW PARAMETER TARGET

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
memory_max_target                    big integer 0
memory_target                        big integer 0
pga_aggregate_target                 big integer 2G
sga_target                           big integer 6G
```

---

## 8.2 HugePages 고정 설정 (`USE_LARGE_PAGES=ONLY`)

### Linux Static HugePages (2MB)와 SGA의 1:1 매핑 원리

Linux 커널의 기본 가상 메모리 페이지 크기는 **4KB**입니다. 만약 64GB 크기의 SGA를 4KB 페이지 단위로 관리할 경우, OS 커널은 1,600만 개가 넘는 Page Table Entry(PTE)를 지속적으로 관리해야 하므로 CPU의 TLB(Translation Lookaside Buffer) 미스 현상이 급증하고 성능이 저하됩니다.

Linux **Static HugePages**는 메모리 페이지 크기를 **2MB** 단위로 확대하여 OS 개시 시점에 미리 연속된 물리 메모리를 선점하는 기술입니다.

```mermaid
graph TD
    subgraph Linux Default Page (4KB)
        Page4K[SGA 64GB = 16,777,216 Page Entries] -->|TLB Miss Increase & High Memory Lock| CPU1[CPU Memory Overhead]
    end

    subgraph Static HugePages (2MB)
        Page2M[SGA 64GB = 32,768 HugePage Entries] -->|TLB Hit Max & Zero Swapping| CPU2[Optimal Database Performance]
    end
```

#### Static HugePages 적용 시 얻을 수 있는 핵심 이점

1. **TLB Hit 비율 극대화**: 페이지 테이블 엔트리 수가 1/512로 줄어들어 CPU 가상 메모리 주소 변환 성능이 극대화됩니다.
2. **SGA Swapping 방지**: HugePages로 할당된 메모리 영역은 OS에 의해 디스크로 Paging-out(Swapping)되지 않고 물리 RAM에 고정(Pinned)됩니다.
3. **페이지 테이블 메모리 절감**: 커널이 유지해야 하는 페이지 테이블 자원이 수 GB 단위에서 수 MB 단위로 감소합니다.

---

### `USE_LARGE_PAGES` 파라미터 옵션별 상세 비교

오라클 데이터베이스는 인스턴스 기동 시 Static HugePages 활용 방식을 제어하기 위해 **`USE_LARGE_PAGES`** 초기화 파라미터를 제공합니다.

#### 표 8-2. `USE_LARGE_PAGES` 설정값별 동작 특성

| 설정값 | 동작 메커니즘 및 특성 |
| :--- | :--- |
| **`TRUE`** | HugePages가 설정되어 있으면 이를 사용하고, 설정량이 부족하면 잔여 SGA를 일반 4KB 소형 페이지로 혼용 할당(Mixed Page Mode)하여 시작합니다. |
| **`FALSE`** | HugePages를 전혀 사용하지 않고 모든 SGA를 소형 4KB 페이지로 할당합니다. 성능 저하를 유발하므로 권장하지 않습니다. |
| **`AUTO`** | 인스턴스 시작 시 필요 HugePages 개수를 계산하여 OS에 동적 요청합니다. |
| **`ONLY`** | **SGA 전체가 100% HugePages에 매핑될 수 있을 때만 인스턴스 기동을 허용합니다.** HugePages가 단 1MB라도 부족하면 인스턴스 시작이 거부됩니다. |
| **`AUTO_ONLY`** | 인스턴스 시작 시 HugePages를 동적 요청하며, 100% 할당에 성공한 경우에만 부팅을 허용합니다. |

> **💡 [Technical Note] MAA(Maximum Availability Architecture) 모범 사례**
> 오라클 MAA 가이드라인에서는 **`USE_LARGE_PAGES = ONLY`** 설정을 최우선 모범 사례로 권장합니다. HugePages 용량이 부족한 상태에서 일반 4KB 페이지로 혼용 기동(Mixed Page)되면 런타임 중 memory fragmentation 및 ORA-04030 에러가 유발될 수 있으므로, 시작 시점에 이를 원천 차단하는 것이 시스템 안정성에 유리합니다.

---

### `USE_LARGE_PAGES=ONLY` 설정 및 alert.log 검증

#### 1. SPFILE 파라미터 적용

SQL*Plus에서 `USE_LARGE_PAGES` 값을 `ONLY`로 지정합니다.

```sql
SQL> ALTER SYSTEM SET USE_LARGE_PAGES = ONLY SCOPE = SPFILE;
```

#### 2. `limits.conf` 및 `vm.nr_hugepages` 사전 연동 필수 조건

`USE_LARGE_PAGES = ONLY` 설정이 작동하려면 Chapter 4에서 구성한 다음 OS 커널 요건이 완벽히 충족되어야 합니다.

* `/etc/security/limits.d/99-oracle.conf` 파일의 **`memlock`** 수치가 SGA 전체 크기보다 크게 설정되어 있어야 합니다.
* `/etc/sysctl.d/99-oracle.conf` 파일의 **`vm.nr_hugepages`** 개수가 `SGA_TARGET`을 2MB로 나눈 개수보다 커야 합니다.

#### 3. 인스턴스 구동 및 `alert.log` 출력 검증

`USE_LARGE_PAGES = ONLY` 설정 후 인스턴스를 시작하면 `$ORACLE_BASE/diag/rdbms/<db_name>/<SID>/trace/alert_<SID>.log` 파일에 HugePages 할당 성공 내역이 기록됩니다.

```text
# alert_orcl.log 정상 출력 내용
Starting ORACLE instance (normal)
...
Recommended System Configuration:
  Configure Large Pages allocable through sysctl parameter vm.nr_hugepages
...
SGA allocated 6144 MB Size Large Pages Metric
Large Pages Information :
  Total Shared Global Area size : 6144 MB
  Large Pages configured : 3075
  Large Page size : 2048 KB
  Total Large Pages allocated for SGA : 3072
  Maximum Size of Large Pages Allocated : 6144 MB
  Result of Large Pages allocation : SUCCESS (ONLY)
```

만약 OS의 HugePages 용량이 부족한 상태에서 `USE_LARGE_PAGES = ONLY`로 기동을 시도하면 인스턴스는 시작하지 않고 다음과 같이 에러를 출력하며 구동이 중단됩니다.

```text
# alert_orcl.log 오류 출력 내용
************************************************──────────────────────
ERROR:
  Failed to allocate shared memory segment of size 6442450944 bytes.
  HugePages configuration is insufficient. USE_LARGE_PAGES is set to ONLY.
  Instance shutdown initiated.
************************************************──────────────────────
ORA-27102: out of memory
Linux-x86_64 Error: 12: Cannot allocate memory
```

---

## 8.3 `/dev/shm` 마운트 크기 산정 및 커널 튜닝

### Linux Shared Memory (`/dev/shm`, tmpfs) 파일시스템의 역할

Linux 운영체제의 **`/dev/shm`**은 가상 메모리 기반의 래피드 shared memory 파일시스템(tmpfs)입니다. 오라클 데이터베이스가 AMM(`MEMORY_TARGET`) 모드로 동작할 경우, SGA 및 PGA 메모리 구조가 `/dev/shm` 아래의 가상 공유 메모리 파일로 할당받아 작동합니다.

ASMM(`SGA_TARGET`) 및 Static HugePages 환경을 사용할 때에도 오라클 일부 프로세스 간 통신(IPC) 및 템포러리 메모리 할당을 위해 `/dev/shm` 마운트 디렉토리가 올바른 크기로 확보되어 있어야 합니다.

---

### `/dev/shm` 용량 부족 시 발생하는 `ORA-00845` 에러 원인 및 분석

`/dev/shm` 마운트 지점의 물리적 용량이 오라클 인스턴스의 `MEMORY_TARGET` 또는 `SGA_MAX_SIZE` 파라미터 설정값보다 작게 지정되어 있으면 데이터베이스 부팅 시 **`ORA-00845`** 에러가 발생합니다.

```text
SQL> STARTUP
ORA-00845: MEMORY_TARGET not supported on this system
```

* **원인**: Linux 커널이 `/dev/shm` 공간 상에서 오라클이 요청한 최소 공유 메모리 세그먼트 용량을 수용하지 못하여 시스템 콜을 거부하기 때문입니다.

---

### `/etc/fstab` 마운트 설정 및 런타임 적용 절차

`/dev/shm` 마운트 크기는 최소 `MEMORY_MAX_TARGET` 또는 `SGA_MAX_SIZE` 용량보다 크거나 같게 지정해야 합니다.

#### 1. 런타임 동적 마운트 크기 변경 (`mount -o remount`)

서버 재부팅 없이 런타임 상태에서 `/dev/shm` 용량을 즉시 확장 적용합니다.

```bash
# /dev/shm 용량을 12GB로 동적 재마운트 (root 계정)
$ sudo mount -o remount,size=12g /dev/shm
```

#### 2. `/etc/fstab` 영구 마운트 설정 등록

서버 재부팅 후에도 확대된 `/dev/shm` 용량이 고정 유지되도록 `/etc/fstab` 파일에 `size` 옵션을 명시합니다.

```ini
# /etc/fstab
tmpfs                   /dev/shm                tmpfs   defaults,size=12g        0 0
```

#### 3. CLI 마운트 크기 검증

`df -h /dev/shm` 명령을 실행하여 마운트된 tmpfs 파일시스템의 용량을 최종 검증합니다.

```bash
# /dev/shm 마운트 상태 확인
$ df -h /dev/shm
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            12G  168K   12G   1% /dev/shm
```

---

### 💬 기획 편집자 노트 (Next Step)

Chapter 8에서는 AMM vs ASMM의 Linux 제약사항, Static HugePages와 `USE_LARGE_PAGES=ONLY` 파라미터를 통한 SGA 메모리 고정 매핑, 그리고 `/dev/shm` 마운트 커널 튜닝을 정밀하게 다루었습니다.

이어지는 **CHAPTER 09**에서는 OPatch 유틸리티 최신화, `opatch apply -silent`를 활용한 19c Release Update(RU) 및 MRP 패치 적용, 그리고 Post-Patch 데이터 카탈로그 업데이트를 위한 `datapatch` 스크립트 실행 절차를 다룰 예정입니다. CHAPTER 09 본문 집필을 계속 진행할까요?
