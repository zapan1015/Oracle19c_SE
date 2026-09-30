# Oracle Linux 9 Vagrant 환경 (CHAPTER 01 & 02 테스트 랩)

본 디렉터리는 [CHAPTER 01.md](file:///c:/Users/zapan/Documents/Oracle_SE/Books/CHAPTER_01.md) 및 [CHAPTER 02.md](file:///c:/Users/zapan/Documents/Oracle_SE/Books/CHAPTER_02.md)의 아키텍처와 하드웨어 사이징 규격을 직접 검증할 수 있도록 구성된 **Oracle Linux 9 Headless(Non-GUI) 전용 Vagrant 가상머신 환경**입니다.

오라클 데이터베이스 엔진 설치 전 단계로, **Oracle Linux 9 OS만 깨끗하게 구동(`Oracle Linux 만 뜰 수 있도록`)**하여 커널, 메모리, 스왑, 스토리지 분리(LVM) 설계를 단계별로 테스트할 수 있습니다.

---

## 1. Box 사양 및 출처

* **공식 Box 명칭**: `oraclelinux/9`
* **Box 다운로드 출처**: [https://yum.oracle.com/boxes/](https://yum.oracle.com/boxes/)
* **메타데이터 URL**: `https://oracle.github.io/vagrant-projects/boxes/oraclelinux/9.json`
* **운영체제 및 커널**: Oracle Linux 9 (Unbreakable Enterprise Kernel Release 7, UEK R7)

---

## 2. 호스트 환경 분석 및 최적 사이징 근거

현재 사용자 호스트 하드웨어 자원을 정밀 진단하여, 호스트의 안정성을 해치지 않으면서 책의 요구조건을 100% 충족하도록 최적 사이징을 도출했습니다.

| 항목 | 호스트 사양 (Current Host) | VM 할당 규격 (Sizing) | CHAPTER 01 / 02 설계 근거 |
| :--- | :--- | :--- | :--- |
| **CPU** | AMD Ryzen 7 5800H (8코어 / 16스레드) | **2 vCPUs** (환경변수 `VM_CPUS`로 조절 가능) | SE2 인스턴스당 최대 16스레드 제한(제1장) 준수 및 호스트 CPU 부담 최소화 |
| **RAM** | 16 GB 물리 RAM (15.4 GB 가용) | **6,144 MB (6 GB)** (환경변수 `VM_MEMORY`로 조절 가능) | 호스트에 약 10 GB의 여유 메모리를 보존하면서, 20% OS(1.2GB) / 80% DB(4.8GB) 원칙 반영. 특히 **DB 메모리가 4GB를 초과하므로 AMM 금지 및 ASMM 필수 원칙(제2장 2.1.2절)**을 실습하기에 최적 |
| **Swap** | - | **6,144 MB (6 GB)** | 제2장 표 2-3의 공식 기준(2GB 초과 ~ 16GB 이하: RAM과 1:1 매핑) 충족 |
| **스토리지** | C: 드라이브 약 110 GB 여유 SSD | **5개 독립 가상 디스크 (총 80 GB)** | VirtualBox의 **동적 확장(Thin Provisioning) VDI** 방식을 적용하여 초기 호스트 디스크 점유 용량은 0MB에 가깝게 유지 |
| **모드** | Windows 11 GUI | **Strict Headless (Non-GUI)** | 제1장 1.3절의 Non-GUI(Headless) 실무 원칙 반영 (`gui = false`) |

---

## 3. OFA 스토리지 다중화 레이아웃 (CHAPTER 02)

제2장 2.3절의 I/O 격리 아키텍처를 테스트할 수 있도록 5개의 가상 디스크가 VM에 자동 매핑됩니다.

| 디스크 디바이스 | 볼륨 그룹 (VG) | 마운트 포인트 | 할당 크기 | 권장 마운트 옵션 및 용도 |
| :---: | :---: | :---: | :---: | :--- |
| `/dev/sdb` | `vg_ora_app` | `/u01` | **30 GB** | `defaults` (ORACLE_BASE, ORACLE_HOME, Inventory) |
| `/dev/sdc` | `vg_ora_data` | `/u02/oradata` | **20 GB** | `noatime,nodiratime` (데이터파일, Undo, Temp) |
| `/dev/sdd` | `vg_ora_redo1` | `/u03/oraredo1` | **5 GB** | `noatime,nodiratime` (Online Redo Log 멤버 1, 제어파일 1) |
| `/dev/sde` | `vg_ora_redo2` | `/u04/oraredo2` | **5 GB** | `noatime,nodiratime` (Online Redo Log 멤버 2, 제어파일 2) |
| `/dev/sdf` | `vg_ora_fra` | `/u05/fast_recovery_area` | **20 GB** | `noatime,nodiratime` (Fast Recovery Area, 아카이브로그) |

---

## 4. 디렉터리 구성 및 스크립트 안내

```plaintext
Vagrant/
├── Vagrantfile                    # Oracle Linux 9 가상머신 정의 및 리소스 사이징 파일
├── README.md                      # 환경 가이드 및 사이징 설명서
└── scripts/
    ├── setup_os_base.sh           # VM 부팅 시 자동 실행되는 기본 OS 및 Swap 구성 스크립트
    ├── setup_storage_ch2.sh       # 제2장 2.3.4절 LVM/XFS/noatime 마운트 원클릭 실습 스크립트
    └── verify_ch1_ch2.sh          # 제1장 & 제2장 규격 준수 상태 종합 점검 스크립트
```

---

## 5. 실행 및 테스트 절차 (How to Run)

### 1) Oracle Linux 9 가상머신 구동

호스트 터미널(PowerShell 또는 bash)에서 `Vagrant` 디렉터리로 이동한 후 가상머신을 기동합니다.

```powershell
cd c:\Users\zapan\Documents\Oracle_SE\Vagrant

# 가상머신 기동 (최초 실행 시 Box 다운로드 자동 진행)
vagrant up

# 가상머신 SSH 접속
vagrant ssh
```

> 💡 **메모리/CPU 변경 실행 (선택 사항)**
> 기본값(2 vCPU, 6GB RAM) 외에 8GB RAM으로 띄우고 싶다면 다음과 같이 환경변수를 주어 실행할 수 있습니다.
> ```powershell
> $env:VM_MEMORY=8192; vagrant up
> ```

---

### 2) 제1장 & 제2장 기본 사양 검증 (VM 내부)

가상머신 접속 후 기본 점검 스크립트를 실행합니다.

```bash
[vagrant@ol9-se2 ~]$ /vagrant/scripts/verify_ch1_ch2.sh
```

* **확인 항목**:
  * Oracle Linux 9 배포판 버전 및 UEK R7 활성화 여부
  * `CONFIG_IO_URING=y` 지원 상태
  * 6 GB 물리 RAM 및 6 GB Swap 구성 확인
  * Non-GUI(`multi-user.target`) 부팅 모드 확인

---

### 3) 제2장 LVM 및 스토리지 마운트 실습 (VM 내부)

제2장 2.3.4절의 LVM 생성, XFS 포맷, `noatime,nodiratime` 영구 마운트 절차를 원클릭으로 실행하거나 수동으로 한 줄씩 실습할 수 있습니다.

```bash
# 원클릭 자동 구성 스크립트 실행
[vagrant@ol9-se2 ~]$ sudo /vagrant/scripts/setup_storage_ch2.sh

# 마운트 결과 확인
[vagrant@ol9-se2 ~]$ df -hT /u01 /u02/oradata /u03/oraredo1 /u04/oraredo2 /u05/fast_recovery_area
```

---

### 4) 가상머신 관리 명령어

```powershell
# 가상머신 상태 확인
vagrant status

# 가상머신 일시 정지 (종료)
vagrant halt

# 가상머신 재부팅
vagrant reload

# 가상머신 완전 삭제
vagrant destroy -f
```
