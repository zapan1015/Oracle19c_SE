# CHAPTER 06. `netca -silent`를 활용한 리스너 및 네트워크 구성

Oracle Database와 클라이언트 애플리케이션 간의 통신을 중개하는 Oracle Net Services 프로세스인 **리스너(Listener)**는 데이터베이스 수신 및 네트워크 세션 수락을 담당하는 인프라 핵심 레이어입니다 (출처: database-net-services-administrators-guide.pdf, 2019). Headless(Non-GUI) 환경에서는 GUI 기반의 Oracle Net Manager나 대화형 NETCA 대신 **`netca -silent`** 커맨드라인 인터페이스를 활용하여 리스너 및 네트워킹 환경을 비대화형으로 자동 구성합니다 (출처: administrators-reference-linux-and-unix-based-operating-systems.pdf, 2019).

본 장에서는 Response File을 통한 Silent 리스너 생성, 커맨드라인 기반의 `listener.ora` 및 `sqlnet.ora` 설정 최적화, `lsnrctl` 제어 유틸리티 활용, 그리고 클라이언트 연결 매핑을 위한 `tnsnames.ora` CLI 작성법을 단계별로 다룹니다.

---

## 6.1 Response File을 이용한 Silent 리스너 생성

### NETCA Silent Mode의 메커니즘

Oracle Net Configuration Assistant(NETCA)는 네트워크 서비스 구성 유틸리티입니다. Headless CUI 환경에서는 `-silent` 옵션과 `-responsefile` 파라미터를 결합하여 대화형 화면 호출 없이 네트워크 리스너 및 프로파일 설정을 즉시 완료할 수 있습니다 (출처: administrators-reference-linux-and-unix-based-operating-systems.pdf, 2019).

* **응답 파일 경로**: `$ORACLE_HOME/inventory/response/netca.rsp` 또는 오라클 홈 내부의 기본 응답 파일 템플릿을 복사하여 사용합니다.
* **환경 변수 참조**: NETCA 실행 시 `$ORACLE_HOME` 및 `$TNS_ADMIN` 환경 변수를 우선 탐색하여 `$ORACLE_HOME/network/admin` 경로에 설정 파일을 생성합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

---

### `netca.rsp` 응답 파일 핵심 매개변수 설정

`netca.rsp` 응답 파일 내에서 Silent 리스너 생성을 제어하는 핵심 파라미터 규격은 다음과 같습니다.

#### 표 6-1. `netca.rsp` 핵심 설정 매개변수 명세

| 매개변수 항목 | 설정값 예시 | 기능 및 설정 목적 |
| :--- | :--- | :--- |
| **`[COMPONENT_NS_RESPONSE_VERSION]`** | `"19.0.0"` | NETCA 응답 파일 스키마 버전 지정 |
| **`NUMBER_OF_LISTENERS`** | `1` | 생성할 오라클 리스너의 총 개수 |
| **`SHOW_COMPONENT_STATUS`** | `true` | CLI 콘솔상에 컴포넌트 구성 진행 상태 출력 |
| **`LISTENER_NAMES`** | `{"LISTENER"}` | 생성을 원하는 리스너의 고유 식별 명칭 (기본값: LISTENER) |
| **`LISTENER_PROTOCOLS`** | `{"TCP;1521"}` | 리스너가 바인딩할 바인딩 프로토콜 및 TCP 포트 번호 |
| **`LISTENER_START`** | `"LISTENER"` | 리스너 구성 완료 직후 즉시 구동할 리스너 이름 지정 |

---

### CLI 기반 Silent 리스너 생성 및 실행

수정된 `netca.rsp` 파일 경로를 지정하여 NETCA를 비대화형으로 실행합니다.

```bash
# netca -silent 실행 명령
$ netca -silent -responsefile $ORACLE_HOME/inventory/response/netca.rsp

Parsing command line arguments:
    Parameter "silent" = true
    Parameter "responsefile" = /u01/app/oracle/product/19.0.0/dbhome_1/inventory/response/netca.rsp
Done parsing command line arguments.

Oracle Net Services Configuration:
    Profile configuration complete.
    Listener configuration complete.
    Default local naming configuration complete.
Oracle Net Services configuration successful. The exit code is 0
```

---

## 6.2 커맨드라인 기반 `listener.ora` & `sqlnet.ora` 자동 생성 및 튜닝

### `$ORACLE_HOME/network/admin` 경로 및 `TNS_ADMIN` 환경 변수

오라클 네트워킹 설정 파일(`listener.ora`, `sqlnet.ora`, `tnsnames.ora`)은 기본적으로 `$ORACLE_HOME/network/admin` 디렉토리에 위치합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

