#!/usr/bin/env bash
# COPR producer entry: keep the complete owned root in a private regular-file SDK.
set -Eeuo pipefail
[[ ${UKE_COPR_WORKER_AUDIT:-0} == 1 && $# == 4 && -d $1 && -d $2 && -d $3 && ! -e $4 && ! -L $4 ]]
recipe=$(realpath "$1") inputs=$(realpath "$2") target=$(realpath "$3") output=$(realpath -m "$4")
[[ $recipe =~ ^/[A-Za-z0-9_./+-]+$ && $inputs =~ ^/[A-Za-z0-9_./+-]+$ &&
   $target =~ ^/[A-Za-z0-9_./+-]+$ && $output =~ ^/[A-Za-z0-9_./+-]+$ ]]
# shellcheck source=copr-root-inputs.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-root-inputs.sh"
# shellcheck source=copr-sdk.sh
# shellcheck disable=SC1091
source "$recipe/src/public/copr-sdk.sh"
mkdir -m700 "$output"
mkdir "$output/input-audit"
public_copr_root_inputs "$recipe" "$target" "$output/input-audit"
size=$(jq -er .size_mib "$target/request.json")
input_mib=$(( ($(du -sk "$inputs" "$target" | awk '{sum+=$1} END{print sum}')+1023)/1024 ))
sdk_mib=$((8192+size*3+input_mib*2))
available_kib=$(df -Pk "$output" | awk 'NR==2 {print $4}')
(( available_kib >= sdk_mib*1024 )) || { echo "At least $sdk_mib MiB is required for the complete root SDK" >&2; exit 1; }
public_copr_sdk "$recipe" "$inputs" "$output"
mkdir -p "$output/target-repo/rpms/fedora" "$output/target-repo/rpms/uke"
while IFS=$'\t' read -r path _; do
    # Copy only independently verified, declared RPMs into fresh repository metadata.
    cp --reflink=auto "$target/$path" "$output/target-repo/$path"
done < "$output/input-audit/target-actual-rpms.tsv"
for role in fedora uke; do createrepo_c --no-database "$output/target-repo/rpms/$role"; done
tar -cf "$output/target.tar" -C "$target" request.json manifest.json firmware-review.json uke-key.asc \
    -C "$output/target-repo" rpms
tar -cf "$output/recipe.tar" -C "$recipe" src configs
truncate -s "${sdk_mib}M" "$output/sdk.raw"
cat > "$output/root.commands" <<GUEST
set-smp 2
set-memsize 2048
set-network false
run
mkfs ext4 /dev/sda
mount /dev/sda /
tar-in $output/sdk.tar /
write /.uke-copr-sdk 1
mkdir-p /builder
tar-in $output/recipe.tar /builder
mkdir-p /inputs/target
tar-in $output/target.tar /inputs/target
mkdir-p /job
upload $output/mke2fs.sha256 /job/mke2fs.sha256
command-out "/usr/bin/bash /builder/src/public/copr-root-entry.sh" -
download /job/rootfs.tar $output/rootfs.tar
download /job/artifacts.tar $output/artifacts.tar
download /job/production-root.log $output/production-root.log
sync
umount-all
GUEST
public_copr_guest_run rw "$output/sdk.raw" "$output/root.commands" "$output/root.log" 14400
sha256sum "$output/sdk.raw" "$output/rootfs.tar" "$output/artifacts.tar" > "$output/root-stage.sha256"
printf '%s\n' 'Production root archive and SDK retained; full filesystem composition and independent readback remain required.'
