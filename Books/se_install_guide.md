**피드백해 주신 방향을 적극 반영하여, GUI를 100% 배제하고 전 과정을 'CUI / CLI / Silent Mode' 기반의 자동화·전문가 가이드로 전면 재설계했습니다.**

엔터프라이즈 데이터센터나 클라우드(OCI, AWS, Azure) 환경에서는 보안 정책과 리소스 효율성으로 인해 GUI 패키지(X11 / Desktop Environment)를 설치하지 않는 **Headless Linux Server**가 표준입니다.

GUI 단계를 완전히 배제하고 **응답 파일(Response File)과 Command-Line Interface(CLI)**로만 끝까지 완수하는 구성은 독자층(현업 DBA 및 Infrastructure Engineer)에게 **"실무 현장에서 바로 사용할 수 있는 진짜 자동화 구축 가이드"**라는 강렬한 차별성을 제공합니다.

---

# 📖 개정된 도서 출판 기획서 (Publication Proposal - Silent Mode Focus)

### 1. 도서명(안)

* **메인 타이틀**: **Oracle Linux 9 & Oracle Database 19c SE2 Silent Mode 구축·운영 가이드**
* **서브 타이틀**: *GUI 없이 CLI로 끝내는 하드웨어 사이징, OS 최적화, Response File 스크립팅 및 DBCA 자동화 바이블*

### 2. 핵심 차별화 포인트 (USP: Unique Selling Point)

1. **100% Non-GUI (Headless) 실무 환경 전제**: OS Minimal 설치부터 `runInstaller -silent`, `netca -silent`, `dbca -silent`까지 모든 프로세스를 터미널 명령어와 스크립트로 완성합니다.
2. **Response File 완벽 해설 및 템플릿 제공**: 실무에 바로 적용 가능한 `db_install.rsp`, `netca.rsp`, DBCA CLI 원라이너(One-liner) 및 옵션 파라미터를 완전하게 수록합니다.
3. **재현 가능한 스크립트 중심**: 단순 가이드북을 넘어 독자가 자신의 인프라 환경에 맞춰 변수만 수정해 바로 실행할 수 있는 Shell Script와 systemd 자동화 스크립트를 제공합니다.

---

# 📑 전면 개정된 상세 목차 (Detailed Table of Contents)

## **PART 1. 인프라 기획 및 하드웨어 준비 (Hardware & System Planning)**

### **CHAPTER 01. Oracle Database 19c SE2 & Oracle Linux 9 UEK 7 아키텍처**

* **1.1 Oracle 19c SE2(Standard Edition 2) 핵심 제약과 구축 전략**
  * SE2의 CPU 소켓 제한(최대 2소켓) 및 19c SE2에서의 RAC 지원 중단 체계
  * Standard Edition High Availability(SEHA)를 통한 CUI 환경 고가용성 구성 개요
* **1.2 Oracle Linux 9 UEK Release 7 커널 특징**
  * `io_uring` I/O 서브시스템 구조와 커널 비동기 I/O(AIO) 메커니즘 분석
* **1.3 Headless (Non-GUI) 구축 환경의 이점**
  * X11 패키지 배제로 인한 보안 취약점 감소, 메모리 다이어트 및 자동화 배포 이점

### **CHAPTER 02. 하드웨어 사이징 및 리소스 설계**

* **2.1 CPU 및 메모리 요구사항 수치화**
  * SGA/PGA 메모리 할당 기준 및 물리 메모리(RAM) 수치에 따른 계산 모형
* **2.2 Swap 공간 산정 스펙 및 수식 정밀 가이드**
  * RAM 용량 구간별 정확한 Swap 할당 공식 (RAM 1~2GB: 1.5배 / 2~16GB: 1:1 매핑 / 16GB 초과: 16GB 고정)
* **2.3 스토리지 레이아웃 및 파일시스템 설계**
  * Datafile, Redo Log, Fast Recovery Area(FRA), Temp 공간의 물리적 디스크 분리 설계
  * LVM 스토리지 구성 및 XFS/ext4 Mount Option 최적화 (`noatime`, `nodiratime`)