만약 별도의 독립 디렉토리에서 네트워킹 설정 파일을 중앙 집중식으로 관리하고자 할 경우, OS 환경 변수 **`TNS_ADMIN`**을 지정하면 최우선으로 해당 경로의 파일을 참조합니다 (출처: administrators-reference-linux-and-unix-based-operating-systems.pdf, 2019).

```bash
# TNS_ADMIN 환경 변수 지정 예시 (선택 사항)
export TNS_ADMIN=/u01/app/oracle/network/admin
```

---

### `listener.ora` 구성 분석 및 정밀 튜닝

`netca -silent` 실행을 통해 자동 생성된 `$ORACLE_HOME/network/admin/listener.ora` 파일의 기본 구조와 실무 최적화 파라미터를 점검합니다 (출처: database-net-services-reference.pdf, 2019).

```ini
# $ORACLE_HOME/network/admin/listener.ora
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = dbserver.example.com)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )

# [엔터프라이즈 보안 및 성능 튜닝 파라미터]
# 1. 미인증 접속 타임아웃 제한 (초 단위: 기본값 60초)
INBOUND_CONNECT_TIMEOUT_LISTENER = 10

# 2. 리스너 원격 세팅 변경 제한 (기본값 ON)
ADMIN_RESTRICTIONS_LISTENER = ON

# 3. Dynamic Service Registration 권한 제어
VALID_NODE_CHECKING_REGISTRATION_LISTENER = SUBNET
```

#### 표 6-2. `listener.ora` 주요 튜닝 파라미터 해설

| 파라미터 항목 | 기본값 / 권장값 | 기능 및 설명 |
| :--- | :--- | :--- |
| **`INBOUND_CONNECT_TIMEOUT_<lsnr>`** | `60` / `10` | 클라이언트 접속 시 서비스 인증 요청 수신 대기 시간(초). DoS 공격 방지 (출처: database-net-services-reference.pdf, 2019). |
| **`ADMIN_RESTRICTIONS_<lsnr>`** | `OFF` / `ON` | `lsnrctl`을 통한 런타임 매개변수 동적 변경을 금지하여 리스너 보안 강화 (출처: database-net-services-reference.pdf, 2019). |
| **`VALID_NODE_CHECKING_REGISTRATION_<lsnr>`** | `OFF` / `SUBNET` | 승인된 서브넷/노드에서만 데이터베이스 동적 서비스 등록(Registration)을 허용 (출처: database-net-services-reference.pdf, 2019). |

---

### `sqlnet.ora` 클라이언트/서버 프로파일 파라미터 제어

`sqlnet.ora` 파일은 클라이언트 및 서버 측 네트워킹 전역 프로파일 규격을 정의합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

```ini
# $ORACLE_HOME/network/admin/sqlnet.ora
# 1. 이름 풀이 탐색 우선순위 지정 (TNSNAMES 우선 탐색)
NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)

# 2. 서버 수신 타임아웃 제한 (초 단위)
SQLNET.INBOUND_CONNECT_TIMEOUT = 10

# 3. Dead Connection Detection (DCD) 활성화 (분 단위: 19c부터 분 단위 권장)
SQLNET.EXPIRE_TIME = 10

# 4. OS 인증 서비스 제어
SQLNET.AUTHENTICATION_SERVICES = (ALL)
```

---

### `lsnrctl` 커맨드라인 관리 및 상태 검증

리스너 프로세스의 구동, 정지, 상태 모니터링은 **`lsnrctl` (Listener Control Utility)** 도구를 사용합니다 (출처: database-net-services-reference.pdf, 2019).

```bash
# 1. 리스너 상태 점검 (lsnrctl status)
$ lsnrctl status

LSNRCTL for Linux: Version 19.0.0.0.0 - Production on 30-SEP-2026 10:50:00

Connecting to (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=dbserver.example.com)(PORT=1521)))
STATUS of the LISTENER
------------------------
Alias                     LISTENER
Version                   TNSLSNR for Linux: Version 19.0.0.0.0 - Production
Start Date                30-SEP-2026 10:45:12
Uptime                    0 days 0 hr. 4 min. 48 sec
Trace Level               off
Security                  ON: Local OS Authentication
SNMP                      OFF
Listener Parameter File   /u01/app/oracle/product/19.0.0/dbhome_1/network/admin/listener.ora
Listener Log File         /u01/app/oracle/diag/tnslsnr/dbserver/listener/alert/log.xml
Listening Endpoints Summary...
  (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=192.0.2.100)(PORT=1521)))
  (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=EXTPROC1521)))
The listener supports no services
The command completed successfully

# 2. 등록된 서비스 핸들러 및 상태 모니터링 (lsnrctl services)
$ lsnrctl services
```

