# syntax=docker/dockerfile:1.7
#
# devolution-neko — Neko v3 server (m1k1o/neko/chromium:latest) с встроенным
# demodesk-frontend bundle (поддержка native touch) и runtime-патчами в build-time.
# Снимает зависимость от ручного деплоя bundle на VPS — образ полностью
# самодостаточен. iOS-приложение делает только `docker run` без последующих
# sed/apt-get/cp шагов.

# ---------------------------------------------------------------------------
# Stage 1: собираем frontend (Vue 2 + @demodesk/neko Vue-компонент).
# Используем готовый Node 20 image, исключаем dev-cache из финального слоя.
# ---------------------------------------------------------------------------
FROM node:20-slim AS frontend-builder
WORKDIR /build

# Сначала только манифесты — слой кешируется пока не меняется package*.json.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

# Потом исходники + конфиги. Сборка через build:page (vue-cli-service build
# без --target lib — даёт standalone HTML+JS+CSS, не Vue-компонент-библиотеку).
COPY frontend/ ./
RUN npm run build:page

# ---------------------------------------------------------------------------
# Stage 2: финальный image — поверх m1k1o/neko/chromium с патчами + bundle.
# ---------------------------------------------------------------------------
FROM ghcr.io/m1k1o/neko/chromium:latest

# Все патчи требуют root, переключаемся.
USER root

# Один RUN — один слой. Объединяем chromium-флаги, neko.yaml, apt и cleanup.
#
# Chromium-флаги:
#   --remote-debugging-port / address / origins  → CDP-доступ (через socat-proxy
#     на :9224, потому что Chromium 146 жёстко биндит DevTools на 127.0.0.1).
#   --touch-events=enabled                        → форсит TouchEvent API на
#     странице (без него auto-detect Chromium может игнорировать X11 touch).
#
# Neko-конфиг:
#   implicit_hosting: true → первый клиент авто-получает host без UI-кнопки
#     (с cast=1 в URL UI Neko-фронта скрыт, кнопки взять-host нет).
#
# socat — для CDP-proxy supervisord-программы (cdp-proxy.conf копируется ниже).
RUN set -eux; \
    grep -Fq -- "--remote-debugging-port=9223" /etc/neko/supervisord/chromium.conf || \
        sed -i '/--no-sandbox/i\  --remote-debugging-port=9223' /etc/neko/supervisord/chromium.conf; \
    grep -Fq -- "--remote-debugging-address=0.0.0.0" /etc/neko/supervisord/chromium.conf || \
        sed -i '/--no-sandbox/i\  --remote-debugging-address=0.0.0.0' /etc/neko/supervisord/chromium.conf; \
    grep -Fq -- "--remote-allow-origins=*" /etc/neko/supervisord/chromium.conf || \
        sed -i '/--no-sandbox/i\  --remote-allow-origins=*' /etc/neko/supervisord/chromium.conf; \
    grep -Fq -- "--touch-events=enabled" /etc/neko/supervisord/chromium.conf || \
        sed -i '/--no-sandbox/i\  --touch-events=enabled' /etc/neko/supervisord/chromium.conf; \
    sed -i 's/implicit_hosting: false/implicit_hosting: true/' /etc/neko/neko.yaml; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends socat; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# CDP socat-proxy: 0.0.0.0:9224 → 127.0.0.1:9223 (где Chromium слушает CDP).
COPY supervisord/cdp-proxy.conf /etc/neko/supervisord/cdp-proxy.conf

# Подменяем legacy m1k1o-frontend на собранный demodesk-bundle.
# Bundle поддерживает native touch protocol (опкоды 0x08-0x0a) и содержит
# наши патчи: auto-login через ?usr=&pwd=, embed/cast modes, floating
# keyboard-кнопку (DOM-button = user-gesture для iOS WKWebView).
RUN rm -rf /var/www/* && chown -R neko:neko /var/www
COPY --from=frontend-builder --chown=neko:neko /build/dist/ /var/www/

# USER оставляем root — апстрим m1k1o/neko/chromium тоже стартует supervisord
# от root, чтобы он мог дропать привилегии в `user=neko` директивах
# supervisord-программ. Иначе supervisord падает с
# "Error: Can't drop privilege as nonroot user".
