#!/usr/bin/env bash
# Tiny byte fixtures and a fake GitHub CLI; no image build or publication.
set -Eeuo pipefail
builder=$(cd -- "$(dirname -- "$0")/.." && pwd)
tool=$builder/src/public/release-layout.sh
publisher=$builder/scripts/publish-image-release.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/kde/kernel" "$work/bin"
printf 'identical boot fixture\n' > "$work/kde/boot.img"
printf 'KDE root fixture\n' > "$work/kde/userdata.img"
boot_sha=$(sha256sum "$work/kde/boot.img" | cut -d ' ' -f1)
root_sha=$(sha256sum "$work/kde/userdata.img" | cut -d ' ' -f1)
jq -n --arg boot "$boot_sha" --arg root "$root_sha" '{distribution:"fedora",architecture:"aarch64",fedora_release:"rawhide",release:"rawhide",
 image_built:true,rpm_transaction_validated:true,source_checked:true,mode:"singleboot",partition:"userdata",filesystem:"ext4",desktop:"kde",
 size_mib:8192,root_raw_bytes:8589934592,device_private_data_included:false,credentials_included:false,ssh_enabled:false,automatic_kernel_activation:false,
 kernel_rpm_signature:"verified COPR signature",kernel_rpms_locally_built:false,filesystem_contents_readback:true,filesystem_metadata_readback:true,
 selinux_policy_contexts_verified:true,independent_aosp_decoder_verified:true,sparse_roundtrip_verified:true,
 cohort_validation:{source:"matched-request-and-producer",packages:"matched-producer-rpm-identities",final_filesystem_hashes_verified:true,kernel_modules_config_dt:"matched-producer-payload-bytes",boot_kernel:"extracted-and-matched",root_selector:"matched-fstab"},
 kernel_profile:"normal",kernel_family:"senemos-uke-linux-kernel-mainline",kernel_version:"7.3.1",kernel_release:"7.3.1-115",
 kernel_commit:("a"*40),kernel_source_commit:("a"*40),rpm_dist:".fc46",rpm_version_release:"7.3.1-115",
 kernel_repository:"mcc45tr/uke-linux-unstable",kernel_key_fingerprint:("B"*40),payload_sha256:("c"*64),boot_sha256:$boot,root_sparse_sha256:$root}' > "$work/kde/manifest.json"
