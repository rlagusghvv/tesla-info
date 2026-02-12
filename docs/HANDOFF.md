# Handoff (2026-02-10)

## Anti-Reset / Bootstrap (MANDATORY)
이 프로젝트는 컨텍스트가 날아가거나 모델/세션이 바뀌어도 운영 규칙이 유지되어야 합니다.

모든 봇/에이전트는 작업 시작 시 아래 2개를 **반드시 먼저 읽고** 그대로 따릅니다.
1) `docs/HANDOFF.md` (이 문서: 역할/규칙/금지사항)
2) `current_progress.md` (최신 진행상황/실행 로그/다음 단계)

그리고 작업이 끝나면:
- 변경 사항/결과/로그/재현법은 **MD에만** 남깁니다(아래 프로세스 섹션 참조)

---

## Communication / Process (MANDATORY)
- 오더: 김현호(대표) → **공영삼(영삼봇, 팀장)**
- 팀장(공영삼): 업무 분할/테스크 전달 + 최종 보고 + **빌드 업데이트까지 필수로 진행**
- 작업자(각 봇): 작업 수행 후 **MD 파일에만** 작업 내용/로그/결과/PR/커밋/재현법 정리
- 정리삼: MD 기반 1차 요약(역할/결과/리스크/다음 액션) 정리 후 **완료!**만 전송
- 텔레그램 운영 규칙(절대):
  - 팀장만 설명/대화 가능
  - 작업자/정리자는 **완료!** 한 단어만 전송(그 외 대화 금지)

### Non-reset policy (중심 규칙 / 절대 초기화 방지)
- 목적: 컨텍스트 압축/LLM 교체/세션 리셋이 있어도 **역할/프로세스/규칙**이 절대 초기화되지 않게 함.
- Canonical(진실의 원본) 문서:
  1) `docs/HANDOFF.md` (프로세스/규칙/역할)
  2) `current_progress.md` (작업 진행/현황/피드백 타임라인)
- 모든 에이전트는 세션 시작 시:
  - `docs/HANDOFF.md`의 프로세스를 최우선으로 따르고,
  - 새로운 규칙/변경은 반드시 `docs/HANDOFF.md`에 반영한 뒤 작업을 진행한다.
- 텔레그램 메시지 정책:
  - (팀장 제외) 텔레그램에서는 **"완료!" 외 금지**
  - 질문/설명/논의는 md로만 남긴다.

(주의) 본 문서는 `docs/HANDOFF.md`가 canonical입니다.
- 루트의 `HANDOFF.md`는 내부 메모/임시 파일로 남아있을 수 있으니 무시하세요.
- 프로세스상 커뮤니케이션/진행 기록은 `docs/HANDOFF.md` + `current_progress.md` 를 기준으로 합니다.

## Hard Rules (절대 위반 금지)
- 민감정보(예: ASC API Key .p8, 토큰/쿠키/개인정보)는 **어떤 MD/레포에도 원문을 남기지 않습니다.**
- 텔레그램에서는(팀장 제외) **완료! 외 모든 텍스트 전송 금지**
- 새 에이전트/LLM/세션이 떠도 위 규칙을 최우선으로 강제

## 지금 상태 (요약)
- iPad 앱 `Car Mode` 중앙 패널에 `Map / Navi / Media`가 있음.
- `Navi`는 "카카오 REST API" 기반으로 목적지 검색 + 경로(폴리라인) 오버레이를 하는 MVP.
- iPad GPS를 쓰지 않고, Tesla Fleet API의 `drive_state` 좌표(차량 위치)를 "내 위치"로 사용.

## 오늘 반영된 변경점
- `Navi` 탭 추가
  - 목적지 검색: Kakao 키워드 검색 API
  - 경로 요청: KakaoMobility Directions API
  - 지도 표시: MapKit 위에 폴리라인 표시 + next guide 텍스트
- 안정화
  - 경로 폴리라인을 다운샘플링(최대 900 포인트)해서 MapKit 프리즈 위험 낮춤
  - 경로가 있는 동안에는 차량 좌표가 갱신돼도 카메라를 계속 재포커싱하지 않도록 변경
  - Media(WKWebView) 검은 화면 발생 시 자동 reload
  - 핫스팟 인터넷이 끊겨도 Car Mode에서 바로 튕겨나가지 않도록 라우팅 조건 완화
  - 오프라인 배너/오프라인 시 Navi 검색/경로 요청 차단
- UI
  - iPad에서 `.segmented` Picker가 터치가 안 먹는 이슈가 있어서, 자체 세그먼트 버튼 UI로 교체
- 차량 위치 안정화(Origin)
  - Tesla API 호출 시 VIN 대신 `vehicle id`가 있으면 우선 사용(일부 계정에서 더 안정적)
  - `vehicle_data`에서 위치가 안 오면 `data_request/drive_state`를 추가로 호출해 위치를 보강(25초 백오프)
  - 위치가 없으면 사이드 패널에 `Unknown (tap Wake)`로 표시
  - Navi 탭의 How-to 카드에 `Wake vehicle` 버튼 추가
