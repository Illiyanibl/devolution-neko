# devolution-neko

Кастомный Docker-образ Neko v3 для мобильных клиентов: поверх публичного
`ghcr.io/m1k1o/neko/chromium:latest` встроен **demodesk-frontend** с поддержкой
native touch protocol (опкоды `touchbegin/touchupdate/touchend`) и runtime-патчи
(CDP-флаги Chromium, `implicit_hosting`, socat-прокси для DevTools) применены
на этапе сборки, не в runtime.

## Зачем

Стандартный `m1k1o/neko/chromium:latest` идёт с legacy-frontend
(`m1k1o/neko/client` v2.5.0), у которого `client.sendData()` принимает только
`mousemove/wheel/keydown/mousedown/keyup/mouseup`. На мобильных клиентах
(iOS WKWebView, Android WebView) это означает: tap → mouse → xdotool → видимый
курсор; swipe → mouse-drag, не scroll.

Серверная сторона `m1k1o/neko/server` v3.x уже умеет принимать
`controlTouchBegin/Update/End`, но публичный bundle не подключён к этой фиче.
`@demodesk/neko@1.6.32` (npm, archived июнь 2024) имеет совместимый client с
native touch и сборку через `vue-cli-service build`.

## Использование

```bash
docker pull ghcr.io/illiyanibl/devolution-neko:latest

docker run -d \
  --name neko \
  --shm-size=2gb \
  --cap-add=SYS_ADMIN \
  -p 52000-52100:52000-52100/udp \
  -e NEKO_DESKTOP_SCREEN=1290x2517@30 \
  -e NEKO_SCREEN=1290x2517@30 \
  -e NEKO_PASSWORD=$(openssl rand -hex 16) \
  -e NEKO_PASSWORD_ADMIN=$(openssl rand -hex 16) \
  -e NEKO_EPR=52000-52100 \
  -e NEKO_NAT1TO1=<your-public-ip> \
  -e NEKO_CAPTURE_AUDIO_CODEC=opus \
  -v neko-profile:/home/neko/.config/chromium \
  --restart unless-stopped \
  ghcr.io/illiyanibl/devolution-neko:latest
```

URL для подключения через WebView мобильного клиента:
```
http://<host>:<port>/?usr=admin&pwd=<NEKO_PASSWORD_ADMIN>&embed=1&cast=1
```

Query-параметры:
- `usr`/`pwd` — auto-login (frontend читает их в `mounted()` и стирает из URL через `history.replaceState`).
- `embed=1` — скрывает sidebar/header/notifications.
- `cast=1` — скрывает video-toolbar (mouse/lock/file иконки), остаётся чистый канвас.

## Структура

- `Dockerfile` — multi-stage: Node 20 для сборки frontend → m1k1o-base + патчи + bundle.
- `frontend/` — клон `demodesk/neko-client` (master) с двумя патчами:
  - `src/page/components/connect.vue::mounted()` — auto-login по `?usr=&pwd=`.
  - `src/page/main.vue` — computed `embedMode`/`castMode` из URL; CSS-классы скрывают header/sidebar/room-controls; floating `.dvl-kbd-btn` для мобильной экранной клавиатуры (DOM-button = user-gesture внутри WebView).
- `supervisord/cdp-proxy.conf` — socat-прокси `0.0.0.0:9224 → 127.0.0.1:9223` (Chromium 146 биндит CDP только на localhost).
- `.github/workflows/build.yml` — GHA: build + push в GHCR на push, weekly cron, manual dispatch.

## Лицензии

- `frontend/` — наследует Apache-2.0 от `demodesk/neko-client`.
- Базовый image — Apache-2.0 (`m1k1o/neko`).
- Патчи — Apache-2.0.
