# Oracle Linux 9 & Oracle Database 19c SE2 Silent Mode 구축·운영 가이드

GUI를 배제하고 전 과정을 CUI / CLI / Silent Mode 기반으로 구축하는 엔터프라이즈 Oracle Database 19c Standard Edition 2(SE2) 및 Oracle Linux 9(UEK R7) 자동화 구축·운영 가이드 프로젝트입니다.

---

## 📁 디렉토리 구조 (Directory Structure)

```plaintext
Oracle_SE/
├── .gitignore          # VirtualBox, Python, Go, Oracle 민감정보 보안 관리용
├── README.md           # 프로젝트 소개 및 가이드
└── Books/              # 출판 원고 및 기술 챕터 마크다운 문서
    ├── se_install_guide.md  # 도서 출판 기획서 및 상세 목차
    ├── CHAPTER_01.md        # 아키텍처 및 라이선스 제약 분석
    ├── CHAPTER_02.md        # 하드웨어 사이징 및 리소스 설계
    ├── CHAPTER_03.md        # 스토리지 아키텍처 및 볼륨 설계
    ├── CHAPTER_04.md        # 네트워크 아키텍처 및 보안 설계
    ├── CHAPTER_05.md        # Oracle Linux 9 Silent 설치 및 Minimal 환경
    ├── CHAPTER_06.md        # OS 파라미터 튜닝 및 사전 요구조건 구성
    ├── CHAPTER_07.md        # Oracle 19c SE2 엔진 Silent 무인 설치
    ├── CHAPTER_08.md        # 리스너(Listener) Silent 구성 및 네트워크 기동
    ├── CHAPTER_09.md        # DBCA 무인 데이터베이스 생성 및 PDB 구성
    ├── CHAPTER_10.md        # systemd 기반 인스턴스 자동 기동 및 무중단 관리
    ├── CHAPTER_11.md        # 필수 유지관리 스크립트 및 헬스체크 자동화
    └── CHAPTER_12.md        # 장애 복구 시나리오 및 트러블슈팅 핸드북
```

---

## 🔒 보안 및 `.gitignore` 정책

본 저장소는 **Public Repository** 환경에 맞춰 다음 항목들의 누출을 원천 방지하도록 `.gitignore`가 설정되어 있습니다.

1. **VirtualBox 가상화 산출물**: `*.vdi`, `*.vmdk`, `*.vbox`, `*.sav`, `*.ova` 등 대용량 가상 디스크 및 상태 파일
2. **Oracle Database 민감 데이터**: Wallet/Keystore(`cwallet.sso`, `*.p12`), 데이터 덤프(`*.dmp`), 트레이스(`*.trc`, `*.trm`), 알림 로그(`alert_*.log`)
3. **보안 비밀정보**: `.env*`, 개인키(`*.key`, `*.pem`, `id_rsa`, `id_ed25519`), 서비스 계정 키 등
4. **Python & Go 개발 환경**: 가상환경(`venv/`, `.venv/`), 바이트코드(`__pycache__/`), 컴파일 바이너리(`bin/`, `*.exe`, `*.test`) 및 빌드 캐시
