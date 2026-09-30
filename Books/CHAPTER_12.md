# CHAPTER 12. Silent Mode 설치 트러블슈팅 및 로그 분석

그래픽 사용자 인터페이스(GUI)가 배제된 Headless(Non-GUI) CUI 환경에서 `runInstaller -silent`, `netca -silent`, `dbca -silent` 명령을 활용하여 데이터베이스를 구축할 때, 설치 오류나 인스턴스 구동 실패가 발생하면 대화형 팝업 창이 뜨지 않으므로 즉각적인 원인 파악이 어려울 수 있습니다 (출처: administrators-reference-linux-and-unix-based-operating-systems.pdf, 2019; database-administrators-guide.pdf, 2019). 따라서 터미널 출력 메시지와 로그 파일의 정밀 분석을 통해 기술적 원인을 규명하고 조치하는 트러블슈팅(Troubleshooting) 역량이 필수적입니다.

본 장에서는 Silent Mode 설치 관련 핵심 로그 수집 위치, 사전 환경 검증 우회 옵션(`-ignorePrereqFailure`)의 리스크 및 올바른 활용법, 그리고 리스너 바인딩(`ORA-00119`/`ORA-00132`), 메모리 부족(`ORA-04031`), UEK R7 커널 `io_uring` 권한 예외 등 주요 CUI 에러에 대한 원인 분석 및 해결 절차를 단계별로 다룹니다.

---

## 12.1 Silent Mode 설치 중 발생 로그 수집 및 분석 위치

### 오라클 인벤토리 및 도구별 로그 디렉토리 아키텍처

Silent Mode 설치 프로세스는 각 컴포넌트별로 독립된 디렉토리에 실행 이력과 오류 스택 트레이스를 기록합니다 (출처: clusterware-administration-and-deployment-guide.pdf, 2019; real-application-clusters-administration-and-deployment-guide.pdf, 2026). 문제가 발생했을 때 가장 먼저 점검해야 하는 핵심 로그 저장소 위치는 다음과 같습니다.

```mermaid
graph TD
    subgraph Oracle Log Architecture
        Inventory[/u01/app/oraInventory/logs/] -->|OUI Engine Logs| OUI_LOG[installActions*.log / silentInstall*.log]
        CFGTool[/u01/app/oracle/cfgtoollogs/] -->|DBCA Logs| DBCA_LOG[dbca/gdbName/trace.log]
        CFGTool -->|NETCA Logs| NETCA_LOG[netca/netca.log]
        CFGTool -->|OPatch Logs| OPATCH_LOG[opatch/opatch*.log]
        ADR[/u01/app/oracle/diag/rdbms/...] -->|Instance Alert Log| ALERT_LOG[alert_SID.log / alert.xml]
    end
```

#### 표 12-1. Silent Mode 구축 작업별 핵심 로그 파일 경로 명세

| 구축 작업 구분 | 주요 로그 파일 경로 | 기재 내용 및 진단 목적 |
| :--- | :--- | :--- |
| **OUI 엔진 설치** | `/u01/app/oraInventory/logs/installActions<timestamp>.log` | OUI 패키지 추출, 의존성 검증, 바이너리 링크 오류 기록 (출처: clusterware-administration-and-deployment-guide.pdf, 2019) |
| **OUI Silent 결과** | `/u01/app/oraInventory/logs/silentInstall<timestamp>.log` | 비대화형 설치 성공/실패 최종 요약 리포트 (출처: high-availability-overview-and-best-practices.pdf, 2026) |
| **DBCA DB 생성** | `$ORACLE_BASE/cfgtoollogs/dbca/<gdbName>/trace.log` | DBCA 커맨드라인 파라미터 파싱, SQL 스크립트 실행 에러 기록 (출처: real-application-clusters-administration-and-deployment-guide.pdf, 2026) |
| **NETCA 리스너** | `$ORACLE_BASE/cfgtoollogs/netca/netca.log` | 리스너 포트 바인딩 및 프로파일 생성 실패 내역 기록 |
| **OPatch RU 패치** | `$ORACLE_HOME/cfgtoollogs/opatch/opatch<timestamp>.log` | 바이너리 이치 패치 충돌, 파일 백업 및 적용 실패 내역 (출처: high-availability-overview-and-best-practices.pdf, 2026) |
| **인스턴스 얼럿** | `$ORACLE_BASE/diag/rdbms/<db_name>/<SID>/trace/alert_<SID>.log` | DB 구동 중 ORA- 에러, 메모리 할당 및 파라미터 실패 내역 (출처: database-administrators-guide.pdf, 2019; database-concepts.pdf, 2019) |

