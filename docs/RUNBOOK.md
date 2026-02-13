# RUNBOOK — Tesla SubDash backend + Cloudflared (mac mini)

이 문서는 **"리붓(재기동) 해줘"** 요청을 받았을 때, 운영자가 빠르게 복구/점검할 수 있도록 정리한 런북입니다.

## 0) 구성
- repo path: `/Users/kimhyunhomacmini/tesla-info/_repo`
- docker compose 서비스:
  - `backend` (Node, port 8787)
  - `cloudflared` (Cloudflare Tunnel)

## 1) 정상 재기동(기본)
```bash
cd /Users/kimhyunhomacmini/tesla-info/_repo

git pull --rebase origin main

docker compose up -d --build backend cloudflared

docker compose ps
```

### 로그 확인
```bash
# backend
docker compose logs --tail=80 backend

# cloudflared
docker compose logs --tail=120 cloudflared
```

## 2) 정상 상태 기준
- `backend`: `Up (healthy)`
- `cloudflared`: `Up` 이고, 로그에 `Registered tunnel connection`이 찍힘

## 3) Cloudflared 실행 방식(중요: 실수 방지)
cloudflared는 크게 2가지 방식이 있음.

### A) Token 방식 (주의)
- 실행: `cloudflared tunnel run --token <TOKEN>`
- 필요: `.env`에 `CF_TUNNEL_TOKEN` 필수
- **CF_TUNNEL_TOKEN이 비어있으면 컨테이너가 Restarting(255) 루프**에 빠짐

### B) Credentials-file 방식 (현재 이 repo의 docker 기본값)
- 실행: `cloudflared --config /etc/cloudflared/config.yml tunnel run`
- 필요:
  - credential json(= tunnel credentials) 파일
  - config.yml에 `tunnel` + `credentials-file` + `ingress` 설정

현재 docker compose는 아래를 사용한다:
- 로컬 credential json을 컨테이너로 mount
  - `${HOME}/.cloudflared/790d9e75-55ef-43d1-95d4-ffe8a30cf752.json` → `/etc/cloudflared/creds.json`
- repo 내 docker용 config
  - `./cloudflared/config.yml` → `/etc/cloudflared/config.yml`

> 운영 규칙: **token 방식으로 바꿀 때는 반드시 .env에 CF_TUNNEL_TOKEN이 포함되도록** 하고,
> credentials-file 방식으로 바꿀 때는 **mount 경로/파일 존재/권한**을 먼저 확인.

## 4) 자주 나는 장애와 조치

### (1) cloudflared가 Restarting (255)
확인:
```bash
docker compose ps
docker compose logs --tail=200 cloudflared
```
원인 후보:
- token 방식인데 `.env`에 `CF_TUNNEL_TOKEN` 누락
- credentials-file mount 경로가 틀림(파일 없음)
- `cloudflared/config.yml` 문법/ingress 문제

조치(현재 기본값 기준):
- 로컬 파일 존재 확인
```bash
ls -la ${HOME}/.cloudflared/790d9e75-55ef-43d1-95d4-ffe8a30cf752.json
ls -la /Users/kimhyunhomacmini/tesla-info/_repo/cloudflared/config.yml
```
- 그 다음 재기동
```bash
docker compose up -d cloudflared
```

### (2) backend는 healthy인데 외부 도메인 접속이 안 됨
- 대부분 cloudflared 문제(위 Restarting 이슈)
- cloudflared 로그에 `Registered tunnel connection`이 있는지 확인

### (3) backend 로그에 `teslamate poll fetch failed`
이건 cloudflared와 별개로 **TeslaMate API 연결 문제**인 경우가 많음.
- 컨테이너에서 `127.0.0.1:8080`은 “컨테이너 자기 자신”을 의미하므로 실패할 수 있음
- 일반적으로 호스트의 TeslaMate를 보려면 `TESLAMATE_API_BASE=http://host.docker.internal:8080` 사용

(단, 운영자가 의도적으로 TeslaMate 폴링을 끈다면 `.env`에서 `USE_TESLAMATE=0` / `POLL_ENABLED=0` 등으로 비활성화)

## 5) 참고 파일
- `docker-compose.yml`
- `cloudflared/config.yml` (docker용)
- 호스트 측 cloudflared 설정(참고): `~/.cloudflared/config.yml`
