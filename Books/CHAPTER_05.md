# CHAPTER 05. Response File 작성 및 `runInstaller -silent` 엔진 설치

Oracle Database 19c부터는 오라클 셋업 소프트웨어의 배포 및 설치 방식이 **이미지 기반 설치(Image-based Installation)** 메커니즘으로 새로이 전환되었습니다. 과거 버전과 달리 압축 파일 형태의 오라클 홈 이미지를 대상 디렉토리에 직접 해제한 후 해당 위치에서 설치 프로그램을 즉시 구동합니다.

본 장에서는 GUI 화면을 사용할 수 없는 Headless(Non-GUI) CUI 환경에서 응답 파일(Response File)을 활용하여 오라클 데이터베이스 19c SE2 엔진을 비대화형(Silent Mode)으로 설치하는 전체 과정을 다룹니다.

---

## 5.1 Oracle 19c 소프트웨어 스테이징 및 압축 해제

### 이미지 기반 설치(Image-based Installation) 메커니즘

Oracle 19c 엔진 바이너리 배포판(`LINUX.X64_193000_db_home.zip`)은 오라클 홈 이미지 자체를 포함하고 있습니다. 따라서 기존처럼 임시 디렉토리에 압축을 풀고 `runInstaller`를 호출하는 방식이 아니라, 사전 정의된 `$ORACLE_HOME` 경로로 이동한 뒤 그 자리에서 직접 압축을 해제해야 합니다.

```
[ 전통적인 12c 이하 설치 방식 ]
임시 스테이징 디렉토리 (/tmp/db) ───> runInstaller 실행 ───> target $ORACLE_HOME 으로 파일 복사

[ 19c 이미지 기반 설치 방식 ]
target $ORACLE_HOME 디렉토리 생성 ───> $ORACLE_HOME 내에서 zip 직접 해제 ───> ./runInstaller -silent 실행
```

---

### `$ORACLE_HOME` 디렉토리 이동 및 압축 해제 절차

`oracle` 계정으로 로그인한 후 디렉토리 구조를 확인하고 오라클 홈 이미지 파일의 압축을 해제합니다.

```bash
# 1. oracle 계정 전환 및 환경 변수 확인
$ su - oracle
$ echo $ORACLE_HOME
/u01/app/oracle/product/19.0.0/dbhome_1

# 2. ORACLE_HOME 디렉토리 이동 및 압축 해제 (unzip -q)
$ cd $ORACLE_HOME
$ unzip -q /software/stage/LINUX.X64_193000_db_home.zip
```

---

### `oracle` 사용자 환경 변수 (`.bash_profile`) 설정

오라클 엔진 및 유틸리티 명령어를 정상 구동하기 위해 `oracle` 계정의 쉘 환경 변수를 설정합니다.

```bash
# ~/.bash_profile 설정
$ vi ~/.bash_profile

# Oracle Environment Variables
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.0.0/dbhome_1
export ORACLE_SID=orcl
export PATH=$ORACLE_HOME/bin:$PATH:$HOME/.local/bin:$HOME/bin
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib

# 반영 및 검증
$ source ~/.bash_profile
```

---

## 5.2 `db_install.rsp` 응답 파일 핵심 매개변수 정밀 해설

### Silent Mode 응답 파일(Response File)의 구조

GUI 설치 프로그램(OUI)이 수집하는 모든 선택 항목과 매개변수를 텍스트 형태의 키-값(Key-Value) 쌍으로 정의한 파일이 **응답 파일(Response File)**입니다. `$ORACLE_HOME/install/response/db_install.rsp` 템플릿 파일을 복사하여 환경에 맞게 수정합니다.

#### 표 5-1. `db_install.rsp` 핵심 설정 매개변수 명세

| 매개변수 항목 | 설정값 예시 | 기능 및 설정 목적 |
| :--- | :--- | :--- |
| **`oracle.install.option`** | `INSTALL_DB_SWONLY` | 오라클 데이터베이스 소프트웨어 엔진만 설치 지정 |
| **`UNIX_GROUP_NAME`** | `oinstall` | 오라클 인벤토리 관리 권한을 소유한 OS 중앙 그룹 |
| **`INVENTORY_LOCATION`** | `/u01/app/oraInventory` | 오라클 제품 설치 이력을 기록하는 중앙 인벤토리 경로 |
| **`ORACLE_HOME`** | `/u01/app/oracle/product/19.0.0/dbhome_1` | 오라클 소프트웨어가 설치되는 절대 경로 |
| **`ORACLE_BASE`** | `/u01/app/oracle` | 오라클 최상위 베이스 디렉토리 경로 |
| **`oracle.install.db.InstallEdition`** | `SE2` | 설치할 오라클 에디션 지정 (SE2 / EE) |
| **`OSDBA_GROUP`** | `dba` | 데이터베이스 SYSDBA 관리자 권한을 가질 OS 그룹 |
| **`OSOPER_GROUP`** | `oper` | 데이터베이스 SYSOPER 운영자 권한을 가질 OS 그룹 |
| **`OSBACKUPDBA_GROUP`** | `backupdba` | RMAN 백업/복구 관리 전용 SYSBACKUP 권한 그룹 |
| **`OSDGDBA_GROUP`** | `dgdba` | Data Guard 복제 관리 전용 SYSDG 권한 그룹 |
| **`OSKMDBA_GROUP`** | `kmdba` | 암호화 키 관리 전용 SYSKM 권한 그룹 |
| **`OSRACDBA_GROUP`** | `racdba` | RAC 클러스터 인스턴스 전용 SYSRAC 권한 그룹 |

