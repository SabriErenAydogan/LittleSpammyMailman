#!/bin/bash
# LK'nin oem ramoops / rrlog / sram komutlarıyla bir bölgenin TAMAMINI toplar.
#
# Neden döngü: LK'nin fastboot INFO kanalı komut başına ~76 mesajda kopuyor.
# Eski sürüm ramoops'un 256 KB'ını tek komutta dökmeye çalışıyordu (~1170
# satır) — başlığı basıp orada ölüyordu. Yamalı LK artık her çağrıda en
# fazla 64 satır basıyor ve kaç BAYT tükettiğini "used=0x..." ile bildiriyor.
# Burada offset'i "used" kadar ilerletip bölgeyi parça parça topluyoruz.
#
# Kullanım:
#   bash 08-lkdump.sh ramoops            -> out/lk-ramoops-<zaman>.txt
#   bash 08-lkdump.sh rrlog
#   bash 08-lkdump.sh sram
set -u

REGION="${1:-ramoops}"
case "$REGION" in
  ramoops|rrlog|sram) ;;
  *) echo "bölge: ramoops | rrlog | sram"; exit 1 ;;
esac

OUT="$(cd "$(dirname "$0")" && pwd)/out"
mkdir -p "$OUT"
DEST="$OUT/lk-$REGION-$(date +%Y%m%d-%H%M%S).txt"

fastboot devices | grep -q . || { echo "cihaz fastboot'ta değil"; exit 1; }

off=0
size=0
total=0
stall=0

: > "$DEST"
while : ; do
  if ! raw=$(timeout 60 fastboot oem "$REGION" "$(printf %x $off)" 2>&1); then
    echo "!! komut başarısız (off=0x$(printf %x $off)) — yarıda kesildi"
    echo "$raw" | tail -3
    break
  fi

  # (bootloader) önekini at
  body=$(printf '%s\n' "$raw" | sed -n 's/^(bootloader) //p')

  # başlık alanları
  s=$(printf '%s\n' "$body" | sed -n 's/^size=0x//p' | head -1)
  u=$(printf '%s\n' "$body" | sed -n 's/^used=0x//p' | head -1)
  [ -n "$s" ] && size=$((16#$s))
  if [ -z "$u" ]; then
    echo "!! 'used' alanı gelmedi — LK yamalı sürüm değil olabilir"
    break
  fi
  used=$((16#$u))

  # veri satırları: başlık/kuyruk alanlarını ele
  printf '%s\n' "$body" | grep -vE '^(\[selene\]|size=|off=|used=)' >> "$DEST"

  total=$((total + used))
  off=$((off + used))

  if [ "$used" -eq 0 ]; then
    stall=$((stall + 1))
    [ "$stall" -ge 2 ] && { echo "!! ilerleme durdu (used=0)"; break; }
  else
    stall=0
  fi

  [ "$size" -gt 0 ] && [ "$off" -ge "$size" ] && break
  printf '\r  %s: %d / %d bayt' "$REGION" "$total" "$size"
done
echo

echo "-> $DEST  ($(wc -l < "$DEST") satır, $total bayt)"
