#!/usr/bin/env bash
# Tiny archive fixtures and a read-only host fastboot stub.
set -Eeuo pipefail
export LC_ALL=C
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
mkdir "$work/bin" "$work/input"
export PATH="$work/bin:$PATH" CALLS="$work/calls" FIXTURE=512
cat > "$work/bin/fastboot" <<'FASTBOOT'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $1 == devices ]]; then printf 'mock-uke\tfastboot\n'; exit; fi
[[ $1 == -s && $2 == mock-uke ]]
shift 2
printf '%s\n' "$*" >> "$CALLS"
case $1 in
    getvar)
        case $2 in
            product) value=uke;;
            is-userspace) value=no;;
            unlocked) value=yes;;
            slot-count) value=2;;
            current-slot) value=a; [[ $FIXTURE != 256 ]] || value=b;;
            snapshot-update-status) value=none; [[ $FIXTURE != snapshot ]] || value=merging;;
            partition-size:boot_*|partition-size:vendor_boot_*) value=0x06000000;;
            partition-size:dtbo_*) value=0x01800000;;
            partition-size:vbmeta_*) value=0x00020000;;
            partition-size:super) value=0x00000002A0000000; [[ $FIXTURE != 256 ]] || value=0x0000000220000000;;
            partition-size:userdata)
                case $FIXTURE in
                    256) value=0x37d7700000;;
                    small) value=0x100000000;;
                    invalid) value=0xfffxyz;;
                    *) value=0x00000073d7700000;;
                esac;;
            *) exit 2;;
        esac
        printf '%s:  %s  \r\nFinished.\n' "$2" "$value" >&2;;
    flash) exit 91;;
    reboot) exit 92;;
    *) exit 2;;
esac
FASTBOOT
chmod +x "$work/bin/fastboot"
cd "$work/input"
truncate -s 100663296 boot.img rescue-boot.img
truncate -s 4096 dtbo.img
# These are just the headers needed for the host capacity checks.
printf '\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x00\x10\x00\x00\x00\x00\x10\x00\x01\x00\x00\x00\x00\x00\x00\x00' > super.img
printf '\x3a\xff\x26\xed\x01\x00\x00\x00\x1c\x00\x0c\x00\x00\x10\x00\x00\x00\x00\x20\x00\x01\x00\x00\x00\x00\x00\x00\x00' > userdata.img
for file in boot.img dtbo.img rescue-boot.img super.img userdata.img; do
    stored=$(stat -c %s "$file")
    case $file in
        super.img) expanded=4294967296;;
        userdata.img) expanded=8589934592;;
        *) expanded=$stored;;
    esac
    jq -nc --arg file "$file" --arg hash "$(sha256sum "$file" | cut -d ' ' -f1)" --argjson stored "$stored" --argjson expanded "$expanded" '
        {key:$file,value:{stored_bytes:$stored,expanded_bytes:$expanded,sha256:$hash}}'
done | jq -s '{schema_version:1,artifact_kind:"uke-stable-super-fastboot",device:"uke",kernel_release:"7.4.5-senemos",
    super_layout:{phase:"seed"},images:from_entries}' > manifest.json
touch README.txt SHA256SUMS android-info.txt fastboot-info.txt install-stable-super-fastboot.sh
zip -q -1 "$work/test.zip" ./*
rm -- boot.img rescue-boot.img
for fixture in 256 512; do
    FIXTURE=$fixture bash "$repo/scripts/install-stable-super-fastboot.sh" --check "$work/test.zip" > "$work/result"
    grep -Fxq 'Compatibility and payload checks passed.' "$work/result"
done
for fixture in small invalid snapshot; do
    if FIXTURE=$fixture bash "$repo/scripts/install-stable-super-fastboot.sh" --install "$work/test.zip" > "$work/result" 2>&1; then
        printf 'Unexpected acceptance of %s\n' "$fixture" >&2
        exit 1
    fi
done
if grep -Eq '^(flash|reboot)' "$CALLS"; then
    printf 'Preflight tried to mutate a fixture\n' >&2
    exit 1
fi
printf 'Stable fastboot preflight passed capacity and write-refusal fixtures.\n'