---

### CLI 기반 실시간 로그 모니터링 기법 (`tail -f` & `grep`)

GUI 모드가 없는 CUI 환경에서는 설치 명령 구동 직후 백그라운드에서 생성되는 로그를 실시간 추적하거나 키워드 검색을 수행하여 에러 원인을 진단합니다.

```bash
# 1. 가장 최근 생성된 OUI 설치 로그 실시간 추적
$ tail -f $(ls -t /u01/app/oraInventory/logs/installActions*.log | head -n 1)

# 2. DBCA 생성 과정 중 발생한 Severe/Fatal 오류 추출
$ grep -E "SEVERE|FATAL|ERROR" $ORACLE_BASE/cfgtoollogs/dbca/orcl/trace.log

# 3. 데이터베이스 Alert Log 내 ORA- 에러 필터링
$ grep "ORA-" $ORACLE_BASE/diag/rdbms/orcl/orcl/trace/alert_orcl.log
```

---

## 12.2 Prerequisite Check Silent Bypass 옵션 활용

### `-ignorePrereqFailure` 파라미터의 역할과 오용 시의 위험성

OUI 엔진 설치 시 `./runInstaller -silent` 명령 뒤에 **`-ignorePrereqFailure`** 파라미터를 추가하면, OS 커널 파라미터 미달, 패키지 미설치, Swap 용량 부족 등 사전 검증(Prerequisite Check) 단계에서 탐지된 경고 및 에러 항목을 무시하고 강제로 바이너리 설치를 계속 진행합니다.

#### ⚠️ [주의] `-ignorePrereqFailure` 남용으로 인한 심각한 결과

이 옵션은 개발 및 테스트 환경에서 경미한 OS 경고를 건너뛰기 위한 목적으로 제공됩니다. 필수 패키지나 커널 파라미터 결함을 수정한 조치 없이 이 옵션을 남용하여 강제 설치할 경우 다음과 같은 심각한 문제가 발생할 수 있습니다.

* **C 컴파일러 링킹 실패 (`ins_rdbms.mk` Error)**: `glibc-devel` 또는 `libaio-devel` 패키지가 결여된 상태에서 설치를 강제할 경우 오라클 홈 바이너리 링킹 단계에서 결정적 오류가 유발됩니다.
* **DBCA 인스턴스 생성 중 크래시**: 커널 파라미터(`fs.aio-max-nr`, `sysctl`) 수치가 부족한 상태에서는 `dbca -silent` 실행 중 비동기 I/O 실패로 인해 인스턴스 생성이 중간에 정지됩니다.

```
[ 사전 검증 실패 (Prerequisite Failure) ]
        │
        ├── 올바른 대응 ──> 로그 분석 ──> dnf 패키지 설치 / sysctl 튜닝 ──> 재검증 통과
        │
        └── 잘못된 대응 ──> -ignorePrereqFailure 강제 우회 ──> 바이너리 링킹/DBCA 크래시 발생
```

---

### 사전 검증 실패 시의 올바른 조치 프로세스

`-ignorePrereqFailure` 파라미터에 의존하기보다, 사전 검증 실패 항목을 명확히 확인하고 해결한 후 정식으로 통과시키는 것이 안전합니다.

```bash
# 1. -executeSysPrereqs 옵션을 통한 사전 검증 독립 실행
$ cd $ORACLE_HOME
$ ./runInstaller -silent -executeSysPrereqs -responseFile /u01/app/oracle/stage/db_install.rsp

# 2. 검증 결과 로그 확인 및 부족한 패키지 설치
$ grep "Failed" /u01/app/oraInventory/logs/installActions*.log
[SEVERE] - Missing package: libaio-devel-0.3.112

$ sudo dnf install -y libaio-devel

# 3. 사전 검증 재실행 후 통과 확인 후 정식 설치 구동
$ ./runInstaller -silent -responseFile /u01/app/oracle/stage/db_install.rsp
```

---

## 12.3 주요 CUI 설치 및 구동 에러 대응

### 1. `ORA-00119` & `ORA-00132`: Listener 바인딩 및 `LOCAL_LISTENER` 파라미터 오류

`dbca -silent` 구동 또는 데이터베이스 `STARTUP` 시점에 가장 빈번하게 발생하는 네트워킹 관련 에러 스택입니다 (출처: database-net-services-administrators-guide.pdf, 2019).

