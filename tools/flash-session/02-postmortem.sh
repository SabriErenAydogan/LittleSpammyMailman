#!/bin/bash
# ADIM 3 — test BAŞARISIZSA: dieD'ye dön, sonra kanıtı topla
#
# Sıra önemli: expdb kaydı bir SONRAKİ başarılı boot'ta okunur, o yüzden önce
# kurtar + boot et, sonra dök. pstore'u SİLME - okumadan önce.
#
#   bash 02-postmortem.sh
set -e

PROJ="C:/Users/Eren/selene-kernel-project"
OUT="$PROJ/flash-session/out"
mkdir -p "$OUT"

echo "== cihaz açık ve rootlu olmalı (dieD geri yüklendikten sonra)"
adb wait-for-device
echo "   kernel: $(adb shell uname -r)"

echo "== pstore (SİLMEDEN oku)"
adb shell 'su -c "ls -la /sys/fs/pstore/"' | sed 's/^/   /'
for f in $(adb shell 'su -c "ls /sys/fs/pstore/"' | tr -d '\r'); do
  adb shell "su -c 'cat /sys/fs/pstore/$f'" > "$OUT/pstore-$f.txt" 2>/dev/null || true
  echo "   -> $OUT/pstore-$f.txt ($(stat -c%s "$OUT/pstore-$f.txt" 2>/dev/null || echo 0) bayt)"
done

echo "== flaş sonrası expdb"
adb shell 'su -c "dd if=/dev/block/by-name/expdb of=/data/local/tmp/expdb_post.bin bs=1M"' 2>/dev/null
adb shell 'su -c "chmod 666 /data/local/tmp/expdb_post.bin"'
adb pull /data/local/tmp/expdb_post.bin "$OUT/expdb_post.bin" >/dev/null
echo "   -> $OUT/expdb_post.bin"

echo
echo "== ÇÖZÜMLEME"
echo "-- expdb'de hangi kernel banner'ları var (öncesi vs sonrası):"
python "$PROJ/sandbox/expdb_banner.py" "$OUT/expdb_pre.bin" "$OUT/expdb_post.bin" 2>/dev/null || true
echo "-- watchdog kayıtları (fiq_step 0x47 = kernel panikledi / 0x0 = hiç exception yok):"
python "$PROJ/sandbox/expdb_diff.py" "$OUT/expdb_pre.bin" "$OUT/expdb_post.bin" 2>/dev/null || true
