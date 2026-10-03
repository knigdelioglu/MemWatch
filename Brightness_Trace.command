#!/bin/bash
# MemWatch otomatik parlaklık teşhis kaydı (HDR KAPALIYKEN çalıştırın)
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT_DIR/brightness_trace.log"
M1DDC="$(command -v m1ddc || ls /opt/homebrew/bin/m1ddc /usr/local/bin/m1ddc 2>/dev/null | head -1)"
APP="${MEMWATCH_APP:-/Applications/MemWatch.app}"
{
  echo "=== $(date) ==="
  sw_vers; echo
  echo "m1ddc: $M1DDC"
  if [[ -n "$M1DDC" ]]; then
    "$M1DDC" display list detailed; echo
    for sel in 1 2; do
      echo "--- display $sel get luminance:"; "$M1DDC" display $sel get luminance
      echo "--- display $sel max luminance:"; "$M1DDC" display $sel max luminance
    done
  fi
  echo; echo "=== system_profiler (displays) ==="
  system_profiler SPDisplaysDataType 2>/dev/null | sed -n '1,60p'
  echo; echo "=== MemWatch runtime trace (75 sn) ==="
} > "$LOG" 2>&1

pkill -x MemWatch 2>/dev/null; sleep 1
MEMWATCH_DISPLAY_RUNTIME_TRACE=1 "$APP/Contents/MacOS/MemWatch" >> "$LOG" 2>&1 &
PID=$!
echo "Kayıt alınıyor (75 sn)... Bu sürede ortam ışığını değiştirmeyi deneyin (lamba aç/kapa, sensörü elinizle kapatın)."
sleep 75
kill $PID 2>/dev/null; sleep 1
open "$APP"
echo "Bitti: $LOG"
