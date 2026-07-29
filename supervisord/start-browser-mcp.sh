#!/bin/bash
# §AI-control: запуск @playwright/mcp в LAUNCH-режиме (транспорт pipe) — Playwright
# сам поднимает bundled Chromium на X-экране :99. Агент рулит браузером по MCP
# (http://<host>:PORT/mcp). Внешний CDP по порту не используем (Chromium 146 глушит
# page-сессии с -32001; pipe при launch — не глушит).
#
# Размер окна и профиль браузера задаём через --config (launchOptions.args), т.к.
# CLI-флаг --viewport-size ставит только CDP-вьюпорт (эмуляцию), а OS-окно
# остаётся дефолтным (маленьким) → нужен --window-size/--start-maximized.
set -eu

PORT="${PW_MCP_PORT:-9250}"
BROWSERS="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
CONFIG="${PW_MCP_CONFIG:-/tmp/mcp-config.json}"

# bundled Chromium (открытый, НЕ Google Chrome — mcp по умолчанию ищет chrome).
CHROME="$(find "$BROWSERS" -type f -name chrome -path '*chrome-linux*' 2>/dev/null | head -1)"
if [ -z "${CHROME}" ]; then
    echo "start-browser-mcp: bundled chromium not found under $BROWSERS" >&2
    exit 1
fi

# cli @playwright/mcp (установлен глобально npm -g).
MCP_CLI="$(find /usr/lib/node_modules /usr/local/lib/node_modules -path '*@playwright/mcp/cli.js' 2>/dev/null | head -1)"
if [ -z "${MCP_CLI}" ]; then
    echo "start-browser-mcp: @playwright/mcp cli not found" >&2
    exit 1
fi

# Размер экрана из NEKO_SCREEN ("WxH@FPS"), дефолт под телефон.
RES="${NEKO_SCREEN%%@*}"; W="${RES%%x*}"; H="${RES##*x}"
if [ -z "${W}" ] || [ -z "${H}" ] || [ "${W}" = "${H}" ]; then W=832; H=1283; fi

UA="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"

# Конфиг браузера: окно на весь экран (--start-maximized + явный --window-size),
# без песочницы (контейнер), мобильный контекст под экран neko.
cat > "${CONFIG}" <<EOF
{
  "browser": {
    "browserName": "chromium",
    "isolated": false,
    "launchOptions": {
      "executablePath": "${CHROME}",
      "headless": false,
      "chromiumSandbox": false,
      "args": [
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--window-position=0,0",
        "--window-size=${W},${H}",
        "--start-maximized"
      ]
    },
    "contextOptions": {
      "viewport": { "width": ${W}, "height": ${H} },
      "isMobile": true,
      "hasTouch": true,
      "userAgent": "${UA}"
    }
  }
}
EOF

exec node "${MCP_CLI}" \
    --port "${PORT}" \
    --host 0.0.0.0 \
    --allowed-hosts '*' \
    --shared-browser-context \
    --config "${CONFIG}"
