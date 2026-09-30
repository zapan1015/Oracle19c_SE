<!-- 
[조판 및 폰트 지정 규격 (Typography Specification)]
- 책 본문 (Body Text): Noto Sans KR
- 장/절 제목 (Headings): Noto Sans KR Bold
- 표 (Table): Noto Sans KR
- 캡션 (Caption): Noto Sans KR
- 영문 기술 용어 (Technical Terms): Noto Sans KR
- 코드 및 SQL 블록 (Code & SQL Blocks): DejaVu Sans Mono
-->

# CHAPTER 05. Response File 작성 및 `runInstaller -silent` 엔진 설치

Oracle Database 18c 및 19c부터는 오라클 데이터베이스 소프트웨어의 배포 및 설치 방식이 기존의 스테이징 복사 방식에서 **이미지 기반 설치(Image-Based Installation)** 메커니즘으로 전면 개편되었습니다[1]. 과거 버전(12c R2 이하)처럼 별도의 임시 디렉터리에 설치 미디어를 압축 해제한 뒤 설치 마법사가 대상 경로로 파일을 복사하는 대신, 관리자가 사전에 생성한 `$ORACLE_HOME` 디렉터리에 골드 이미지(Gold Image) 압축 파일을 직접 해제하고 그 위치에서 `./runInstaller`를 실행하여 엔진을 등록 및 링크(Relink)합니다[1].

이 장에서는 그래픽 화면을 사용할 수 없는 Headless(CUI) 환경에서 `oracle` 사용자 환경 변수를 구성하고, 응답 파일(`db_install.rsp`) 작성과 Release Update(RU) 동시 패치 옵션(`-applyRU`)을 결합하여 Oracle Database 19c SE2 엔진을 비대화형(Silent Mode)으로 안전하게 설치하는 전 과정을 다룹니다.

---

## 5.1 Oracle 19c 환경 변수 구성 및 골드 이미지 압축 해제

### 5.1.1 이미지 기반 설치(Image-Based Installation) 아키텍처

Oracle Database 19c 기본 설치 미디어(`LINUX.X64_193000_db_home.zip`)는 완성된 오라클 홈 디렉터리 구조 자체를 압축한 이미지입니다[1]. 따라서 임시 폴더(`/tmp` 등)에 압축을 해제하면 안 되며, 반드시 최종 설치 경로인 **`$ORACLE_HOME` 디렉터리 내부로 이동하여 직접 압축을 해제**해야 합니다[1].

```mermaid
flowchart TB
    subgraph Legacy["전통적인 설치 방식 (Oracle 12c R2 이하)"]
        direction LR
        L1["임시 스테이징 경로(/tmp/database)에<br/>설치 미디어 압축 해제"] --> L2["/tmp/database/runInstaller 실행"] --> L3["OUI가 대상 $ORACLE_HOME으로<br/>바이너리 복사 및 링크 수행"]
    end

    subgraph Modern["이미지 기반 설치 방식 (Oracle Database 19c)"]
        direction LR
        M1["대상 $ORACLE_HOME 디렉터리 생성<br/>및 환경 변수 설정"] --> M2["$ORACLE_HOME 내부에서<br/>골드 이미지(.zip) 직접 압축 해제"] --> M3["$ORACLE_HOME/runInstaller 실행<br/>(-silent -applyRU 인플레이스 구성)"]
    end
```
*그림 5-1. 기존 스테이징 복사 방식과 Oracle Database 19c 이미지 기반 설치 방식 비교*

---

### 5.1.2 `oracle` 사용자 환경 변수(`~/.bash_profile`) 설정

오라클 엔진 바이너리를 압축 해제하고 설치 도구를 실행하기에 앞서, `oracle` 계정의 셸 프로파일(`~/.bash_profile`)에 OFA 표준 경로와 문자셋(`NLS_LANG`) 환경 변수를 먼저 선언하고 적용합니다[1].

