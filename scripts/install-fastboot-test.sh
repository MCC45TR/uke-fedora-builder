#!/usr/bin/bash
# Host-only installer for the independently audited initial B-slot test ZIP.
set -Eeuo pipefail
umask 077
export LC_ALL=C
language=${LANG:-en}
say() { if [[ $language == tr* ]]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
fail() { say "$1" "$2" >&2; exit 1; }
stage() { printf '\n[%s/5] ' "$1"; say "$2" "$3"; }
usage() {
    printf 'Usage: %s --check|--install ARCHIVE [--fastboot EXECUTABLE]\n' "${0##*/}"
}
[[ $# -ge 2 ]] || { usage >&2; exit 2; }
action=$1
case $action in --check|--install) :;; *) usage >&2; exit 2;; esac
[[ -f $2 && ! -L $2 ]] || fail 'The installation ZIP was not found.' 'Kurulum ZIP dosyası bulunamadı.'
archive=$(realpath -e "$2")
shift 2
client=$(dirname "$archive")/fastboot
if [[ $# == 2 && $1 == --fastboot ]]; then client=$(realpath -e "$2"); shift 2; fi
[[ $# == 0 ]] || { usage >&2; exit 2; }
[[ -f $archive && ! -L $archive && -x $client && -f $client && ! -L $client ]] ||
    fail 'The ZIP or adjacent qualified fastboot executable is missing.' 'ZIP veya yanındaki doğrulanmış fastboot çalıştırıcısı bulunamadı.'
for tool in jq sha256sum unzip timeout flock awk sed df; do command -v "$tool" >/dev/null ||
    fail "Required host tool is missing: $tool" "Gerekli bilgisayar aracı eksik: $tool"; done
lock=$(dirname "$archive")/.uke-install.lock
[[ ! -L $lock && ( ! -e $lock || -f $lock ) ]] || exit 1
exec 9>"$lock"
flock -n 9 || fail 'Another installation is running from this directory.' 'Bu klasörden başka bir kurulum çalışıyor.'
work=$(mktemp -d "$(dirname "$archive")/.uke-install.XXXXXXXX")
started=$(date +%s)
cleanup() { find "$work" -depth -delete; }
trap cleanup EXIT
stage 1 'Checking the complete installation ZIP' 'Kurulum ZIP dosyasının tamamı doğrulanıyor'
expected=89ba8ad9d791971ffe1ad0ac5ccaea356a4e66dda7a0486a28fb0898fe1825d2
actual=$(sha256sum "$archive" | cut -d ' ' -f1)
[[ $actual == "$expected" ]] || fail 'This is not the qualified test ZIP; no device was changed.' 'Bu dosya doğrulanmış test ZIP dosyasıyla eşleşmiyor; cihaza işlem yapılmadı.'
unzip -p "$archive" manifest.json > "$work/manifest.json"
jq -e '.artifact_kind=="ext4-singleboot-fastboot-test" and .destinations==["boot_b","userdata"] and
    .required_current_slot=="b" and .root_raw_bytes==8589934592 and
    .kernel_release=="7.3.3-28-unstable" and (.full_singleboot_goal_complete|not)' "$work/manifest.json" >/dev/null || exit 1
available=$(df -B1 --output=avail "$work" | tail -n1)
((available >= 10737418240)) || fail 'Keep at least 10 GiB free beside the ZIP for extraction and reserve.' 'ZIP dosyasının bulunduğu diskte açma ve pay için en az 10 GiB boş alan gerekli.'
say 'ZIP checksum and test scope verified.' 'ZIP özeti ve test kapsamı doğrulandı.'
qualification=$(dirname "$archive")/receipts/host-fastboot-qualification.json
client_checksums=$(dirname "$archive")/receipts/host-fastboot-SHA256SUMS
[[ -f $qualification && ! -L $qualification && -f $client_checksums && ! -L $client_checksums ]] ||
    fail 'The compatible fastboot verification files are missing beside this ZIP.' 'Bu ZIP için uyumlu fastboot aracının doğrulama dosyaları eksik.'
jq -e '.partition_size_response_whitespace_normalized and .padded_wrong_capacity_and_malformed_values_refused' "$qualification" >/dev/null ||
    fail 'This fastboot client has not passed the required response-format tests.' 'Bu fastboot aracı gerekli yanıt biçimi testlerini geçmemiş.'
read -r expected_client client_name < "$client_checksums"
[[ $expected_client =~ ^[a-f0-9]{64}$ && $client_name == fastboot && $(sha256sum "$client" | cut -d ' ' -f1) == "$expected_client" ]] ||
    fail 'Use the verified fastboot supplied next to the ZIP.' 'ZIP dosyasının yanında verilen doğrulanmış fastboot aracını kullanın.'
stage 2 'Checking the connected tablet and all ten partition capacities' 'Bağlı tablet ve on bölümün kapasitesi denetleniyor'
mapfile -t devices < <(timeout 8s "$client" devices | awk '$2=="fastboot"{print $1}')
[[ ${#devices[@]} == 1 ]] || fail 'Connect exactly one tablet in bootloader fastboot mode.' 'Bootloader fastboot modunda tam bir tablet bağlı olmalı.'
device=${devices[0]}
getvar() {
    local name=$1
    timeout 8s "$client" -s "$device" getvar "$name" > "$work/getvar.log" 2>&1 || return
    mapfile -t response < <(sed -n "s/^$name:[[:space:]]*//p" "$work/getvar.log" | sed 's/[[:space:]]*$//')
    [[ ${#response[@]} == 1 ]] || return 1
    value=${response[0]}
}
for pair in product=uke is-userspace=no slot-count=2 current-slot=b; do
    name=${pair%=*} expected_value=${pair#*=}
    getvar "$name" || fail "Cannot read device property: $name" "Cihaz bilgisi okunamadı: $name"
    [[ $value == "$expected_value" ]] || fail "Incompatible $name; stop before flashing." "$name uyumsuz; yazmaya başlamadan durduruldu."
done
for item in boot_a:100663296 boot_b:100663296 dtbo_a:25165824 dtbo_b:25165824 vendor_boot_a:100663296 vendor_boot_b:100663296 vbmeta_a:131072 vbmeta_b:131072 super:11274289152 userdata:497535680512; do
    name=${item%:*} expected_bytes=${item#*:}
    getvar "partition-size:$name" || fail "Cannot read capacity: $name" "Bölüm kapasitesi okunamadı: $name"
    [[ $value =~ ^0[xX][0-9a-fA-F]{1,11}$ ]] || fail "Malformed capacity: $name" "Bölüm kapasitesi geçersiz biçimde: $name"
    hex=${value#0[xX]}
    bytes=$((16#$hex))
    [[ $bytes == "$expected_bytes" ]] || fail "Unexpected capacity: $name; no device was changed." "$name boyutu beklenenle eşleşmiyor; cihaza işlem yapılmadı."
    printf '  %-14s %12s KiB  OK\n' "$name" "$((bytes / 1024))"
done
say 'Measured 512-GB Uke, slot B: all preflight checks passed.' 'Ölçülmüş 512 GB Uke, B slotu: bütün ön denetimler geçti.'
if [[ $action == --check ]]; then
    say 'Check only: no download, flash, slot change or reboot was requested.' 'Yalnız denetim: aktarım, yazma, slot değişikliği veya yeniden başlatma istenmedi.'
    exit 0
fi
stage 3 'Writing boot_b and replacing userdata' 'boot_b yazılıyor ve userdata yeniden kuruluyor'
say 'Existing userdata files and accounts will be erased. Other partition images are not written.' 'Mevcut userdata dosyaları ve hesapları silinecek. Diğer bölüm imajları yazılmayacak.'
log=$(dirname "$archive")/install-last.log
[[ ! -L $log && ( ! -e $log || -f $log ) ]] || exit 1
: > "$log"
set +e
# Fastboot extracts the sparse image to a temporary file. Keep that growth on
# the budgeted real filesystem instead of filling a RAM-backed /tmp.
TMPDIR="$work" "$client" -s "$device" update "$archive" 2>&1 | while IFS= read -r line; do
    # Device serials are unnecessary in a support log.
    [[ $line != 'Serial Number'* ]] || continue
    printf '%s\n' "$line" >> "$log"
    # These exact optional probes are expected for this hash-pinned test ZIP.
    # Keep them in the support log; actual failures and other missing files stay
    # visible. The initial image does not claim verified boot qualification.
    case $line in
        "archive does not contain 'super_empty.img'"|"archive does not contain 'boot.sig'"|"archive does not contain 'userdata.sig'") continue;;
    esac
    printf '%s\n' "$line"
    if [[ $line =~ ^Sending[[:space:]]sparse[[:space:]].*[[:space:]]([0-9]+)/([0-9]+)[[:space:]] ]]; then
        current_piece=${BASH_REMATCH[1]} total_pieces=${BASH_REMATCH[2]}
    fi
    if [[ $line == Writing\ \'userdata\'*OKAY* && -n ${current_piece:-} ]]; then
        say "Root image: piece $current_piece/$total_pieces written." "Kök imajı: $current_piece/$total_pieces parça yazıldı."
    fi
    case $line in *Writing*) : > "$work/writing-started";; esac
done
status=${PIPESTATUS[0]}
set -e
if ((status)); then
    say "Installation stopped; fastboot status $status. See install-last.log." "Kurulum durdu; fastboot hata kodu $status. Ayrıntı: install-last.log."
    if grep -q 'requirements not met' "$log"; then
        say 'The ZIP compatibility check refused the response. Use the qualified adjacent client; do not remove requirements or force the flash.' 'ZIP uyumluluk kontrolü yanıtı reddetti. Yanındaki doğrulanmış istemciyi kullanın; denetimleri silmeyin veya yazmayı zorlamayın.'
    elif grep -Eqi 'too large|not enough|no space' "$log"; then
        say 'Image capacity check failed. Keep the tablet in fastboot for diagnosis.' 'İmaj kapasitesi kontrolü başarısız. İnceleme için tableti fastboot modunda bırakın.'
    fi
    if [[ -e $work/writing-started ]]; then
        say 'Writing began. Inspect the log before any reboot or retry.' 'Yazma başladı. Yeniden başlatmadan veya tekrar denemeden önce günlüğü inceleyin.'
    else
        say 'No partition-write stage was reached.' 'Bölüm yazma aşamasına geçilmedi.'
    fi
    exit "$status"
fi
stage 4 'Flash completed; reboot command acknowledged' 'Yazma tamamlandı; yeniden başlatma komutu kabul edildi'
stage 5 'Waiting for the first graphical setup' 'İlk grafik kurulum ekranı bekleniyor'
say 'The flash succeeded. OS boot, full-capacity growth and native health still need verification.' 'Yazma başarılı. Sistemin açılışı, tam kapasiteye büyüme ve native sağlık henüz doğrulanmalı.'
say 'Complete Plasma account/network setup, then run: sudo systemctl enable --now sshd' 'Plasma hesap/ağ kurulumunu tamamlayıp şunu çalıştırın: sudo systemctl enable --now sshd'
printf '\n'
say "Summary: boot_b + userdata written; reboot requested; elapsed $(( $(date +%s) - started )) s." "Özet: boot_b + userdata yazıldı; yeniden başlatma istendi; geçen süre $(( $(date +%s) - started )) sn."
