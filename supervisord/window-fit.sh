#!/bin/bash
# §AI-control: держим окно общего браузера ровно по размеру X-экрана :99.
#
# Клиент при переходе на Viewer читает своё разрешение и через neko REST
# (/api/room/screen) меняет разрешение :99 под телефон (RandR). Окно, которое
# запустил Playwright, само за этим НЕ следует (фиксированный --window-size со
# старта) → по высоте появлялась чёрная полоса. Штатный chromium у neko раньше
# тянулся, т.к. был openbox-maximized; окно Playwright под то правило не попадает
# (другой WM role). Поэтому подгоняем окно сами: раз в секунду сверяем размер
# окна с геометрией экрана и, если разошлись, ресайзим/двигаем в 0,0.
set -u

D=:99.0
NAME='Google Chrome for Testing'   # заголовок окна контента всегда оканчивается так

while true; do
    set -- $(DISPLAY=$D xdotool getdisplaygeometry 2>/dev/null)
    W="${1:-}"; H="${2:-}"
    WID="$(DISPLAY=$D xdotool search --name "$NAME" 2>/dev/null | tail -1)"
    if [ -n "$W" ] && [ -n "$H" ] && [ -n "$WID" ]; then
        WIDTH=0; HEIGHT=0
        eval "$(DISPLAY=$D xdotool getwindowgeometry --shell "$WID" 2>/dev/null)"
        if [ "${WIDTH:-0}" != "$W" ] || [ "${HEIGHT:-0}" != "$H" ]; then
            DISPLAY=$D xdotool windowmove "$WID" 0 0 2>/dev/null || true
            DISPLAY=$D xdotool windowsize "$WID" "$W" "$H" 2>/dev/null || true
        fi
    fi
    sleep 1
done