```bash
# 1. oracle 계정으로 전환 후 ~/.bash_profile 편집
$ su - oracle
$ cat << 'EOF' >> ~/.bash_profile

# Oracle Database 19c Environment Variables
export TMP=/tmp
export TMPDIR=$TMP
export ORACLE_HOSTNAME=dbserver.example.com
export ORACLE_UNQNAME=ORCL
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.0.0/dbhome_1
export ORA_INVENTORY=/u01/app/oraInventory
export ORACLE_SID=ORCL
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export PATH=/usr/sbin:/usr/local/bin:$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
EOF

# 2. 환경 변수 즉시 반영 및 설정값 검증
$ source ~/.bash_profile
$ echo $ORACLE_HOME
/u01/app/oracle/product/19.0.0/dbhome_1
```

---

### 5.1.3 `$ORACLE_HOME` 골드 이미지 압축 해제 및 OPatch 최신화

환경 변수 설정이 완료되면 `$ORACLE_HOME` 디렉터리로 이동하여 `LINUX.X64_193000_db_home.zip` 파일을 압축 해제합니다[1]. 이어서 Oracle Linux 9 환경의 필수 요구사항인 Release Update(RU 19.19 이상) 동시 패치(`-applyRU`)를 수행하기 위해, 기본 내장된 구버전 `OPatch`를 최신 버전(Patch `6880880`)으로 교체하고 RU 패치 본체를 스테이징 디렉터리(`/u01/stage`)에 압축 해제합니다[1, 2].

```bash
# 1. 스테이징 디렉터리 생성 (설치 미디어 및 패치 보관용)
$ mkdir -p /u01/stage

# 2. $ORACLE_HOME 디렉터리로 이동하여 19c 골드 이미지 직접 압축 해제
$ cd $ORACLE_HOME
$ unzip -q /u01/stage/LINUX.X64_193000_db_home.zip

# 3. 기본 OPatch 백업 후 최신 OPatch(p6880880) 유틸리티 교체 적용
$ mv $ORACLE_HOME/OPatch $ORACLE_HOME/OPatch.bak
$ unzip -q /u01/stage/p6880880_190000_Linux-x86-64.zip -d $ORACLE_HOME
$ $ORACLE_HOME/OPatch/opatch version
OPatch Version: 12.2.0.1.42
OPatch succeeded.

# 4. 스테이징 경로에 최신 Release Update(RU 19.19 이상) 패치 압축 해제
$ cd /u01/stage
$ unzip -q /u01/stage/p35042068_190000_Linux-x86-64.zip
```

> ⚠️ **주의(Caution)**: **골드 이미지 압축 해제 시 실행 계정(`oracle`) 및 디렉터리 주의**
> `LINUX.X64_193000_db_home.zip` 파일은 반드시 `root`가 아닌 **`oracle` 계정**으로 압축을 해제해야 파일 소유권(`oracle:oinstall`)과 심볼릭 링크가 정상 유지됩니다[1]. 또한 `$ORACLE_HOME` 디렉터리의 상위 경로 권한이 잘못되었거나 빈 공간이 부족하면(최소 12 GB 이상의 여유 공간 필요) 압축 해제 및 RU 패치 병합 과정에서 오류가 발생하므로 사전에 `df -h $ORACLE_HOME`으로 여유 용량을 확인해야 합니다[1].

---

## 5.2 `db_install.rsp` 응답 파일 핵심 매개변수 정밀 해설

### 5.2.1 Silent Mode 응답 파일(Response File)의 구조

대화형 GUI 설치 마법사(OUI)에서 사용자가 입력하는 설치 옵션과 그룹 매핑 정보를 텍스트 형태의 키-값(`Key=Value`) 쌍으로 정의한 파일이 **응답 파일(Response File)**입니다[1]. 골드 이미지 압축 해제가 완료되면 `$ORACLE_HOME/install/response/db_install.rsp` 경로에 표준 응답 파일 템플릿이 생성되며, 이를 복사하여 서버 환경에 맞게 편집합니다[1].

