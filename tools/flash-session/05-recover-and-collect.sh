#!/bin/bash
# Kurtar VE logu hemen al - tek adımda, arada boşluk bırakmadan.
#
# Neden tek script: ramoops konsol bölgesi tek bir halka tampon. Test kernel'inin
# logu ancak kurtarma boot'unun pstore'unda görünür; o boot'tan sonra ÇALIŞAN
# kernel aynı bölgeye yazmaya devam eder ve fazladan her boot içeriği ezer.
# Geçen sefer dieD kurtarma sırasında bir kez panikleyip yeniden başladı, araya
# iki boot girdi ve #17'nin logu kayboldu.
#
# Cihaz FASTBOOT'ta olmalı.  Kullanım:  bash 05-recover-and-collect.sh <etiket>
set -u
PROJ="C:/Users/Eren/selene-kernel-project"
OUT="$PROJ/flash-session/out"
TAG="${1:-test}"
mkdir -p "$OUT"
export MSYS_NO_PATHCONV=1

echo "== fastboot bekleniyor"
fastboot devices || exit 1
echo "== dieD geri yazılıyor"
fastboot flash boot_a "$PROJ/device-backup/dieD-a16-gsi-boot/boot_a_dieD.img"
fastboot flash dtbo_a "$PROJ/device-backup/dieD-a16-gsi-boot/dtbo_a_dieD.img"
fastboot reboot

echo "== adb bekleniyor (boot_completed BEKLENMİYOR - pstore ilk iş)"
adb wait-for-device

echo "== pstore HEMEN çekiliyor"
for f in $(adb shell 'su -c "ls /sys/fs/pstore/ 2>/dev/null"' | tr -d '\r'); do
  adb shell "su -c 'cat /sys/fs/pstore/$f'" > "$OUT/pstore-$TAG-$f.txt" 2>/dev/null
  echo "   -> $OUT/pstore-$TAG-$f.txt ($(stat -c%s "$OUT/pstore-$TAG-$f.txt" 2>/dev/null || echo 0) bayt)"
done

echo "== içerik hangi kernel'e ait"
grep -ahoE "Linux version 4\.[0-9]+\.[0-9]+[^ ]*" "$OUT"/pstore-"$TAG"-*.txt 2>/dev/null | sort -u | head -3
grep -alc "Thermal/TZ/CPUM\] selene: raw=" "$OUT"/pstore-"$TAG"-*.txt 2>/dev/null | sed 's/^/   yama satiri var: /'

echo "== expdb"
adb shell 'su -c "dd if=/dev/block/by-name/expdb of=/data/local/tmp/e.bin bs=1M"' 2>/dev/null
adb shell 'su -c "chmod 666 /data/local/tmp/e.bin"'
adb pull /data/local/tmp/e.bin "$OUT/expdb-$TAG.bin" >/dev/null && echo "   -> $OUT/expdb-$TAG.bin"
adb shell 'su -c "rm -f /data/local/tmp/e.bin"'

# LK logu: boot etmeyen kernel icin tek tanik. Kernel kendi konsolunu acmadan
# olurse ramoops bos kalir; LK ise her seferinde sonuna kadar kosar ve MTK'nin
# DRAM log-store'u onun logunu expdb'ye yazar (flash'ta, soguk kesmeye dayanikli).
echo "== LK logu cikariliyor"
PYTHONIOENCODING=utf-8 PYTHONUTF8=1 python "$PROJ/sandbox/lklog.py"     "$OUT/expdb-$TAG.bin" -o "$OUT/lk_logged-$TAG.txt"
echo "   reset kaynaklari (RGU):"
grep -ao "rst from: [a-z?]*" "$OUT/lk_logged-$TAG.txt" | sort | uniq -c | sed 's/^/      /'
exit 0
