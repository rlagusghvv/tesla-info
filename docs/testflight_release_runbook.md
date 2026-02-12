# TeslaSubDash – TestFlight Release Runbook (CLI)

목표: **Mac mini에서 CLI로 빌드+TestFlight 업로드를 재현 가능**하게 만든다.

## 작업 경로
- Repo: `/Users/kimhyunhomacmini/tesla-info/_repo`
- fastlane 실행 위치: `/Users/kimhyunhomacmini/tesla-info/_repo/tesla-subdash-starter`
- Xcode project: `TeslaSubDash.xcodeproj` (fastlane에서는 `../TeslaSubDash.xcodeproj`로 참조)
- Scheme: `TeslaSubDash`
- Bundle ID: `com.kimhyeonho.teslasubdash`

## 0) 사전 조건

### Xcode
```bash
xcodebuild -version
xcode-select -p
```

### Ruby/Bundler (중요)
macOS 기본 ruby(2.6) + bundler(1.x) 조합은 이 레포의 bundler lock과 충돌할 수 있습니다.

권장(홈브루 ruby 사용):
```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
ruby -v
bundle -v
```

## 1) App Store Connect API Key 발급 위치

1. App Store Connect → Users and Access
2. Keys 탭 → App Store Connect API
3. 새 Key 생성 후 `.p8` 다운로드

주의:
- `.p8` 파일은 **절대 git 커밋 금지**
- 로컬 절대 경로로만 참조

## 2) 환경변수 세팅

예시(`~/.teslasubdash_asc.env`):
```bash
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_PATH="/absolute/path/to/AuthKey_XXXXXXXXXX.p8"
export APPLE_TEAM_ID="YOUR_TEAM_ID"

# Recommended: allow Xcode to fetch/update signing assets using ASC auth key
export ALLOW_PROVISIONING_UPDATES=true

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
```

적용:
```bash
source ~/.teslasubdash_asc.env
```

## 3) 실행 명령 (한 줄)

```bash
cd /Users/kimhyunhomacmini/tesla-info/_repo/tesla-subdash-starter
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
source ~/.teslasubdash_asc.env
bundle install
bundle exec fastlane ios beta
```

lane 동작:
- build number 자동 증가
- archive 생성
- app-store-connect export
- TestFlight 업로드
- build processing 대기 skip(기본 true)

## 4) 대표 실패 케이스 & 해결

### A) `Missing required env var: ASC_KEY_ID`
- 원인: ASC env 미세팅
- 해결: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, `APPLE_TEAM_ID` 세팅

### B) Signing / Provisioning 관련 에러
- 원인: 인증서/프로파일 불일치, 팀/번들ID 불일치
- 해결:
  - `ALLOW_PROVISIONING_UPDATES=true` 유지(ASC auth로 portal 동기화)
  - Team ID / Bundle ID 재확인
  - 그래도 실패하면 Apple Developer 계정 권한/인증서 상태 점검

### C) 업로드 권한/인증 실패
- 원인: API key 권한(Role) 부족
- 해결: App Store Connect에서 Key 권한 확인/재발급