for file in FLASHING.txt installed-rpms.tsv kernel/packages.tsv kernel/RPM-SHA256SUMS; do printf 'fixture receipt\n' > "$work/kde/$file"; done
cp -a "$work/kde" "$work/gnome"
printf 'GNOME root fixture\n' > "$work/gnome/userdata.img"
jq --arg sha "$(sha256sum "$work/gnome/userdata.img" | cut -d ' ' -f1)" '.desktop="gnome"|.root_sparse_sha256=$sha' "$work/kde/manifest.json" > "$work/gnome/manifest.json"
reject() { if "$@" > "$work/rejected" 2>&1; then echo "Invalid release accepted: $*" >&2; exit 1; fi; }
names=$(bash "$tool" names "$work/kde/manifest.json" 011126 0)
[[ $(jq -r .boot <<< "$names") == fedora-rawhide-uke-senemos-boot-011126-r0.img ]]
[[ $(jq -r .system <<< "$names") == fedora-rawhide-kde-plasma-uke-senemos-system-011126-r0.img.zst ]]
reject bash "$tool" names "$work/kde/manifest.json" 311126 0
reject bash "$tool" names "$work/kde/manifest.json" 011126 r0
reject bash "$tool" names "$work/kde/manifest.json" 011126 00
reject bash "$tool" names "$work/kde/manifest.json" 011126 '0;touch bad'
bash "$tool" stage "$work/kde" "$work/delivery" 011126 0
bash "$tool" stage "$work/gnome" "$work/delivery" 011126 0
bash "$tool" stage "$work/kde" "$work/delivery" 011126 0
[[ $(find "$work/delivery/assets" -type f | wc -l) == 3 ]]
[[ $(find "$work/delivery/assets" -name '*-boot-*' | wc -l) == 1 ]]
bash "$tool" verify "$work/delivery"
cp -a "$work/gnome" "$work/different-boot"
printf 'different boot fixture\n' > "$work/different-boot/boot.img"
jq --arg sha "$(sha256sum "$work/different-boot/boot.img" | cut -d ' ' -f1)" '.boot_sha256=$sha' "$work/gnome/manifest.json" > "$work/different-boot/manifest.json"
reject bash "$tool" stage "$work/different-boot" "$work/delivery" 011126 0
grep -F 'boot bytes differ' "$work/rejected" >/dev/null
cp -a "$work/gnome" "$work/different-cohort"
jq '.payload_sha256=("d"*64)' "$work/gnome/manifest.json" > "$work/different-cohort/manifest.json"
reject bash "$tool" stage "$work/different-cohort" "$work/delivery" 011126 0
grep -F 'different kernel cohort' "$work/rejected" >/dev/null
printf 'not an image\n' > "$work/delivery/assets/manifest.json"
reject bash "$tool" verify "$work/delivery"
rm "$work/delivery/assets/manifest.json"
cp "$work/kde/manifest.json" "$work/valid.json"
jq '.image_built="true"' "$work/valid.json" > "$work/kde/manifest.json"
reject bash "$tool" names "$work/kde/manifest.json" 011126 0
cp "$work/valid.json" "$work/kde/manifest.json"
mkdir -p "$work/unsafe/assets"
ln -s "$work/not-created" "$work/unsafe/assets/fedora-rawhide-uke-senemos-boot-011126-r0.img"
reject bash "$tool" stage "$work/kde" "$work/unsafe" 011126 0
[[ ! -e $work/not-created ]]
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
state=$UKE_GH_STATE
mkdir -p "$state/assets"
printf '%s\n' "$*" >> "$state/calls"
option() { local key=$1; shift; while (($#)); do if [[ $1 == "$key" ]]; then printf '%s\n' "$2"; return; fi; shift; done; return 1; }
if [[ $1 == api ]]; then
 if [[ -f $state/release.json ]]; then cat "$state/release.json"; else printf '{"status":"404"}\n'; exit 1; fi
elif [[ $1 == release && $2 == create ]]; then
 notes=$(option --notes-file "$@")
 jq -n --rawfile body "$notes" '{body:$body,assets:[],draft:true}' > "$state/release.json"
elif [[ $1 == release && $2 == upload ]]; then
 shift 3
 while (($#)) && [[ $1 != --* ]]; do
  file=$1 name=${1##*/}; cp "$file" "$state/assets/$name"
  sha=$(sha256sum "$file"); sha=${sha%% *}
  jq --arg name "$name" --arg sha "sha256:$sha" --argjson size "$(stat -c %s "$file")" '.assets += [{name:$name,digest:$sha,size:$size,state:"uploaded"}]' "$state/release.json" > "$state/new.json"
  mv "$state/new.json" "$state/release.json"; shift
 done
elif [[ $1 == release && $2 == download ]]; then
 name=$(option --pattern "$@"); directory=$(option --dir "$@")
 cp "$state/assets/$name" "$directory/$name"
elif [[ $1 == release && $2 == edit ]]; then
 notes=$(option --notes-file "$@")
 jq --rawfile body "$notes" '.body=$body|.draft=false' "$state/release.json" > "$state/new.json"
 mv "$state/new.json" "$state/release.json"
elif [[ $1 == release && $2 == view ]]; then printf 'https://example.invalid/release\n'
else exit 99; fi
SH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GITHUB_REPOSITORY=MCC45TR/fixture SOURCE_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa GITHUB_RUN_ID=123 UKE_GH_STATE=$work/remote
bash "$tool" stage "$work/kde" "$work/kde-only" 011126 0
bash "$publisher" "$work/kde-only"
jq -e '.draft==false and (.assets|length==2) and all(.assets[]; .name|test("[.]img([.]zst)?$")) and (.body|contains("| Image | Bytes | SHA256 |"))' "$work/remote/release.json" >/dev/null
bash "$tool" stage "$work/gnome" "$work/gnome-only" 011126 0
export GITHUB_RUN_ID=456
bash "$publisher" "$work/gnome-only"
jq -e '(.assets|length==3) and ([.assets[]|select(.name|contains("-boot-"))]|length==1)' "$work/remote/release.json" >/dev/null
jq -e '.body|contains("<!-- uke-image-build-runs: 123,456 -->")' "$work/remote/release.json" >/dev/null
grep -F 'release download' "$work/remote/calls" >/dev/null
cp "$work/remote/release.json" "$work/remote.good"
printf 'corrupt published boot\n' > "$work/remote/assets/fedora-rawhide-uke-senemos-boot-011126-r0.img"
reject bash "$publisher" "$work/gnome-only"
grep -F 'Published shared boot bytes differ' "$work/rejected" >/dev/null
cp "$work/kde/boot.img" "$work/remote/assets/fedora-rawhide-uke-senemos-boot-011126-r0.img"
jq '.body="unrecorded cohort"' "$work/remote.good" > "$work/remote/release.json"
reject bash "$publisher" "$work/gnome-only"
cp "$work/remote.good" "$work/remote/release.json"
cp -a "$work/gnome" "$work/root-collision"
printf 'changed GNOME fixture\n' > "$work/root-collision/userdata.img"
jq --arg sha "$(sha256sum "$work/root-collision/userdata.img" | cut -d ' ' -f1)" '.root_sparse_sha256=$sha' "$work/gnome/manifest.json" > "$work/root-collision/manifest.json"
bash "$tool" stage "$work/root-collision" "$work/collision-delivery" 011126 0
reject bash "$publisher" "$work/collision-delivery"
grep -F 'Published image collision' "$work/rejected" >/dev/null
jq '.assets += [{name:"manifest.json",state:"uploaded",digest:("sha256:"+("e"*64)),size:10}]' "$work/remote.good" > "$work/remote/release.json"
before=$(wc -l < "$work/remote/calls")
reject bash "$publisher" "$work/gnome-only"
[[ $(wc -l < "$work/remote/calls") == $((before + 1)) ]]
echo 'Image names, shared boot byte/cohort gates, collisions, image-only publication and legacy-release preservation passed; no GitHub writes ran'
