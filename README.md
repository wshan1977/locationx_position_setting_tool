# LocationX Position Setting Tool

AoA 로케이터 카드(라즈베리파이)를 LAN에서 검색해 도면 캔버스에 드래그앤드롭으로 배치하고,
MQTT 서버 카드의 `positioning_config.json`을 업데이트하는 Windows 데스크톱 도구.

## 화면 구성

```
┌──────────────────────── 툴바 ────────────────────────┐
│ 프로젝트 │ 도면 불러오기 │ 스케일 보정 │ 원점 │ [서버로 전송] │
├──────────┬──────────────────────────┬───────────────┤
│ 왼쪽 패널 │        중앙 캔버스        │  오른쪽 패널   │
│ 선택 로케 │  도면 이미지 + m 그리드    │  [카드 검색]   │
│ 이터 설정 │  로케이터 마커 (드래그 이동)│  서버 카드     │
│ / 전역   │  휠 줌 / 드래그 팬        │  로케이터 목록  │
│ 설정     │                          │  (드래그 소스)  │
└──────────┴──────────────────────────┴───────────────┘
```

## 사용 순서

1. **카드 검색** — UDP 40010 브로드캐스트로 서버 카드/로케이터 카드 검색
2. **도면 불러오기** — 바닥 도면 이미지(png/jpg) 선택
3. **스케일 보정** — 도면에서 거리를 아는 두 점 클릭 → 실거리(m) 입력
4. **원점 설정** — world (0,0)으로 쓸 위치 클릭
5. 오른쪽 목록의 로케이터를 **캔버스로 드래그**해 배치 (z 기본 3.0m, orientation 0/180/90)
6. 마커 클릭 → 왼쪽 패널에서 좌표/자세/AoA 상세 설정 편집
7. **서버로 전송** — diff 확인 → 스테이징 저장 → 적용(+aoa-positioning 재시작)
8. 프로젝트 저장(`.lxpos.json`)으로 도면/보정/배치를 로컬에 보관

## 서버 요구사항

서버 카드의 `locationx_config_server.py`가 **v1.1.0 이상**이어야 합니다
(`/api/status`, `/api/positioning`, `/api/apply` JSON API 포함 —
`locationx_mqtt_server_config` 저장소에서 배포).

## 개발

```powershell
flutter pub get
flutter run -d windows
flutter test                 # 단위 테스트
flutter build windows        # 릴리스 빌드
flutter build apk            # Android 빌드
```

### 안드로이드 스튜디오에서 실행

1. Android Studio → **Open** → 이 폴더 선택 (Flutter/Dart 플러그인 필요)
2. 상단 실행 구성에서 선택:
   - **Windows (desktop)** — Windows 데스크톱으로 실행 (`-d windows` 고정)
   - **Android (선택한 기기)** — 툴바에서 고른 기기/에뮬레이터로 실행
3. Android 기기에서 쓸 때 주의:
   - 기기가 라즈베리파이 카드들과 **같은 Wi-Fi(서브넷)** 에 있어야 UDP 검색이 됩니다
   - config 서버가 http(비암호화)라서 매니페스트에 `usesCleartextTraffic=true` 적용됨
   - 프로젝트 저장은 Android 저장소 프레임워크(SAF)를 통해 항상 저장 다이얼로그를 띄웁니다
   - 에뮬레이터는 호스트 LAN 브로드캐스트가 막혀 있어 실기기 테스트를 권장

### 이 PC의 Gradle TLS 설정 (Avast)

이 PC는 Avast 백신이 TLS를 가로채(dl.google.com 인증서를 Avast 루트로 교체)
Gradle의 Android 플러그인 다운로드가 실패한다. 해결책으로
`%USERPROFILE%\.gradle\gradle.properties` 에서 JBR cacerts + Avast 루트를 합친
truststore(`%USERPROFILE%\.gradle\cacerts-avast`)를 지정해 두었다.

Avast가 루트 인증서를 갱신해 다시 빌드가 깨지면 재생성:

```powershell
$jbr = "C:\Program Files\Android\Android Studio\jbr"
$cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'Avast' | Select-Object -First 1
Export-Certificate -Cert $cert -FilePath "$env:USERPROFILE\.gradle\avast_root.cer" -Type CERT
Copy-Item "$jbr\lib\security\cacerts" "$env:USERPROFILE\.gradle\cacerts-avast" -Force
& "$jbr\bin\keytool.exe" -importcert -keystore "$env:USERPROFILE\.gradle\cacerts-avast" `
  -storepass changeit -noprompt -alias avast-webshield-root -file "$env:USERPROFILE\.gradle\avast_root.cer"
```

### 하드웨어 없이 테스트 (mock)

```powershell
# 가짜 로케이터 3개 + 서버 카드 1개 응답
python tools/mock/mock_discover_agent.py

# 실제 config 서버를 %TEMP% 경로로 실행 (포트 8080)
python tools/mock/mock_config_server.py

# 라이브 UDP 테스트 (mock discover agent 필요)
flutter test test/discovery_live_test.dart --tags live
```

mock 실행 상태에서 앱을 켜면 검색→배치→전송 전체 사이클을 로컬에서 확인할 수 있고,
결과는 `%TEMP%\locationx_mock\` 아래에 기록됩니다.

## 프로토콜 요약

- **디스커버리**: UDP 40010에 `{"type":"DISCOVER"}` → `DISCOVER_RESPONSE`.
  `cap` 필드가 있으면 로케이터 카드, 없으면 MQTT 서버 카드.
- **로케이터 ID**: `ble-pd-` + MAC(콜론 제거, 대문자). 예: `ble-pd-4C5BB3CAD71E`
- **전송**: `GET /api/positioning` → 병합(locators는 캔버스 배치로 전체 교체)
  → `POST /api/positioning` → `POST /api/apply {"restart":true}`
- 좌표계: world는 미터 단위 y-up, `coordinate.x/y`는 캔버스 배치, `z`는 설치 높이