---

## **PART 2. Oracle Linux 9 Minimal OS 구축 및 CUI 사전 최적화**

### **CHAPTER 03. Oracle Linux 9 Minimal (CUI) 설치 및 기본 설정**

* **3.1 Server (Minimal Install) OS 설치 및 콘솔 설정**
  * GUI 패키지 없이 CUI 모드로 OS를 설치하는 핵심 패키지 그룹 선택
* **3.2 CLI 기반 네트워크 바인딩 및 호스트 검증**
  * `nmcli` 유틸리티를 활용한 고정 IP 설정 및 `/etc/hosts` 네트워크 이름 풀이 검증
* **3.3 스토리지 파티셔닝 및 CLI 파일시스템 생성**
  * `fdisk` / `parted` / `pvcreate` / `vgcreate` / `lvcreate` 명령어를 이용한 스토리지 볼륨 구성

### **CHAPTER 04. CLI 기반 Oracle Pre-installation 및 커널 최적화**

* **4.1 Automated Pre-installation 패키지 적용**
  * `dnf install -y oracle-database-preinstall-19c` 실행 및 자동 반영 항목 검증
* **4.2 사용자, 그룹 및 디렉토리 권한 매핑**
  * `oinstall`, `dba`, `oper`, `backupdba`, `dgdba`, `kmdba` 그룹 및 `oracle` 계정 생성과 권한 설정
* **4.3 커널 파라미터 및 사용자 리소스 제한 (`limits.conf`) 정밀 설정**
  * `/etc/sysctl.conf` 파라미터 제어 (`fs.file-max`, `fs.aio-max-nr`, `kernel.shmmax`, `kernel.shmall`)
  * `/etc/security/limits.conf` 설정 (`nofile`, `nproc`, `memlock`, `stack`)
* **4.4 메모리 성능 최적화: Static HugePages & THP 비활성화**
  * Transparent HugePages(THP) 비활성화 (`grubby` 커널 매개변수 적용)
  * SGA 크기에 맞춘 `vm.nr_hugepages` 스크립트 계산 및 커널 메모리 고정
* **4.5 Storage 및 ASMLIB 구성 모범 사례 (CLI)**
  * UEK R7 환경에서 별도 모듈 드라이버 설치 없이 `io_uring` 기반으로 ASMLIB을 구성하는 CLI 단계

---

## **PART 3. 100% Silent Mode Oracle 19c SE2 구축 (CLI Automation)**

### **CHAPTER 05. Response File 작성 및 `runInstaller -silent` 엔진 설치**

* **5.1 Oracle 19c 소프트웨어 스테이징 및 압축 해제**
  * `$ORACLE_HOME` 디렉토리 사전 생성 및 `LINUX.X64_193000_db_home.zip` 직접 해제
* **5.2 `db_install.rsp` 응답 파일 핵심 매개변수 정밀 해설**
  * `oracle.install.option=INSTALL_DB_SWONLY`
  * `UNIX_GROUP_NAME=oinstall`
  * `INVENTORY_LOCATION=/u01/app/oraInventory`
  * `ORACLE_HOME` & `ORACLE_BASE`
  * `oracle.install.db.InstallEdition=SE2`
* **5.3 CLI 기반 소프트웨어 설치 실행**
  * `./runInstaller -silent -responseFile $ORACLE_HOME/install/response/db_install.rsp` 실행 및 로그 실시간 모니터링 (`tail -f`)
* **5.4 Root 스크립트 자동 실행 및 검증**
  * `orainstRoot.sh` 및 `root.sh` 스크립트 비대화형 실행 수순

### **CHAPTER 06. `netca -silent`를 활용한 리스너 및 네트워크 구성**

* **6.1 Response File을 이용한 Silent 리스너 생성**
  * `netca -silent -responsefile $ORACLE_HOME/inventory/response/netca.rsp` 명령어 구성
