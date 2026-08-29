#!/bin/bash
# LK'nin oem ramoops / rrlog / sram komutlarıyla bir bölgenin TAMAMINI toplar.
#
# Neden döngü: LK'nin fastboot INFO kanalı komut başına ~76 mesajda kopuyor.
# Yamalı LK her çağrıda en fazla 64 satır basıyor ve kaç BAYT tükettiğini
# "used=0x..." ile bildiriyor; burada offset'i o kadar ilerletiyoruz.
#
# İki mod:
#   text (varsayılan) — okunabilir, satır başına daha çok bayt. Konsol logu için.
#   hex               — bayt birebir korunur, çıktı .bin olarak çözülür.
#                       ramoops'un ikili kısımları, mboot_params ve rdmem için
#                       tek doğru mod: metin modunda basılamayan her bayt '.'
#                       oluyor ve veri geri dönüşsüz bozuluyor.
#                       (öneri: vrdons, Kernel Builds, 2026-08-29)
#
# Kullanım:
#   bash 08-lkdump.sh ramoops            -> out/lk-ramoops-<zaman>.txt
#   bash 08-lkdump.sh rrlog hex          -> out/lk-rrlog-<zaman>.bin
#   bash 08-lkdump.sh sram hex
set -u

REGION="${1:-ramoops}"
MODE="${2:-text}"
case "$REGION" in
  ramoops|rrlog|sram) ;;
  *) echo "bölge: ramoops | rrlog | sram"; exit 1 ;;
esac
case "$MODE" in
  text|hex) ;;
  *) echo "mod: text | hex"; exit 1 ;;
esac

if [ "$MODE" = "hex" ] && ! command -v xxd >/dev/null 2>&1; then
  echo "xxd bulunamadı — hex modu çözemez"; exit 1
fi

OUT="$(cd "$(dirname "$0")" && pwd)/out"
mkdir -p "$OUT"
STAMP=$(date +%Y%m%d-%H%M%S)
RAWHEX="$OUT/.lk-$REGION-$STAMP.hex"
if [ "$MODE" = "hex" ]; then DEST="$OUT/lk-$REGION-$STAMP.bin"
else                         DEST="$OUT/lk-$REGION-$STAMP.txt"; fi

fastboot devices | grep -q . || { echo "cihaz fastboot'ta değil"; exit 1; }

off=0; size=0; total=0; stall=0
: > "$DEST"; : > "$RAWHEX"

while : ; do
  args="$(printf %x $off) 0"
  [ "$MODE" = "hex" ] && args="$args hex"

  if ! raw=$(timeout 60 fastboot oem "$REGION" $args 2>&1); then
    echo; echo "!! komut başarısız (off=0x$(printf %x $off)) — yarıda kesildi"
    printf '%s\n' "$raw" | tail -3
    break
  fi

  body=$(printf '%s\n' "$raw" | sed -n 's/^(bootloader) //p')

  s=$(printf '%s\n' "$body" | sed -n 's/^size=0x//p' | head -1)
  u=$(printf '%s\n' "$body" | sed -n 's/^used=0x//p' | head -1)
  [ -n "$s" ] && size=$((16#$s))
  if [ -z "$u" ]; then
    echo; echo "!! 'used' alanı gelmedi — LK v0.2+ değil olabilir"; break
  fi
  used=$((16#$u))

  # veri satırları: başlık/kuyruk alanlarını ele
  data=$(printf '%s\n' "$body" | grep -vE '^(\[selene\]|mode=|size=|off=|used=)')
  if [ "$MODE" = "hex" ]; then
    printf '%s\n' "$data" | tr -d ' \r\n' >> "$RAWHEX"
  else
    printf '%s\n' "$data" >> "$DEST"
  fi

  total=$((total + used)); off=$((off + used))

  if [ "$used" -eq 0 ]; then
    stall=$((stall + 1))
    [ "$stall" -ge 2 ] && { echo; echo "!! ilerleme durdu (used=0)"; break; }
  else
    stall=0
  fi

  [ "$size" -gt 0 ] && [ "$off" -ge "$size" ] && break
  printf '\r  %s (%s): %d / %d bayt' "$REGION" "$MODE" "$total" "$size"
done
echo

if [ "$MODE" = "hex" ]; then
  xxd -r -p "$RAWHEX" > "$DEST"
  rm -f "$RAWHEX"
  got=$(stat -c%s "$DEST" 2>/dev/null || echo 0)
  echo "-> $DEST  ($got bayt çözüldü, LK $total bayt bildirdi)"
  [ "$got" != "$total" ] && echo "   UYARI: çözülen boyut bildirilenle uyuşmuyor"
else
  echo "-> $DEST  ($(wc -l < "$DEST") satır, $total bayt)"
fi
