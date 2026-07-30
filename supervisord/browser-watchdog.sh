#!/bin/bash
# §AI-control: сторож общего браузера.
#
# Если ГЛАВНЫЙ процесс браузера пропал (краш/OOM) или mcp-плейн завис в сломанном
# состоянии ("Cannot read properties of undefined (reading 'once')") — «мягкий»
# рестарт mcp/keeper этот стек НЕ оживляет (остаётся зомби-подпроцесс + Singleton-
# lock + сломанный mcp). Надёжно лечит только чистый boot контейнера. Поэтому:
# нет главного процесса браузера дольше MISS_LIMIT (при живом контейнере, вне
# boot-грейса) → выходим из PID 1 → docker поднимает контейнер заново
# (--restart unless-stopped) → mcp+keeper+браузер стартуют с нуля.
#
# Детект по процессу (а не по X-окну): работает от root без X-authority. Главный
# процесс браузера — chrome без "--type=" (подпроцессы/сам mcp пропускаем).
set -u

GRACE_BOOT="${WATCHDOG_GRACE:-75}"   # не трогать первые N секунд (нормальный boot)
MISS_LIMIT="${WATCHDOG_MISS:-45}"    # нет браузера столько секунд подряд → рестарт
STEP=5

start=$(date +%s)
miss=0

has_browser() {
    for p in $(pgrep -f "chrome-linux64/chrome" 2>/dev/null); do
        cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
        case "$cmd" in
            *"--type="*|*cli.js*) : ;;   # рендереры/gpu/zygote/сам mcp — не в счёт
            *chrome*) return 0 ;;         # главный процесс браузера жив
        esac
    done
    return 1
}

while true; do
    sleep "$STEP"
    now=$(date +%s)
    [ $((now - start)) -lt "$GRACE_BOOT" ] && continue   # грейс на нормальный boot
    if has_browser; then
        miss=0
    else
        miss=$((miss + STEP))
        echo "browser-watchdog: главный процесс браузера отсутствует ${miss}с"
        if [ "$miss" -ge "$MISS_LIMIT" ]; then
            echo "browser-watchdog: браузер мёртв > ${MISS_LIMIT}с → РЕСТАРТ контейнера (чистый boot)"
            supervisorctl shutdown 2>/dev/null || true   # мягко: остановить supervisord
            sleep 10
            kill -9 1 2>/dev/null || true                # жёстко: убить PID 1 → контейнер выходит
            sleep 30                                     # docker поднимает заново
            start=$(date +%s); miss=0                    # новый грейс после рестарта
        fi
    fi
done