* **6.2 커맨드라인 기반 `listener.ora` & `sqlnet.ora` 자동 생성 및 튜닝**
  * 1521 포트 TCP/IP 바인딩 및 LSNRCTL 유틸리티 제어 (`lsnrctl start`, `lsnrctl status`)
* **6.3 `tnsnames.ora` CLI 구성 및 서비스 로컬 파라미터 작성**

### **CHAPTER 07. `dbca -silent` 명령어를 통한 데이터베이스 생성**

* **7.1 DBCA Silent Mode 커맨드라인 구문 구조 분석**
  * `dbca -silent -createDatabase` 주요 CLI 파라미터 완전 해설
* **7.2 단일 인스턴스 Single Database (Non-CDB) 생성 스크립트**
  * `-gdbName`, `-sid`, `-templateName General_Purpose.dbc`, `-characterSet AL32UTF8`, `-memoryMgmtType AUTO_SGA` 실행 예제
* **7.3 Multitenant CDB & PDB 자동 생성 스크립트**
  * `-createAsContainerDatabase true -numberOfPDBs 1 -pdbName pdb1 -pdbAdminPassword <PWD>` 옵션을 이용한 19c CDB/PDB 한 번에 구축하기
* **7.4 OMF(Oracle Managed Files) 및 FRA(Fast Recovery Area) 스토리지 자동 구성**
  * `-useOMF true`, `-recoveryAreaDestination`, `-recoveryAreaSize` 파라미터 연동

---

## **PART 4. CUI 환경에서의 메모리/커널 튜닝 및 OPatch 패치 관리**

### **CHAPTER 08. Oracle Linux 9 환경에서의 19c 메모리 최적화**

* **8.1 메모리 관리 방식 선택: AMM vs ASMM (Linux 제약)**
  * Physical Memory 4GB 초과 시 AMM(`MEMORY_TARGET`) 사용 불가 및 ASMM(`SGA_TARGET` + `PGA_AGGREGATE_TARGET`) 커맨드라인 전환
* **8.2 HugePages 고정 설정 (`USE_LARGE_PAGES=ONLY`)**
  * `ALTER SYSTEM SET USE_LARGE_PAGES=ONLY SCOPE=SPFILE;` 명령을 통한 SGA 대형 페이지 강제 매핑
* **8.3 `/dev/shm` 마운트 크기 산정 및 커널 튜닝**

### **CHAPTER 09. OPatch & Release Update(RU) CLI 패치 관리**

* **9.1 OPatch 유틸리티 최신화 (`opatch version`)**
  * `opatch` 최신 패키지 교체 및 CLI 상태 검증
* **9.2 Silent Mode 기반 Release Update (RU) / MRP 패치 적용**
  * `opatch apply -silent` 명령어를 이용한 19c RU 및 Monthly Recommended Patch(MRP) 적용 절차
* **9.3 Post-Patch Database Upgrade: `datapatch` 스크립트 실행**
  * `$ORACLE_HOME/OPatch/datapatch -verbose` 스크립트를 통한 데이터 카탈로그 패치 반영 및 검증

---

## **PART 5. 운영 자동화, 백업 스크립팅 및 트러블슈팅**

### **CHAPTER 10. Linux systemd 서비스 등록 및 자동 시작 구성**

* **10.1 `/etc/oratab` 파일 제어 (`Y` 플래그 설정)**
* **10.2 systemd 서비스 유닛 스크립트 (`oracle.service`) 작성**
  * OS 재부팅 시 Listener 및 DB Instance 자동 시작/종료 등록 (`systemctl enable oracle`)
* **10.3 CVU(Cluster Verification Utility) CLI 검증**
  * `runcluvfy.sh comp sys -n localhost -verbose`를 통한 OS/DB 종합 환경 검증

### **CHAPTER 11. CLI 기반 RMAN 백업 스크립트 및 운영**

* **11.1 ARCHIVELOG 모드 커맨드라인 전환**
  * `SQL> ALTER DATABASE ARCHIVELOG;` 및 `LOG_ARCHIVE_DEST_1` 설정
