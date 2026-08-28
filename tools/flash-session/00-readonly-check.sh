#!/bin/bash
# ADIM 0 — SALT OKUMA. Hiçbir şey yazmaz, reboot etmez, telefon kullanılırken güvenli.
#
# Amacı: flaştan ÖNCE okuma/doğrulama yolunun çalıştığını kanıtlamak ve flaş
# öncesi expdb anlık görüntüsünü almak. boot_a'yı okuyup bilinen dieD imajıyla
# md5 karşılaştırırız; tutuyorsa "geri okuma" mekanizmasına güvenebiliriz demektir.
#
# NOT: ikili veriyi `adb shell` borusundan geçirmiyoruz - Windows'ta satır sonu
# çevirisi veriyi bozabilir. Cihazda dosyaya yazıp `adb pull` ile çekiyoruz.
set -e

PROJ="C:/Users/Eren/selene-kernel-project"
OUT="$PROJ/flash-session/out"
mkdir -p "$OUT"

echo "== cihaz"
adb wait-for-device
adb shell 'su -c id' | grep -q 'uid=0' || { echo "ROOT YOK - KSU'da shell'e su izni ver"; exit 1; }
echo "   kernel : $(adb shell uname -r | tr -d '\r')"
echo "   slot   : $(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
echo "   uptime : $(adb shell uptime | tr -d '\r')"

pull_part() {   # $1=partition  $2=hedef dosya
  adb shell "su -c 'dd if=/dev/block/by-name/$1 of=/data/local/tmp/$1.read bs=1M'" 2>/dev/null
  adb shell "su -c 'chmod 666 /data/local/tmp/$1.read'"
  adb pull "/data/local/tmp/$1.read" "$2" >/dev/null
  adb shell "su -c 'rm -f /data/local/tmp/$1.read'"
}

echo "== boot_a / dtbo_a geri okuma testi (salt okuma)"
pull_part boot_a "$OUT/boot_a_now.img"
pull_part dtbo_a "$OUT/dtbo_a_now.img"

BA=$(md5sum "$OUT/boot_a_now.img" | cut -d' ' -f1)
DA=$(md5sum "$OUT/dtbo_a_now.img" | cut -d' ' -f1)
KB=$(md5sum "$PROJ/device-backup/dieD-a16-gsi-boot/boot_a_dieD.img" | cut -d' ' -f1)
KD=$(md5sum "$PROJ/device-backup/dieD-a16-gsi-boot/dtbo_a_dieD.img" | cut -d' ' -f1)

echo "   boot_a  okunan : $BA"
echo "   boot_a  dieD   : $KB   $([ "$BA" = "$KB" ] && echo '<-- EŞLEŞTİ' || echo '<-- FARKLI')"
echo "   dtbo_a  okunan : $DA"
echo "   dtbo_a  dieD   : $KD   $([ "$DA" = "$KD" ] && echo '<-- EŞLEŞTİ' || echo '<-- FARKLI')"

echo "== flaş öncesi expdb anlık görüntüsü (salt okuma)"
adb shell 'su -c "dd if=/dev/block/by-name/expdb of=/data/local/tmp/expdb_pre.bin bs=1M"' 2>/dev/null
adb shell 'su -c "chmod 666 /data/local/tmp/expdb_pre.bin"'
adb pull /data/local/tmp/expdb_pre.bin "$OUT/expdb_pre.bin" >/dev/null
adb shell 'su -c "rm -f /data/local/tmp/expdb_pre.bin"'
echo "   -> $OUT/expdb_pre.bin ($(stat -c%s "$OUT/expdb_pre.bin") bayt)"

echo "== pstore mevcut durumu (SİLMEDEN)"
adb shell 'su -c "ls -la /sys/fs/pstore/"' | sed 's/^/   /'

echo
echo "== expdb içeriği: hangi kernel'ler kayıtlı"
python "$PROJ/sandbox/expdb_banner.py" "$OUT/expdb_pre.bin" 2>/dev/null || true
python "$PROJ/sandbox/expdb_diff.py"   "$OUT/expdb_pre.bin" 2>/dev/null || true