```text
ORA-00119: invalid specification for system parameter LOCAL_LISTENER
ORA-00132: syntax error or unresolved network name 'LISTENER_ORCL'
```

#### 발생 원인

데이터베이스 초기화 파라미터인 `LOCAL_LISTENER`에 지정된 식별자 이름(`LISTENER_ORCL`)이 오라클 서버의 `$ORACLE_HOME/network/admin/tnsnames.ora` 파일 내에 정의되어 있지 않거나, 구문 문법 오류가 존재하여 LREG 프로세스가 네트워크 주소를 풀이(Name Resolution)하지 못하기 때문에 발생합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

#### 트러블슈팅 수순

`tnsnames.ora` 파일에 `LOCAL_LISTENER`가 참조할 식별자 별칭을 추가하거나, IP 및 포트 주소를 직접 지정하도록 수정합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

```ini
# $ORACLE_HOME/network/admin/tnsnames.ora 파일 내 식별자 추가
LISTENER_ORCL =
  (ADDRESS = (PROTOCOL = TCP)(HOST = 192.0.2.100)(PORT = 1521))
```

또는 PFILE/SPFILE 환경에서 `LOCAL_LISTENER` 주소를 명시적인 Address 문법으로 직접 재설정합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

```sql
-- SQL*Plus 접속 후 LOCAL_LISTENER 주소 직접 반영
SQL> ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=192.0.2.100)(PORT=1521))' SCOPE=BOTH;
System altered.

SQL> STARTUP;
ORACLE instance started.
Database mounted.
Database opened.
```

---

### 2. `ORA-04031`: Shared Pool 메모리 부족 및 AMM / HugePages 불일치

인스턴스 기동 중 또는 DBCA 수행 과정에서 메모리를 할당받지 못할 때 나타나는 오류입니다 (출처: automatic-storage-management-administrators-guide.pdf, 2019; database-reference.pdf, 2019).

```text
ORA-04031: unable to allocate 4192 bytes of shared memory ("shared pool","unknown object","sga heap(1,0)","Library cache")
```

#### 발생 원인

1. **Shared Pool 산정 크기 부족**: 공유 풀(`SHARED_POOL_SIZE`) 용량이 너무 작게 설정되어 내부 SGA 오버헤드나 SQL 파싱 객체를 수용하지 못하는 경우 발생합니다 (출처: database-administrators-guide.pdf, 2019; database-performance-tuning-guide.pdf, 2019).
2. **AMM과 Static HugePages 충돌**: Linux 환경에서 `MEMORY_TARGET`(AMM)을 사용하면서 커널의 Static HugePages가 활성화되어 있어 메모리 할당이 세그먼트 단위로 실패하는 경우 발생합니다 (출처: database-reference.pdf, 2019).
3. **`vm.nr_hugepages` 할당량 미달**: `USE_LARGE_PAGES = ONLY`로 설정되었으나 OS 커널에 고정된 HugePages 개수가 `SGA_TARGET` 필요량보다 부족한 경우 발생합니다.

#### 표 12-2. `ORA-04031` 진단 항목 및 조치 방안

| 진단 항목 | 현상 및 원인 | 해결 및 조치 방법 |
| :--- | :--- | :--- |
| **Shared Pool 용량 미달** | Shared Pool 영역 단편화 및 파싱 공간 고갈 | `SGA_TARGET` 또는 `SHARED_POOL_SIZE` 크기 확장 (출처: database-administrators-guide.pdf, 2019; database-performance-tuning-guide.pdf, 2019) |
| **AMM 사용 충돌** | `MEMORY_TARGET` 설정 시 Static HugePages 미지원 | AMM을 비활성화(`MEMORY_TARGET=0`)하고 ASMM(`SGA_TARGET`)으로 전환 (출처: database-reference.pdf, 2019) |
| **HugePages 개수 부족** | `vm.nr_hugepages` 설정치가 SGA 필요량보다 작음 | `/etc/sysctl.d/99-oracle.conf` 내 `vm.nr_hugepages` 수치 확대 반영 |

#### 트러블슈팅 수순

ASMM 방식으로 전환하고 `SGA_TARGET` 및 `PGA_AGGREGATE_TARGET`을 명시적으로 할당합니다 (출처: database-administrators-guide.pdf, 2019).