* **11.2 Shell & RMAN 자동 백업 스크립트 작성**
  * Crontab 연동을 위한 RMAN 백업 스크립트 (Full Backup, Incremental Backup, Archivelog Pruning)

### **CHAPTER 12. Silent Mode 설치 트러블슈팅 및 로그 분석**

* **12.1 Silent Mode 설치 중 발생 로그 수집 및 분석 위치**
  * `$ORACLE_BASE/oraInventory/logs/` 및 `$ORACLE_BASE/cfgtoollogs/dbca/` 분석 법
* **12.2 Prerequisite Check Silent Bypass 옵션 활용**
  * `-ignorePrereqFailure` 파라미터 남용 시 위험성과 올바른 조치법
* **12.3 주요 CUI 설치 에러 대응**
  * `ORA-00119`, `ORA-00132` (Listener 커맨드라인 바인딩 오류)
  * `ORA-04031` (Shared Pool 부족) 및 `vm.nr_hugepages` 설정 불일치 분석
  * UEK 7 커널 `io_uring` 권한 및 비동기 I/O 관련 예외 처리

---

# 💡 실무 가이드 작성을 위한 핵심 코드 예시 (기획안 수록용)

책의 완성도를 극대화하기 위해 본문에 수록될 핵심 명령어 패턴과 응답 파일 예시를 일부 정리했습니다.

### 1. `runInstaller -silent` 소프트웨어 전용 설치 명령어

```bash
$ cd $ORACLE_HOME
$ ./runInstaller -silent \
    -noReset \
    -responseFile $ORACLE_HOME/install/response/db_install.rsp \
    oracle.install.option=INSTALL_DB_SWONLY \
    UNIX_GROUP_NAME=oinstall \
    INVENTORY_LOCATION=/u01/app/oraInventory \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
    ORACLE_BASE=/u01/app/oracle \
    oracle.install.db.InstallEdition=SE2 \
    oracle.install.db.OSDBA_GROUP=dba \
    oracle.install.db.OSOPER_GROUP=oper \
    oracle.install.db.OSBACKUPDBA_GROUP=backupdba \
    oracle.install.db.OSDGDBA_GROUP=dgdba \
    oracle.install.db.OSKMDBA_GROUP=kmdba \
    oracle.install.db.OSRACDBA_GROUP=dba
```

### 2. `dbca -silent` Single-Instance (Non-CDB / CDB) 생성 원라이너

```bash
$ dbca -silent -createDatabase \
    -gdbName orcl \
    -sid orcl \
    -templateName General_Purpose.dbc \
    -createAsContainerDatabase false \
    -sysPassword "Oracle_1234#!" \
    -systemPassword "Oracle_1234#!" \
    -emConfiguration NONE \
    -datafileDestination /u01/app/oracle/oradata \
    -storageType FS \
    -characterSet AL32UTF8 \
    -nationalCharacterSet AL16UTF16 \
    -memoryMgmtType AUTO_SGA \
    -sgaTargetInMB 4096 \
    -pgaAggregateTargetInMB 2096 \
    -redoLogFileSize 200
```

---

### 🚀 집필 가이드 및 편집자 제언

1. **실행 결과 출력 화면(Terminal Output)의 명확성**: 독자가 커맨드를 입력한 후 터미널에 출력되는 정상 반응(예: `100% complete`, `Look at the log file...` 등)을 상자(Box) 형태로 명확히 보여주어, 자신의 진행 상황과 대조할 수 있게 구성합니다.
2. **복사-붙여넣기 가능한 GitHub / 자료실 코드 제공**: Response File 템플릿과 Shell 스크립트는 출판사 홈페이지 및 GitHub 리포지토리를 통해 제공하여 독자들의 오타로 인한 실패를 최소화합니다.

이와 같은 100% Silent Mode 중심의 목차와 기획으로 진행하신다면, 엔지니어들에게 현장에서 매우 유용한 기술서가 될 것입니다. 추가적인 수정 사항이 있으시다면 언제든 편하게 말씀해 주세요!
