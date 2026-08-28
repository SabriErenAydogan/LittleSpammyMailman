#!/bin/bash
# ADIM 2b — KURTARMA: dieD'ye geri dön (fastboot'tan)
#
# Cihaz fastboot'ta olmalı:  Güç+Ses Kısma  (ya da  adb reboot bootloader)
#   bash 03-recover.sh
#
# NOT: pstore'u SİLME. Kurtarıp boot ettikten sonra 02-postmortem.sh çalıştır.
set -e

PROJ="C:/Users/Eren/selene-kernel-project"
B="$PROJ/device-backup/dieD-a16-gsi-boot/boot_a_dieD.img"
D="$PROJ/device-backup/dieD-a16-gsi-boot/dtbo_a_dieD.img"

echo "== fastboot bekleniyor"
fastboot devices
echo "== dieD boot_a + dtbo_a geri yazılıyor"
fastboot flash boot_a "$B"
fastboot flash dtbo_a "$D"
echo "== yeniden başlat"
fastboot reboot
echo
echo "Açıldıktan sonra:  bash 02-postmortem.sh   (pstore'u SİLMEDEN okur)"
