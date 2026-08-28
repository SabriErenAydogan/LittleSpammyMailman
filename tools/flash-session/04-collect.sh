#!/bin/bash
# SALT OKUMA toplama: A/B otomasyonu için gereken her şeyi cihazdan al.
# Hiçbir şey yazmaz.
set -u
PROJ="C:/Users/Eren/selene-kernel-project"
OUT="$PROJ/flash-session/out"
mkdir -p "$OUT"

adb wait-for-device
echo "== cihaz"
echo "   kernel : $(adb shell uname -r | tr -d '\r')"
echo "   slot   : $(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
echo "   pil    : $(adb shell cat /sys/class/power_supply/battery/capacity | tr -d '\r')% $(adb shell cat /sys/class/power_supply/battery/status | tr -d '\r')"
echo "   uptime : $(adb shell uptime | tr -d '\r')"

pull_part() {   # $1=bölüm $2=hedef
  adb shell "su -c 'dd if=/dev/block/by-name/$1 of=/data/local/tmp/$1.read bs=1M'" 2>/dev/null
  adb shell "su -c 'chmod 666 /data/local/tmp/$1.read'"
  adb pull "/data/local/tmp/$1.read" "$2" >/dev/null 2>&1 && echo "   -> $2 ($(stat -c%s "$2") bayt)"
  adb shell "su -c 'rm -f /data/local/tmp/$1.read'"
}

echo "== misc (A/B slot metadata) - yedek + temel durum"
pull_part misc "$OUT/misc-current.bin"

echo "== expdb (#20 testi sonrası - bu veri henüz alınmamıştı)"
pull_part expdb "$OUT/expdb-after20.bin"

echo "== slot B mantıksal bölümleri var mı"
adb shell 'su -c "ls -la /dev/block/mapper/"' 2>/dev/null | sed 's/^/   /'
echo "   -- lpdump --"
adb shell 'su -c "lpdump 2>/dev/null | head -40"' 2>/dev/null | sed 's/^/   /'

echo "== bootctl var mı"
adb shell 'su -c "which bootctl; bootctl get-number-slots; bootctl get-current-slot"' 2>&1 | sed 's/^/   /'

echo "== pstore (silmeden)"
adb shell 'su -c "ls -la /sys/fs/pstore/"' 2>/dev/null | sed 's/^/   /'
exit 0
