#!/bin/bash
# Wrapper для запуска Chromium с явным --window-size, посчитанным из
# NEKO_SCREEN env-переменной. Без этого openbox+chromium на холодном старте
# часто отрисовывают окно 10x10 в углу: --start-maximized игнорируется (баг
# взаимодействия chromium 146 + openbox в условиях минимального WM).
# Симптом — чёрный canvas в Browser-вкладке, видна только небольшая
# chromium-форточка в верхнем левом углу.
set -e

# NEKO_SCREEN формат: "WIDTHxHEIGHT@FPS" (например "780x1454@30").
RES="${NEKO_SCREEN%%@*}"
WIDTH="${RES%%x*}"
HEIGHT="${RES##*x}"

# Sanity: если env пустой/мусор — fallback на разумный default чтобы
# chromium хотя бы открылся в видимом размере, а не упал с ошибкой парсинга.
if [ -z "${WIDTH}" ] || [ -z "${HEIGHT}" ] || [ "${WIDTH}" = "${HEIGHT}" ]; then
    WIDTH=1280
    HEIGHT=2560
fi

exec /usr/bin/chromium \
    --remote-debugging-port=9223 \
    --remote-debugging-address=0.0.0.0 \
    --remote-allow-origins=* \
    --touch-events=enabled \
    --no-sandbox \
    --window-position=0,0 \
    --window-size="${WIDTH},${HEIGHT}" \
    --display="${DISPLAY}" \
    --user-data-dir=/home/neko/.config/chromium \
    --no-first-run \
    --start-maximized \
    --start-fullscreen \
    --bwsi \
    --force-dark-mode \
    --disable-file-system \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-dev-shm-usage