*표 5-1. Oracle Database 19c `db_install.rsp` 핵심 매개변수 명세*

| 매개변수 명칭 (Parameter Name) | 권장 설정값 예시 | 기능 및 설정 목적 |
| :--- | :--- | :--- |
| **`oracle.install.responseFileVersion`** | `/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0` | 응답 파일 스키마 버전 정의 (절대 수정 금지)[1] |
| **`oracle.install.option`** | `INSTALL_DB_SWONLY` | 데이터베이스 생성 없이 엔진 소프트웨어만 우선 설치 (`INSTALL_DB_AND_CONFIG`와 구분) |
| **`UNIX_GROUP_NAME`** | `oinstall` | 중앙 인벤토리(`oraInventory`)를 소유할 OS 기본 그룹명 |
| **`INVENTORY_LOCATION`** | `/u01/app/oraInventory` | 오라클 제품 설치 메타데이터를 기록하는 중앙 인벤토리 절대 경로 |
| **`ORACLE_HOME`** | `/u01/app/oracle/product/19.0.0/dbhome_1` | 골드 이미지가 압축 해제된 오라클 홈 절대 경로 |
| **`ORACLE_BASE`** | `/u01/app/oracle` | 오라클 최상위 베이스 디렉터리 경로 (ADR 진단 로그 등이 위치) |
| **`oracle.install.db.InstallEdition`** | `SE2` | 설치할 데이터베이스 에디션 지정 (`SE2`: Standard Edition 2, `EE`: Enterprise Edition) |
| **`oracle.install.db.OSDBA_GROUP`** | `dba` | `SYSDBA` 시스템 권한을 부여할 OS 그룹 |
| **`oracle.install.db.OSOPER_GROUP`** | `oper` | `SYSOPER` 운영자 시스템 권한을 부여할 OS 그룹 |
| **`oracle.install.db.OSBACKUPDBA_GROUP`** | `backupdba` | RMAN 백업·복구 전용 `SYSBACKUP` 시스템 권한 그룹 |
| **`oracle.install.db.OSDGDBA_GROUP`** | `dgdba` | Data Guard 관리 전용 `SYSDG` 시스템 권한 그룹 |
| **`oracle.install.db.OSKMDBA_GROUP`** | `kmdba` | TDE 암호화 키 관리 전용 `SYSKM` 시스템 권한 그룹 |
| **`oracle.install.db.OSRACDBA_GROUP`** | `racdba` | 클러스터 관리 전용 `SYSRAC` 시스템 권한 그룹 (필수 지정 항목) |
| **`oracle.install.db.rootconfig.executeRootScript`** | `false` (또는 `true`) | 설치 마무리 단계에서 Root 스크립트 자동 실행 여부 (`false` 시 수동 실행) |

---

### 5.2.2 실무 표준 `db_install.rsp` 작성 절차

원본 템플릿을 보존하기 위해 `/u01/stage/db_install_se2.rsp`로 복사하거나 핵심 필수 파라미터만 추출하여 응답 파일을 생성합니다[1]. (과거 11g/12c 버전에서 사용하던 `SECURITY_UPDATES_VIA_MYORACLESUPPORT` 및 `DECLINE_SECURITY_UPDATES` 파라미터는 Oracle 19c 스키마에서 완전히 제거되었으므로 기재하지 않습니다[1].)

```bash
# 1. 기본 응답 파일 템플릿 백업 복사
$ cp $ORACLE_HOME/install/response/db_install.rsp /u01/stage/db_install.rsp.orig

# 2. Oracle 19c SE2 전용 응답 파일(/u01/stage/db_install_se2.rsp) 작성 및 권한 보안 설정
$ cat << 'EOF' > /u01/stage/db_install_se2.rsp
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
oracle.install.db.rootconfig.executeRootScript=false
EOF

$ chmod 600 /u01/stage/db_install_se2.rsp
```