> **💡 [Technical Note] LREG 프로세스와 동적 서비스 등록 (Dynamic Service Registration)**
> 데이터베이스 인스턴스가 구동되면 오라클의 **LREG (Listener Registration Process)** 백그라운드 프로세스가 리스너(TCP 1521 포트)로 서비스 이름(`SERVICE_NAMES`)과 인스턴스 이름(`INSTANCE_NAME`)을 자동으로 등록합니다 (출처: database-net-services-administrators-guide.pdf, 2019).
>
> 따라서 `listener.ora` 파일 내에 `SID_LIST` 항목을 수동으로 명시하지 않아도 인스턴스 오픈 시 `READY` 상태로 동적 등록됩니다 (출처: database-net-services-administrators-guide.pdf, 2019).

---

## 6.3 `tnsnames.ora` CLI 구성 및 서비스 로컬 파라미터 작성

### Local Naming 방식과 `tnsnames.ora` 커넥트 디스크립터 구조

클라이언트 애플리케이션이나 DB 간 DB Link 접속 시 사용되는 식별자인 **Net Service Name**을 호스트 주소, 포트, 서비스 이름 매핑 구조로 작성한 파일이 `tnsnames.ora`입니다 (출처: database-net-services-reference.pdf, 2019).

```
[ Net Service Name (Alias) : ORCL ]
        │
        ├── PROTOCOL : TCP
        ├── HOST     : dbserver.example.com (또는 IP 192.0.2.100)
        ├── PORT     : 1521
        └── CONNECT_DATA
            └── SERVICE_NAME : orcl.example.com (또는 PDB 서비스명)
```

---

### `tnsnames.ora` 커맨드라인 작성 예제

단일 데이터베이스 접속 식별자 및 CDB/PDB 접근을 위한 `tnsnames.ora` 작성 예시는 다음과 같습니다.

```ini
# $ORACLE_HOME/network/admin/tnsnames.ora
# 1. CDB / Single Instance 접속 서비스 식별자
ORCL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.0.2.100)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = orcl.example.com)
    )
  )

# 2. Pluggable Database (PDB1) 전용 접속 서비스 식별자
PDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.0.2.100)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = pdb1.example.com)
    )
  )
```

---

### `tnsping` 및 SQL*Plus 접속 검증

작성된 네트워킹 서비스 이름 식별자가 올바르게 리스너에 도달하는지 검증하기 위해 `tnsping` 유틸리티와 `sqlplus` CLI 접속 테스트를 수행합니다 (출처: database-net-services-administrators-guide.pdf, 2019).

```bash
# 1. tnsping을 통한 네트워크 도달성 및 포트 검증 (성공 시 OK (msec) 출력)
$ tnsping ORCL

TNS Ping Utility for Linux: Version 19.0.0.0.0 - Production on 30-SEP-2026 10:55:00

Used parameter files:
/u01/app/oracle/product/19.0.0/dbhome_1/network/admin/sqlnet.ora

Used TNSNAMES adapter to resolve the alias
Attempting to contact (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = 192.0.2.100)(PORT = 1521)) (CONNECT_DATA = (SERVER = DEDICATED) (SERVICE_NAME = orcl.example.com)))
OK (10 msec)

# 2. SQL*Plus 식별자 접속 검증
$ sqlplus system/Oracle_1234#!@ORCL

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Sep 30 10:56:00 2026
Version 19.3.0.0.0

Connected to:
Oracle Database 19c Standard Edition 2 Release 19.0.0.0.0 - Production

SQL> SELECT instance_name, status, con_id FROM v$instance;

INSTANCE_NAME    STATUS       CON_ID
---------------- ------------ ----------
orcl             OPEN                  0
```

---

### 💬 기획 편집자 노트 (Next Step)

Chapter 6에서는 `netca -silent` 명령을 통한 네트워크 리스너 생성, `listener.ora` 및 `sqlnet.ora` 보안/성능 튜닝, `lsnrctl` 제어 유틸리티 활용, 그리고 `tnsnames.ora` CLI 구성 및 `tnsping` 검증까지 완벽하게 집필을 마쳤습니다.

이어지는 **CHAPTER 07**에서는 `dbca -silent` 명령어를 활용하여 Single Instance 또는 Multitenant CDB/PDB 데이터베이스를 비대화형 자동화 스크립트로 구축하는 실무 과정을 다루게 됩니다. CHAPTER 07 본문 집필을 계속 진행할까요?
