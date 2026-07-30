# syntax=docker/dockerfile:1.7
#
# devolution-neko — Neko v3 server (m1k1o/neko/chromium:latest) с встроенным
# demodesk-frontend bundle (поддержка native touch) и runtime-патчами в build-time.
# Снимает зависимость от ручного деплоя bundle на VPS — образ полностью
# самодостаточен. iOS-приложение делает только `docker run` без последующих
# sed/apt-get/cp шагов.
#
# §AI-control (2026-07): общий браузер теперь поднимает control-plane
# @playwright/mcp (launch/pipe) — агент Claude рулит им по MCP, пользователь
# смотрит тот же X-экран по WebRTC. Штатный запуск Chromium у neko отключён,
# CDP-proxy убран (внешний CDP по порту Chromium 146 глушит с -32001).

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

# Patch neko.yaml.
#   implicit_hosting: true → первый клиент авто-получает host без UI-кнопки
#     (с cast=1 в URL UI Neko-фронта скрыт, кнопки взять-host нет).
RUN set -eux; \
    sed -i 's/implicit_hosting: false/implicit_hosting: true/' /etc/neko/neko.yaml

# --- §AI-control: Node + @playwright/mcp + bundled Chromium ---------------
# Node.js 20 (nodesource) — рантайм control-plane @playwright/mcp.
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg; \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; \
    apt-get install -y -qq --no-install-recommends nodejs; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    node --version; npm --version

# @playwright/mcp (пин версии — воспроизводимость) + bundled Chromium (открытый,
# НЕ Google Chrome). Chromium-зависимости уже есть в neko/chromium base.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN set -eux; \
    npm install -g @playwright/mcp@0.0.78 @modelcontextprotocol/sdk; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    CORE_CLI="$(find /usr/lib/node_modules /usr/local/lib/node_modules -path '*/playwright-core/cli.js' 2>/dev/null | head -1)"; \
    test -n "${CORE_CLI}"; \
    echo "playwright-core cli: ${CORE_CLI}"; \
    node "${CORE_CLI}" install chromium; \
    chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}"; \
    find "${PLAYWRIGHT_BROWSERS_PATH}" -type f -name chrome -path '*chrome-linux*' | head -1

# Control-plane скрипты.
COPY supervisord/start-browser-mcp.sh  /usr/local/bin/start-browser-mcp.sh
COPY supervisord/browser-keeper.cjs    /usr/local/bin/browser-keeper.cjs
COPY supervisord/window-fit.sh         /usr/local/bin/window-fit.sh
COPY supervisord/browser-watchdog.sh   /usr/local/bin/browser-watchdog.sh
RUN chmod +x /usr/local/bin/start-browser-mcp.sh /usr/local/bin/window-fit.sh \
             /usr/local/bin/browser-watchdog.sh

# supervisord: chromium.conf ПЕРЕОПРЕДЕЛяет апстрим (отключает штатный Chromium,
# оставляет openbox); browser-mcp.conf поднимает control-plane; browser-keeper.conf
# держит один общий браузер открытым (персистентная MCP-сессия); window-fit.conf
# подгоняет окно браузера под размер экрана (динамический RandR-ресайз от клиента).
COPY supervisord/chromium.conf        /etc/neko/supervisord/chromium.conf
COPY supervisord/browser-mcp.conf     /etc/neko/supervisord/browser-mcp.conf
COPY supervisord/browser-keeper.conf  /etc/neko/supervisord/browser-keeper.conf
COPY supervisord/window-fit.conf      /etc/neko/supervisord/window-fit.conf
COPY supervisord/browser-watchdog.conf /etc/neko/supervisord/browser-watchdog.conf

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