---

### `db_install.rsp` 작성 예시

실무에 즉시 적용 가능한 응답 파일 구성은 다음과 같습니다.

```ini
# /u01/app/oracle/stage/db_install.rsp
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=/u01/app/oraInventory
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
ORACLE_BASE=/u01/app/oracle
oracle.install.db.InstallEdition=SE2
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=backupdba
oracle.install.db.OSDGDBA_GROUP=dgdba
oracle.install.db.OSKMDBA_GROUP=kmdba
oracle.install.db.OSRACDBA_GROUP=racdba
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
```

---

## 5.3 CLI 기반 소프트웨어 설치 실행 (`./runInstaller -silent`)

### `./runInstaller -silent` 커맨드라인 구문

작성된 응답 파일을 참조하여 백그라운드 비대화형 모드로 오라클 엔진 설치를 시작합니다.

```bash
# runInstaller -silent 설치 실행
$ cd $ORACLE_HOME
$ ./runInstaller -silent -nowait \
    -responseFile /u01/app/oracle/stage/db_install.rsp \
    -ignorePrereqFailure
```

> **💡 [Technical Note] `-nowait` 및 `-ignorePrereqFailure` 옵션**
>
> * **`-nowait`**: 설치 시작 즉시 제어권을 터미널 프롬프트로 반환합니다.
> * **`-ignorePrereqFailure`**: 경미한 OS 사전 검증 경고 항목을 무시하고 Silent 설치를 끝까지 완수합니다.

---

### 실시간 설치 로그 트래킹 및 검증

Silent 설치가 구동되면 인벤토리 로그 디렉토리에 설치 상태가 기록됩니다. 터미널에서 `tail -f` 명령어로 진행 상황을 모니터링합니다.

```bash
# 실시간 설치 로그 확인
$ tail -f /u01/app/oraInventory/logs/installActions*.log
```

설치가 정상 완료되면 로그 하단에 다음과 같은 성공 메시지가 출력됩니다.

```text
Successfully Setup Software.
The installation of Oracle Database Software was successful.
Please check '/u01/app/oraInventory/logs/silentInstall2026-09-30_03-00-00AM.log' for more details.
```

---

## 5.4 Root 스크립트 실행 및 자동화 설정

### `orainstRoot.sh` 및 `root.sh` 스크립트의 역할

오라클 소프트웨어 엔진 설치가 끝나면, OS 시스템 루트 권한이 필요한 후속 작업을 처리하기 위해 두 개의 Root 스크립트를 실행해야 합니다.

1. **`orainstRoot.sh`**: 중앙 인벤토리 포인터 파일인 `/etc/oraInst.loc`을 생성하고, 오라클 설치 계정과 인벤토리 그룹(`oinstall`) 권한을 동기화합니다.
2. **`root.sh`**: 오라클 홈 디렉토리 내 바이너리(`$ORACLE_HOME/bin`)들의 OS 소유권을 `root` 및 실행 권한으로 변경하고, `/usr/local/bin`에 주요 실행 파일링크를 등록합니다.

```bash
# 1. root 계정으로 전환하여 orainstRoot.sh 실행
# sudo /u01/app/oraInventory/orainstRoot.sh
Changing permissions of /u01/app/oraInventory.
Adding read,write permissions for group.
Removing read,write,execute permissions for world.

Changing groupname of /u01/app/oraInventory to oinstall.
The execution of the script is complete.

# 2. root.sh 스크립트 실행
# sudo /u01/app/oracle/product/19.0.0/dbhome_1/root.sh
Check /u01/app/oracle/product/19.0.0/dbhome_1/install/root_dbserver_2026-09-30.log for output of it
Finished product-specific root actions.
```

---

### 19c 신규 기능: Root 스크립트 자동 실행 구성

Oracle Database 19c부터는 설치 시점에 `root` 계정 암호나 `sudo` 권한 정보를 응답 파일에 포함시켜 Root 스크립트를 수동 실행 없이 자동으로 처리할 수 있는 옵션이 제공됩니다.

```ini
# db_install.rsp 응답 파일 내 root 스크립트 자동 실행 옵션 추가 예시
oracle.install.db.rootconfig.executeRootScript=true
oracle.install.db.rootconfig.configMethod=SUDO
oracle.install.db.rootconfig.sudoPath=/usr/bin/sudo
```

---

### 💬 기획 편집자 노트 (Next Step)

Chapter 5에서는 오라클 19c 엔진의 이미지 기반 직접 압축 해제, `db_install.rsp` 응답 파일 작성, `./runInstaller -silent` 비대화형 설치 실행, 그리고 `root.sh` 스크립트 검증까지 완벽하게 작성하였습니다.

이어지는 **CHAPTER 06**에서는 `netca -silent` 명령을 통한 네트워크 리스너 자동 구성 및 `listener.ora`, `tnsnames.ora`, `sqlnet.ora` 파일 제어를 다룰 예정입니다. CHAPTER 06 본문 집필을 계속 진행할까요?