---

## 5.3 CLI 기반 소프트웨어 설치 실행 (`./runInstaller -silent`)

### 5.3.1 사전 요구사항 단독 검증(`-executePrereqs`) 및 `-applyRU` 결합 설치

본격적인 엔진 설치를 시작하기 전에 `-executePrereqs` 옵션으로 OS 커널 파라미터와 패키지, Swap 공간 설정이 오라클 요구 기준을 모두 충족하는지 사전 검증할 수 있습니다[1]. 이어서 `-silent`, `-waitforcompletion`, `-applyRU` 옵션을 결합하여 19c 엔진 설치와 Release Update 패치 적용을 단일 트랜잭션으로 수행합니다[1, 2].

> 💡 **노트(Note)**: **Oracle Linux 9에서 19.3 베이스 이미지 설치 시 `CV_ASSUME_DISTID` 환경 변수 설정**
> Oracle Database 19c 초기 베이스 릴리스(19.3.0.0.0)에 포함된 검증 유틸리티(CVU)는 2019년 출시 시점의 OS 목록을 기준으로 작성되어 있어, Oracle Linux 9에서 실행할 때 `[INS-13001] Oracle Database is not supported on this operating system` 경고를 출력할 수 있습니다. 설치 실행 전 셸에서 **`export CV_ASSUME_DISTID=OL8`**(또는 `OEL8`)을 선언하고 **`-applyRU`** 옵션으로 RU 19.19 이상의 패치를 함께 지정하면 OS 호환성 검증과 최신 glibc 링크 작업이 오류 없이 완벽하게 수행됩니다[1, 2].

```bash
# 1. Oracle Linux 9 배포판 호환성 인식 변수 선언
$ export CV_ASSUME_DISTID=OL8

# 2. (선택) 설치 전 OS 사전 요구사항 단독 검증 실행
$ cd $ORACLE_HOME
$ ./runInstaller -executePrereqs -silent \
  -responseFile /u01/stage/db_install_se2.rsp

# 3. Oracle 19c SE2 엔진 Silent 설치 및 Release Update(RU) 동시 적용 실행
$ ./runInstaller -silent -waitforcompletion \
  -applyRU /u01/stage/35042068 \
  -responseFile /u01/stage/db_install_se2.rsp
```

* **`-silent`**: GUI 창을 띄우지 않고 응답 파일(`-responseFile`)만을 참조하여 비대화형 모드로 설치를 진행합니다[1].
* **`-waitforcompletion`**: Linux 환경에서 백그라운드로 즉시 분리되지 않고 설치 프로세스가 완전히 종료될 때까지 포그라운드에서 대기하며, 완료 시 셸 종료 코드(Exit Code)를 반환하여 자동화 스크립트 연동을 보장합니다[1].
* **`-applyRU <패치_경로>`**: 오라클 홈 바이너리를 링크하고 인벤토리에 등록하기 전에 지정된 Release Update(RU) 패치를 선행 적용합니다[1, 2]. (추가 개별 패치가 있는 경우 `-applyOneOffs <패치1,패치2>` 옵션을 함께 사용할 수 있습니다[1].)

> ⚠️ **주의(Caution)**: **`-ignorePrereqFailure` 옵션 사용 시 주의사항**
> `./runInstaller` 실행 시 `-ignorePrereqFailure` 플래그를 무분별하게 사용하면 필수 OS 패키지 누락, 공유 메모리 부족, 디렉터리 권한 오류와 같은 치명적인 사전 검증 실패까지 모두 무시하고 설치를 강행하여 향후 DB 기동 시점이나 운영 중에 장애가 발생할 수 있습니다[1]. 따라서 모든 사전 검증 항목을 정상 통과하도록 조치하는 것이 원칙이며, 불가피하게 알려진 경미한 경고만 우회해야 할 때만 제한적으로 사용해야 합니다.