- OAuth scope/권한
  - `vehicle_location` scope를 요청하도록 변경 (차량 위치/drive_state lat/lon 안정화)
  - authorize URL에 `prompt_missing_scopes=true` 추가 (나중에 scope 추가 시 재동의 유도)
  - refresh token 갱신 시에도 `audience`를 포함하도록 수정 (갱신 후 Unauthorized 방지)

## 키 설정 (카카오)
1. 카카오 개발자 콘솔에서 앱 생성
2. `REST API Key` 복사
3. iPad 앱에서 `Account`(또는 Connection Guide) -> `Navigation (Kakao)`에 붙여넣고 `Save`

주의:
- 지금 MVP는 키를 iOS Keychain에 저장하지만, "앱스토어 배포" 단계에선 키를 앱에 넣는 방식이 적합하지 않음.
  - 배포용은 백엔드 프록시/서버에서 호출하도록 전환 필요.

## 사용 방법 (Navi)
1. Car Mode 진입
2. 중앙 상단에서 `Navi`
3. 목적지 입력 -> `Search`
4. 결과 탭 -> 경로 표시

추가 팁:
- 차량 위치가 `0,0`이면 출발지를 만들 수 없음.
  - 우측의 `Wake`로 차량을 깨우고 위치가 들어오는지 확인.

## 오프라인 동작
- 인터넷이 끊기면 상단에 `Offline. Waiting for hotspot internet.` 배너가 표시됨.
- 오프라인 상태에서는:
  - Tesla refresh/command 버튼은 disabled
  - Navi 검색/경로 요청 시 "Offline" 에러 메시지

## 파일 위치 (핵심)
- Navi UI: `Sources/Features/Navi/KakaoNavigationPaneView.swift`
- Navi 상태/로직: `Sources/Features/Navi/KakaoNavigationViewModel.swift`
- Navi 지도/폴리라인: `Sources/Features/Navi/KakaoRouteMapView.swift`
- Kakao API 클라이언트: `Sources/Kakao/KakaoAPIClient.swift`
- Kakao 키 저장(Keychain): `Sources/Kakao/KakaoConfigStore.swift`

## 다음 작업 후보
- "과속 카메라"를 인앱에서 하려면:
  - KakaoMobility Directions 응답에 SDI/카메라 포인트가 포함되는지 확인
  - 포함된다면 해당 필드를 파싱해서 경고 UI/사운드(로컬 알림/오디오) 설계
  - 포함되지 않는다면: KakaoNavi UI SDK(내비 UI 포함)로 전환 검토
- 프리즈가 재현되면:
  - 폴리라인 maxPoints를 더 낮추기(예: 300)
  - 경로 표시를 "확정 버튼" 이후에만 렌더링하도록 단계 분리

## (신규) 인증/권한 트러블슈팅
- `Account` 화면에서:
  - `Test Vehicles`: `/api/1/vehicles` 호출 확인
  - `Test Snapshot`: `/vehicle_data` 호출 확인(여기서 Unauthorized가 나면 scope/audience 문제일 확률이 높음)
  - `Diagnostics`에서 JWT `aud`/`scopes`를 확인 가능 (Debug 빌드)

## (신규) TestFlight 업로드 키(ASC API Key) 공유 방식
- 키 파일(.p8)은 채팅으로 공유하지 말고, **로컬 공용 폴더 경로**로 공유.
- 이 맥미니에서는 아래 경로에 복사해둠(권한 600/700):
  - `~/Shared/TeslaSubDash/secrets/appstoreconnect/AuthKey_*.p8`
  - `~/Shared/TeslaSubDash/secrets/appstoreconnect/issuer_id.txt`
- fastlane 실행용 env는 로컬 파일로 관리:
  - `tesla-subdash-starter/fastlane/.env.asc` (git 제외)

---

# Update (2026-02-11)

## 해결하려는 문제
- 공식 Tesla 앱에서는 차량 위치가 잘 보이는데, 이 앱의 Fleet API `vehicle_data`는 위치가 `(0,0)`으로 나오는 케이스가 있었음.
- `Wake` 버튼이 종종 "Please sign in again"처럼 보여서(실제로는 wake 엔드포인트/호출 방식 문제일 가능성) UX가 혼란스러웠음.

## 오늘 반영된 변경점
- Fleet API `vehicle_data` 호출에 `location_data` 포함
  - Tesla 차량 펌웨어 `2023.38+`에서는 위치가 기본적으로 반환되지 않을 수 있어서, `endpoints`에 `location_data`를 명시적으로 추가.
  - 적용 파일: `Sources/Tesla/TeslaFleetService.swift`
- `wake_up` 엔드포인트 수정
  - `wake_up`은 Fleet API에서 `/command/wake_up`이 아니라 `/wake_up`로 호출해야 함.
  - 적용 파일: `Sources/Tesla/TeslaFleetService.swift`
- VIN 우선 사용
  - 저장된 VIN이 있으면 먼저 사용하도록 변경(문서/엔드포인트 규격과 일치시키기 위함).
  - 적용 파일: `Sources/Tesla/TeslaFleetService.swift`

## 확인 방법 (iPad)
1. `Account` 화면에서 `Test Vehicles` -> `Vehicles: 1`이면 OK.
2. `Test Snapshot` -> 위치가 `0,0`이 아니면 성공.
3. Car Mode에서 `Wake` 누른 뒤 5-10초 후 `Refresh` -> 위치 갱신 확인.
