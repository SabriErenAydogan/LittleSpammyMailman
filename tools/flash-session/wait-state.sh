#!/bin/bash
# Cihaz hangi duruma geliyor: adb (boot etti) mi, fastboot (bootloop + Ses Kısma) mı?
# Sınırlı süre bekler, sonra ne gördüyse söyler.
export MSYS_NO_PATHCONV=1
LIMIT="${1:-24}"      # 24 x 5sn = 2 dk
for i in $(seq 1 "$LIMIT"); do
  if adb devices 2>/dev/null | grep -q "device$"; then
    echo "ADB GELDİ (t=$((i*5))sn)"
    adb shell 'uname -r; getprop sys.boot_completed' 2>/dev/null
    exit 0
  fi
  if fastboot devices 2>/dev/null | grep -qi fastboot; then
    echo "FASTBOOT (t=$((i*5))sn)"
    exit 0
  fi
  sleep 5
done
echo "2 dk içinde ne adb ne fastboot - cihaz muhtemelen loop'ta ya da siyah ekranda"
exit 1
