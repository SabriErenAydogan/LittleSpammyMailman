#!/bin/bash
# ADIM 1 — flaş ÖNCESİ durum tespiti ve yazma (Android içinden, KSU root ile)
#
# Neden fastboot değil: #18 boot etmezse fastboot'tan boot_a'yı GERİ OKUYAMAYIZ.
# Android içinden dd ile yazıp, REBOOT ETMEDEN önce geri okursak yazmanın
# gerçekten oturduğunu kanıtlayabiliriz. Bu, testin geçerliliğini garanti eden
# tek adım - aylardır eksik olan kontrol buydu.
#
# Kullanım (Windows'ta, bu dizinde):
#   bash 01-preflash.sh
set -e

PROJ="C:/Users/Eren/selene-kernel-project"
# 1. argüman: flaşlanacak boot imajı (varsayılan #18).
#   #13 pozitif kontrol:  bash 01-preflash.sh "$PROJ/scratchpad/fbtest/flash-test-FIXED.img"
IMG="${1:-$PROJ/scratchpad/fbtest/new-boot-allfixes.img}"
DTBO="$PROJ/device-backup/twrp-partitions/dtbo_a.img" # STOK dtbo (eşleşen tek overlay)
[ -f "$IMG" ] || { echo "imaj yok: $IMG"; exit 1; }
echo "== flaşlanacak: $(basename "$IMG")"
OUT="$PROJ/flash-session/out"
mkdir -p "$OUT"

echo "== cihaz kontrolü"
adb wait-for-device
adb shell 'su -c id' | grep -q 'uid=0' || { echo "ROOT YOK - KSU su izni ver"; exit 1; }
echo "   kernel: $(adb shell uname -r)"
echo "   slot:   $(adb shell getprop ro.boot.slot_suffix)"

echo "== flaş öncesi expdb anlık görüntüsü"
adb shell 'su -c "dd if=/dev/block/by-name/expdb of=/data/local/tmp/expdb_pre.bin bs=1M"' 2>/dev/null
adb shell 'su -c "chmod 666 /data/local/tmp/expdb_pre.bin"'
adb pull /data/local/tmp/expdb_pre.bin "$OUT/expdb_pre.bin" >/dev/null
echo "   -> $OUT/expdb_pre.bin ($(stat -c%s "$OUT/expdb_pre.bin") bayt)"

echo "== pstore temizliği (yoksa bölge yeniden kullanılmaz)"
adb shell 'su -c "rm -f /sys/fs/pstore/*"'
adb shell 'su -c "ls /sys/fs/pstore/"' | sed 's/^/   kalan: /'

echo "== imajları cihaza aktar"
adb push "$IMG"  /data/local/tmp/test-boot.img  >/dev/null
adb push "$DTBO" /data/local/tmp/test-dtbo.img  >/dev/null
echo "   yerel  boot md5: $(md5sum "$IMG"  | cut -d' ' -f1)"
echo "   yerel  dtbo md5: $(md5sum "$DTBO" | cut -d' ' -f1)"

echo "== yaz (boot_a + dtbo_a)"
adb shell 'su -c "dd if=/data/local/tmp/test-boot.img of=/dev/block/by-name/boot_a bs=1M"'
adb shell 'su -c "dd if=/data/local/tmp/test-dtbo.img of=/dev/block/by-name/dtbo_a bs=1M"'
adb shell 'su -c sync'

echo "== GERİ OKU ve DOĞRULA  <-- belirleyici adım"
# İkili veriyi `adb shell` borusundan GEÇİRME: Windows'ta satır sonu çevirisi
# bozar. Cihazda dosyaya yaz, `adb pull` ile çek. (00-readonly-check.sh ile
# doğrulandı: bu yolla okunan boot_a, yerel imajla birebir aynı md5 veriyor.)
pull_part() {   # $1=partition  $2=hedef dosya
  adb shell "su -c 'dd if=/dev/block/by-name/$1 of=/data/local/tmp/$1.read bs=1M'" 2>/dev/null
  adb shell "su -c 'chmod 666 /data/local/tmp/$1.read'"
  adb pull "/data/local/tmp/$1.read" "$2" >/dev/null
  adb shell "su -c 'rm -f /data/local/tmp/$1.read'"
}
pull_part boot_a "$OUT/boot_a_readback.img"
pull_part dtbo_a "$OUT/dtbo_a_readback.img"

echo "   okunan boot md5: $(md5sum "$OUT/boot_a_readback.img" | cut -d' ' -f1)"
echo "   okunan dtbo md5: $(md5sum "$OUT/dtbo_a_readback.img" | cut -d' ' -f1)"
echo
if [ "$(md5sum "$IMG" | cut -d' ' -f1)" = "$(md5sum "$OUT/boot_a_readback.img" | cut -d' ' -f1)" ]; then
  echo "*** YAZMA DOĞRULANDI — reboot edebilirsin. Sonuç ne olursa olsun anlamlı olacak."
else
  echo "*** YAZMA EŞLEŞMİYOR — reboot ETME. Bütün #18 hikâyesi bu yüzden olabilir."
fi