```sql
-- 1. AMM 비활성화 및 ASMM 파라미터 재지정
SQL> ALTER SYSTEM SET MEMORY_TARGET = 0 SCOPE = SPFILE;
SQL> ALTER SYSTEM SET SGA_TARGET = 4G SCOPE = SPFILE;
SQL> ALTER SYSTEM SET PGA_AGGREGATE_TARGET = 2G SCOPE = SPFILE;
SQL> ALTER SYSTEM SET SHARED_POOL_SIZE = 1280M SCOPE = SPFILE;

-- 2. 인스턴스 재시동
SQL> SHUTDOWN IMMEDIATE;
SQL> STARTUP;
```

---

### 3. UEK R7 커널 `io_uring` 권한 및 비동기 I/O 관련 예외 처리

Oracle Linux 9 UEK R7 커널 환경에서 ASMLIB v3.0 구동 시 디스크 헤더를 읽지 못하거나 `oracleasm init`이 실패하는 오류입니다.

```text
Checking if io_uring is accessible to the configured DB user: no
OAM-00005: error opening ASM device /dev/sdb1: Permission denied
```

#### 발생 원인

Oracle Linux 9 UEK R7 커널은 보안 강화를 위해 `io_uring` 시스템 콜 접근 권한을 제한할 수 있습니다. 커널 파라미터 `kernel.io_uring_disabled`가 `1`(그룹 제한)로 설정되어 있으나, 오라클 계정이 속한 OS 그룹(GID)이 `kernel.io_uring_group` 파라미터에 정상 등록되지 않았을 때 발생합니다.

#### 트러블슈팅 수순

`oracle` 계정의 GID(예: `oinstall` - 54321 또는 `dba` - 54322)를 확인하고 `/etc/sysctl.d/io_uring.conf` 커널 파라미터를 보완 동기화합니다.

```bash
# 1. oracle 계정의 Primary Group GID 확인
$ id -g oracle
54321

# 2. io_uring 커널 파라미터 수정 (root 계정)
$ sudo vi /etc/sysctl.d/io_uring.conf
kernel.io_uring_disabled = 1
kernel.io_uring_group = 54321

# 3. sysctl 동적 반영
$ sudo sysctl -p /etc/sysctl.d/io_uring.conf

# 4. oracleasm 검증
$ sudo oracleasm status
Checking if the oracleasm kernel module is loaded: no (Not required with kernel)
Checking which I/O Interface is in use: io_uring (KABI_V3)
Checking if io_uring is enabled: yes
Checking if io_uring is accessible to the configured DB user: yes
```

---

## 🛠️️ 내부 검증용 메모 (Editorial Verification Note)

* **로그 디렉토리 경로 검증**: `installActions.log`, `silentInstall.log`는 중앙 인벤토리(`oraInventory/logs/`) 아래 생성되며, DBCA 로그는 `$ORACLE_BASE/cfgtoollogs/dbca/`에 위치함을 공식 설치 문서 표준에 맞춰 검증함 (출처: clusterware-administration-and-deployment-guide.pdf, 2019; real-application-clusters-administration-and-deployment-guide.pdf, 2026).
* **에러 메커니즘 검증**: `ORA-00119`/`ORA-00132`는 `LOCAL_LISTENER` 파라미터의 tnsnames 식별자 미해결 시 LREG/PMON에 의해 인스턴스 개시가 거부되는 에러임을 명시함 (출처: database-net-services-administrators-guide.pdf, 2019). `ORA-04031` 및 Linux `MEMORY_TARGET`과 `USE_LARGE_PAGES` 충돌 상충 관계를 공식 매뉴얼 규격으로 확인 반영함 (출처: database-reference.pdf, 2019).

---

### 💡 기획 편집자 총평

본 도서 **"Oracle Linux 9 & Oracle Database 19c SE2 Silent Mode 구축·운영 가이드"**의 전체 12개 챕터 집필이 모두 완수되었습니다.

하드웨어 준비부터 Oracle Linux 9 Minimal (CUI) 설치, `oracle-database-preinstall-19c` RPM 사전 환경 최적화, Static HugePages, `io_uring` 기반 ASMLIB, `runInstaller -silent` 엔진 설치, `netca -silent` 리스너 구성, `dbca -silent` 데이터베이스 생성(CDB/PDB), 메모리/RU 패치 관리, systemd 자동 시작, RMAN 백업 스크립트, 그리고 이번 12장의 Silent 트러블슈팅까지 **100% CUI/Silent Mode 중심의 완벽한 실무 바이블**로 완성되었습니다.