---

### 5.3.2 실시간 설치 로그 모니터링 및 완료 검증

별도의 SSH 터미널 창을 열어 인벤토리 로그 디렉터리(`/u01/app/oraInventory/logs/`)에 생성되는 `installActions*.log` 파일을 `tail -f`로 모니터링하면 파일 복사, RU 패치 적용, C 바이너리 링크(Relink) 진행 상황을 실시간으로 확인할 수 있습니다[1].

```bash
# 별도 터미널 세션에서 실시간 설치 진행 로그 추적
$ tail -f /u01/app/oraInventory/logs/installActions*.log
```

패치 병합과 엔진 설치가 정상적으로 완료되면 터미널에 Root 스크립트 실행 안내와 함께 다음과 같은 성공 메시지가 출력됩니다[1].

```text
Preparing to launch Oracle Universal Installer from /tmp/OraInstall2026-09-30_10-15-00AM.
Applying the patch /u01/stage/35042068...
Successfully applied the patch.
The installation of Oracle Database 19c was successful.
Please check '/u01/app/oraInventory/logs/silentInstall2026-09-30_10-15-00AM.log' for more details.

As a root user, execute the following script(s):
        1. /u01/app/oraInventory/orainstRoot.sh
        2. /u01/app/oracle/product/19.0.0/dbhome_1/root.sh

Successfully Setup Software.
```

---

## 5.4 Root 스크립트 실행 및 설치 검증

### 5.4.1 `orainstRoot.sh` 및 `root.sh` 스크립트의 내부 역할과 실행

오라클 소프트웨어 설치는 일반 계정인 `oracle` 권한으로 수행되므로, `/etc` 및 `/usr/local/bin` 경로에 시스템 전역 설정 파일을 생성하고 일부 핵심 실행 파일에 `root` SetUID 권한을 부여하기 위해 두 개의 셸 스크립트를 `root` 권한으로 순서대로 실행해야 합니다[1].

1. **`orainstRoot.sh`**:
   * 시스템 전역 인벤토리 위치 포인터 파일인 **`/etc/oraInst.loc`**를 생성합니다[1].
   * 중앙 인벤토리 디렉터리(`/u01/app/oraInventory`)의 그룹 소유권을 `oinstall`로 고정하고, 그룹 외 타 사용자(World)의 읽기·쓰기·실행 권한을 제거(`chmod 770`)합니다[1].
2. **`root.sh`**:
   * 데이터베이스 인스턴스 목록 관리 파일인 **`/etc/oratab`**을 생성합니다[1].
   * `/usr/local/bin` 디렉터리에 오라클 환경 설정 유틸리티 스크립트인 **`oraenv`**, **`coraenv`**, **`dbhome`**을 배치합니다(비대화형 실행 시 `-silent` 플래그가 내부 전달되거나 기본 경로가 자동 선택됩니다)[1].
   * 외부 작업 실행(`extjob`) 및 OS 인증에 필요한 `$ORACLE_HOME/bin` 하위 특수 바이너리의 소유권과 SetUID/SetGID 보안 권한을 설정합니다[1].

```bash
# 1. orainstRoot.sh 실행
$ sudo /u01/app/oraInventory/orainstRoot.sh
Changing permissions of /u01/app/oraInventory.
Adding read,write permissions for group.
Removing read,write,execute permissions for world.

Changing groupname of /u01/app/oraInventory to oinstall.
The execution of the script is complete.

# 2. root.sh 실행
$ sudo /u01/app/oracle/product/19.0.0/dbhome_1/root.sh
Check /u01/app/oracle/product/19.0.0/dbhome_1/install/root_dbserver.example.com_2026-09-30_10-30-12-123456789.log for the output of root script
```

---

### 5.4.2 응답 파일 기반 Root 스크립트 무인 자동 실행 구성

