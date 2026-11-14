# LocationX 설치·검증 도구 (Install & Verify Tool)

LocationX BLE AoA 실내측위 시스템을 **설치(설정)하고 동작을 검증**하는 Windows 데스크톱 도구.
실행 파일: `locationx_install_tool_vX.Y.Z.exe` (v1.15.x까지 이름: locationx_position_setting_tool)

- 설정: 장소·층 / ① Locator 설정(UDP 검색·브로커·업데이트) / ② Tag 설정(검색·송신 주기·OTA, PC 또는 로케이터 경로) /
  ③ 위치 설정(도면·배치·자세·전역 설정 → 서버 전송) / ④ 로케이터 보정
- AOD 모드 (위치측위): 데이터 수신 / 내부망 / 외부망 — 도면 위 2D·3D 위치·각도 확인
- AOA 모드 (방향각): 로케이터별 방위·앙각 원·3D·그래프

고객 소프트웨어 연동(데이터 인터페이스·예제)은 별도 SDK: `../../SDK/locationx-sdk`
사용 설명: `../../SDK/locationx-sdk/docs/05_tool_guide.md`

## 빌드
```powershell
.\tools\build_windows.ps1          # 패치 버전 +1 후 빌드
.\tools\build_windows.ps1 -Minor   # 마이너 +1
.\tools\build_windows.ps1 -NoBump  # 버전 유지
```
결과: `build\windows\x64\runner\Release\locationx_install_tool_vX.Y.Z.exe` (Release 폴더째 배포)

## 데이터
- 세션 자동 저장: `%APPDATA%\LocationXPositionTool\session.json` (이전 버전과 호환 위해 폴더명 유지)
- 프로젝트 파일: `.lxpos.json`
