#!/usr/bin/bash
# Host-only delivery of the full test archive through the existing measured preparer.
set -Eeuo pipefail
umask 077
language=${LANG:-en}
export LC_ALL=C
say(){ if [[ $language == tr* ]];then printf '%s\n' "$2";else printf '%s\n' "$1";fi; }
fail(){ say "$1" "$2" >&2;exit 1; }
stage(){ printf '\n[%s/5] ' "$1";say "$2" "$3"; }
usage(){ printf 'Usage: %s --check|--install ARCHIVE [--fastboot EXECUTABLE]\n' "${0##*/}"; }
[[ $# -ge 2 ]] || { usage >&2;exit 2; }
action=$1
case $action in --check|--install) :;;*) usage >&2;exit 2;;esac
[[ -f $2 && ! -L $2 ]] || fail 'Installation ZIP missing.' 'Kurulum ZIP dosyası bulunamadı.'
archive=$(realpath -e "$2")
shift 2
client=${archive%/*}/fastboot
if [[ $# == 2 && $1 == --fastboot ]];then client=$(realpath -e "$2");shift 2;fi
[[ $# == 0 ]] || { usage >&2;exit 2; }
here=$(cd -- "$(dirname -- "$0")" && pwd)
[[ -f $here/prepare-fastboot-update.sh && ! -L $here/prepare-fastboot-update.sh &&
   -f $client && -x $client && ! -L $client ]] || fail 'Measured preparer or qualified fastboot missing.' 'Ölçümlü hazırlayıcı veya doğrulanmış fastboot eksik.'
for tool in jq sha256sum unzip timeout flock awk df;do
 command -v "$tool" >/dev/null || fail "Required host tool missing: $tool" "Gerekli bilgisayar aracı eksik: $tool"
done
lock=${archive%/*}/.uke-install.lock
[[ ! -L $lock && ( ! -e $lock || -f $lock ) ]] || exit 1
exec 9>"$lock"
flock -n 9 || fail 'Another installation is active in this directory.' 'Bu klasörde başka bir kurulum çalışıyor.'
work=$(mktemp -d "${archive%/*}/.uke-full-install.XXXXXXXX")
trap 'find "$work" -depth -delete' EXIT
stage 1 'Checking the installation archive receipt' 'Kurulum arşivinin özeti denetleniyor'
receipt=$archive.sha256
[[ -f $receipt && ! -L $receipt && $(stat -c %s "$receipt") -le 4096 && $(wc -l < "$receipt") == 1 ]] ||
 fail 'The adjacent ZIP checksum receipt is missing or malformed.' 'ZIP yanındaki özet dosyası eksik veya geçersiz.'
read -r expected recorded_name < "$receipt"
[[ $expected =~ ^[a-f0-9]{64}$ && -n $recorded_name &&
   $(sha256sum "$archive" | cut -d' ' -f1) == "$expected" ]] ||
 fail 'ZIP checksum differs; no device write was requested.' 'ZIP özeti eşleşmiyor; cihaza yazma istenmedi.'
bytes=$(stat -c %s "$archive")
available=$(df -B1 --output=avail "$work" | tail -n1)
((available>=bytes*2+9663676416)) ||
 fail 'Keep space for two archive copies, an 8-GiB extraction and a 1-GiB reserve.' 'İki arşiv kopyası, 8 GiB açma alanı ve 1 GiB boş pay için yer gerekli.'
stage 2 'Checking payloads and measuring all eight destinations' 'İmajlar doğrulanıyor ve sekiz hedefin kapasitesi ölçülüyor'
mapfile -t devices < <(timeout --kill-after=2s 10s "$client" devices | awk '$2=="fastboot"{print $1}')
[[ ${#devices[@]} == 1 ]] || fail 'Connect exactly one tablet in bootloader fastboot mode.' 'Bootloader fastboot modunda tek tablet bağlayın.'
device=${devices[0]}
if ! bash "$here/prepare-fastboot-update.sh" "$archive" "$work/measured.zip" --fastboot "$client";then
 fail 'Preflight refused; no flash or reboot was requested. Correct the reported input or connection.' 'Ön denetim reddetti; yazma veya yeniden başlatma istenmedi. Bildirilen dosya ya da bağlantı hatasını düzeltin.'
fi
mapfile -t devices < <(timeout --kill-after=2s 10s "$client" devices | awk '$2=="fastboot"{print $1}')
[[ ${#devices[@]} == 1 && ${devices[0]} == "$device" ]] ||
 fail 'The device connection changed during preparation; stopped before writing.' 'Hazırlık sırasında cihaz bağlantısı değişti; yazmadan durduruldu.'
stage 3 'Reviewing the measured installation scope' 'Ölçülen kurulum kapsamı gösteriliyor'
say 'Writes super, userdata, both DTBO, both vendor_boot and both boot slots. Existing userdata files and accounts are replaced. GPT sizes are preserved.' 'super, userdata, iki DTBO, iki vendor_boot ve iki boot slotu yazılır. Mevcut userdata dosyaları ve hesapları değiştirilir. GPT boyutları korunur.'
say 'Rescue RAM-boot input is included. Secure Boot, encrypted storage and hibernation remain separate qualification work.' 'Rescue RAM açılış girdisi bulunur. Secure Boot, şifreli depolama ve hazırda bekletme doğrulamaları ayrı çalışmalardır.'
if [[ $action == --check ]];then
 say 'Check passed. No flash, slot selection or reboot was requested.' 'Denetim geçti. Yazma, slot seçimi veya yeniden başlatma istenmedi.'
 exit 0
fi
stage 4 'Writing the verified images; progress follows' 'Doğrulanan imajlar yazılıyor; ilerleme aşağıda'
log=${archive%/*}/install-full-last.log
[[ ! -L $log && ( ! -e $log || -f $log ) ]] || exit 1
: > "$log"
started=$(date +%s)
set +e
TMPDIR="$work" "$client" -s "$device" --skip-reboot update "$work/measured.zip" 2>&1 |
 while IFS= read -r line;do
  [[ $line != 'Serial Number'* ]] || continue
  printf '%s\n' "$line"
  # Keep the support log bounded even if a failed transport repeats messages.
  if (($(stat -c %s "$log")<262144));then printf '%s\n' "$line" >> "$log";fi
 done
statuses=("${PIPESTATUS[@]}")
set -e
if ((statuses[0]||statuses[1]));then
 say "Installation stopped (fastboot ${statuses[0]}, output ${statuses[1]}). See install-full-last.log. Keep fastboot connected for diagnosis before reboot or retry." "Kurulum durdu (fastboot ${statuses[0]}, çıktı ${statuses[1]}). install-full-last.log dosyasına bakın. Yeniden başlatmadan veya tekrar denemeden önce inceleme için fastboot bağlantısını koruyun."
 if grep -q 'requirements not met' "$log";then
  say 'Compatibility check refused. Keep the guards and use the qualified client.' 'Uyumluluk denetimi reddetti. Denetimleri koruyun ve doğrulanmış istemciyi kullanın.'
 elif grep -Eqi 'too large|not enough|no space' "$log";then
  say 'An image or host extraction does not fit; inspect the named destination and host free space.' 'İmaj veya bilgisayardaki açma işlemi sığmadı; belirtilen hedefi ve bilgisayar boş alanını inceleyin.'
 fi
 exit 1
fi
stage 5 'Flash completed; requesting the first system boot' 'Yazma tamamlandı; ilk sistem açılışı isteniyor'
if ! timeout --kill-after=2s 15s "$client" -s "$device" reboot;then
 fail 'Images were written, but reboot was not acknowledged. Inspect the connection before retrying.' 'İmajlar yazıldı fakat yeniden başlatma onaylanmadı. Tekrar denemeden önce bağlantıyı inceleyin.'
fi
say "Update and reboot acknowledged; elapsed $(( $(date +%s)-started )) s. OS boot, capacity growth, setup USB and native health still require verification." "Güncelleme ve yeniden başlatma onaylandı; geçen süre $(( $(date +%s)-started )) sn. Sistem açılışı, kapasite büyümesi, kurulum USB'si ve native sağlık ayrıca doğrulanmalı."