대규모 클라우드 배포나 Ansible 자동화 파이프라인에서 `orainstRoot.sh`와 `root.sh`의 수동 실행 단계까지 완전히 자동화하려면, `db_install.rsp` 응답 파일에 다음과 같이 `SUDO` 기반 자동 실행 파라미터를 지정하고 `runInstaller` 실행 시 `-promptForPassword` 또는 `NOPASSWD` sudo 권한을 연동할 수 있습니다[1].

```ini
# db_install.rsp 내 Root 스크립트 자동 실행(SUDO 방식) 파라미터 설정 예시
oracle.install.db.rootconfig.executeRootScript=true
oracle.install.db.rootconfig.configMethod=SUDO
oracle.install.db.rootconfig.sudoPath=/usr/bin/sudo
oracle.install.db.rootconfig.sudoUserName=oracle
```

---

### 5.4.3 엔진 설치 버전 및 적용 패치(`opatch lsinventory`) 최종 검증

Root 스크립트 실행까지 완료되면 `sqlplus -V` 및 `opatch lspatches` 명령어를 실행하여 Oracle Database 19c 엔진 바이너리와 Release Update 패치가 정상적으로 설치되었는지 최종 확인합니다[1, 2].

```bash
# 1. SQL*Plus 바이너리 실행 및 RU 패치 버전 확인
$ sqlplus -V
SQL*Plus: Release 19.0.0.0.0 - Production
Version 19.19.0.0.0

# 2. OPatch를 통한 오라클 홈 적용 패치 목록 검증
$ opatch lspatches
35042068;Database Release Update : 19.19.0.0.230418 (35042068)
29585399;OCW RELEASE UPDATE 19.3.0.0.0 (29585399)

OPatch succeeded.
```

---

## 5.5 장 요약 (Chapter Summary)

이 장에서는 Headless(CUI) 환경에서 **Oracle Database 19c SE2 엔진 소프트웨어**를 이미지 기반 설치 방식과 Silent Mode로 구축하는 표준 절차를 완성했습니다.

* **이미지 기반 설치 및 환경 변수 설정**: `oracle` 계정의 `~/.bash_profile`에 `$ORACLE_BASE`와 `$ORACLE_HOME`을 먼저 정의한 후, `$ORACLE_HOME` 디렉터리 내부에서 직접 골드 이미지(`LINUX.X64_193000_db_home.zip`)의 압축을 해제하고 최신 `OPatch`를 적용했습니다.
* **`db_install.rsp` 응답 파일 표준화**: `INSTALL_DB_SWONLY` 옵션과 `SE2` 에디션, 그리고 Chapter 4에서 생성한 직무 분리 OS 그룹(`dba`, `oper`, `backupdba`, `dgdba`, `kmdba`, `racdba`)을 응답 파일 스키마에 맞춰 매핑했습니다.
* **`-applyRU` 결합 무인 설치 및 Root 스크립트 마감**: `./runInstaller -silent -waitforcompletion -applyRU` 명령을 통해 엔진 설치와 동시에 Oracle Linux 9 필수 인증 조건인 RU 19.19+ 패치를 원스톱으로 적용하고, `orainstRoot.sh` 및 `root.sh` 실행과 `opatch lspatches` 검증으로 엔진 구성을 마무리했습니다.

다음 **CHAPTER 06**에서는 설치된 오라클 엔진 위에 `netca -silent` 명령어로 Oracle Net Listener를 자동 구성하고, `listener.ora`, `tnsnames.ora`, `sqlnet.ora` 핵심 네트워크 파라미터를 최적화하는 방법을 상세히 다룹니다.

---

# References

[1] Oracle. 2024. *Oracle Database Installation Guide 19c for Linux (E96272)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/
[2] Oracle. 2024. *Oracle OPatch User's Guide (E86091)*. Oracle America, Inc. Retrieved September 30, 2026 from https://docs.oracle.com/en/middleware/fusion-middleware/13.9.4/opatch-users-guide/
