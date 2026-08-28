#!/bin/bash
# LK (bootloader) logunu cihazdan zorla al.
#
# Boot etmeyen bir kernel icin tek tanik budur: kernel kendi konsolunu acmadan
# olurse ramoops bos kalir, ama LK her seferinde sonuna kadar kosar ve MTK'nin
# DRAM log-store'u onun logunu `expdb`ye yazar. expdb flash'ta oldugu icin
# soguk kesmeden de etkilenmez.
#
# Kullanim (cihaz Android'de ve rootlu olmali):
#   bash 06-lklog.sh <etiket>
set -u
PROJ="C:/Users/Eren/selene-kernel-project"
OUT="$PROJ/flash-session/out"
TAG="${1:-test}"
mkdir -p "$OUT"
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 PYTHONUTF8=1

echo "== cihaz bekleniyor"
adb wait-for-device
adb shell 'su -c id' | grep -q 'uid=0' || { echo "ROOT YOK"; exit 1; }

echo "== expdb dokuluyor"
adb shell 'su -c "dd if=/dev/block/by-name/expdb of=/data/local/tmp/e.bin bs=1M"' 2>/dev/null
adb shell 'su -c "chmod 666 /data/local/tmp/e.bin"'
adb pull /data/local/tmp/e.bin "$OUT/expdb-$TAG.bin" >/dev/null || exit 1
adb shell 'su -c "rm -f /data/local/tmp/e.bin"'
echo "   -> $OUT/expdb-$TAG.bin"

echo "== LK logu cikariliyor"
python "$PROJ/sandbox/lklog.py" "$OUT/expdb-$TAG.bin" -o "$OUT/lk_logged-$TAG.txt" || exit 1

echo "== ozet"
echo "   reset kaynaklari (RGU):"
grep -ao "rst from: [a-z?]*" "$OUT/lk_logged-$TAG.txt" | sort | uniq -c | sed 's/^/      /'
echo "   auto-fastboot sayaci:"
grep -ao "\[autofb\][^\"]\{0,40\}" "$OUT/lk_logged-$TAG.txt" | sort -u | sed 's/^/      /' | head -8
exit 0
