#!/bin/bash
# LK'nin `oem rdmem` komutuyla bir bellek bolgesini parca parca cekip birlestirir.
#
# Neden parcali: LK'nin fastboot INFO kanali komut basina ~76 mesajda kopuyor
# (16 KB denemesi "usb_read failed" ile dustu, 4 KB sorunsuz ve 0.023 sn).
# 4 KB'lik parcalar bu sinirin altinda kaliyor.
#
# Neden bu is: kernel boot etmediginde DRAM'deki ramoops/mboot_params tamponlari
# yalnizca cihaz auto-fastboot'ta beklerken el degmemis olur; kurtarma icin
# fastboot'tan 72 MB yazmak onlari eziyor. Bu script yazmadan ONCE okur.
#
# Kullanim (cihaz FASTBOOT'ta):
#   bash 07-fbdump.sh <adres_hex> <uzunluk_hex> <cikti>
#   bash 07-fbdump.sh 4d010000 40000 out/ramoops.txt     # ramoops console
#   bash 07-fbdump.sh 4d0f0000 10000 out/mboot.txt       # AEE RAM console
set -u
ADDR_HEX="${1:?adres gerekli}"; LEN_HEX="${2:?uzunluk gerekli}"; OUT="${3:?cikti gerekli}"
CHUNK=$((0x1000))
addr=$((16#$ADDR_HEX)); len=$((16#$LEN_HEX)); end=$((addr+len))
: > "$OUT"
fail=0; done_b=0
while [ $addr -lt $end ]; do
  n=$CHUNK; [ $((addr+n)) -gt $end ] && n=$((end-addr))
  if ! out=$(timeout 60 fastboot oem rdmem $(printf %x $addr) $(printf %x $n) 2>&1); then
    echo "!! $(printf 0x%x $addr) okunamadi:" >&2
    echo "$out" | tail -2 >&2
    fail=$((fail+1))
    [ $fail -ge 3 ] && { echo "!! ust uste 3 hata, durduruldu" >&2; break; }
  else
    fail=0
    printf '%s\n' "$out" | sed -n 's/^(bootloader) //p' >> "$OUT"
    done_b=$((done_b+n))
  fi
  addr=$((addr+n))
  printf "\r  %d / %d KB" $((done_b/1024)) $((len/1024)) >&2
done
echo >&2
echo "-> $OUT  ($(wc -l < "$OUT") satir, $((done_b/1024)) KB okundu)"
