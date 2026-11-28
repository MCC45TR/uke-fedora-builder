#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Native COPR executable interoperability; never uses a real release key.
set -Eeuo pipefail
trap 'printf "UKE_COHORT_AUTH_TEST_FAILED: line=%s status=%s\n" "$LINENO" "$?" >&2' ERR
export LC_ALL=C
umask 077
[[ $# == 2 && $(uname -m) == aarch64 && -x $1 && ! -e $2 && ! -L $2 ]]
tool=$(realpath "$1") report=$(realpath -m "$2")
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT
cd "$work"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem 2> keygen.log
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out other.pem 2> other-keygen.log
for key in key other; do
    openssl pkey -in "$key.pem" -pubout -out "$key.pub"
    openssl pkey -pubin -in "$key.pub" -outform DER -out "$key.der"
done
pin=$(sha256sum key.der | cut -d ' ' -f1)
printf 'UKE-PROTECTED-COHORT-v1\n{"fixture":"native-signature-only"}\n' > cohort
sign() {
    openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss \
        -sigopt rsa_pss_saltlen:32 -sigopt rsa_mgf1_md:sha256 -out "$2" "$1"
}
sign cohort cohort.sig
sha256sum cohort key.pub cohort.sig > original-inputs.sha256
"$tool" key.pub "$pin" cohort cohort.sig > positive.json
jq -e --arg hash "$(sha256sum cohort | cut -d ' ' -f1)" --arg pin "$pin" \
    '.signature_verified and .payload_sha256==$hash and .signer_spki_sha256==$pin and
     (.manifest_semantics_admitted|not) and (.role_admitted|not) and
     (.snapshot_authenticated|not) and (.hardware_trust_qualified|not)' positive.json >/dev/null
refusals=0
reject() {
    if timeout 5s "$tool" "$@" > refused.json 2> refused.log; then
        echo 'Invalid cohort signature input accepted' >&2; exit 1
    else
        status=$?
    fi
    [[ $status == 1 && ! -s refused.json ]]
    [[ $(cat refused.log) == UKE_COHORT_SIGNATURE_REJECTED ]]
    refusals=$((refusals+1))
}
cp cohort tampered
printf x >> tampered
reject key.pub "$pin" tampered cohort.sig
reject key.pub "${pin:1}" cohort cohort.sig
reject key.pub "${pin^^}" cohort cohort.sig
reject other.pub "$pin" cohort cohort.sig
openssl dgst -sha256 -sign other.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 -out other.sig cohort
reject key.pub "$pin" cohort other.sig
openssl dgst -sha256 -sign key.pem -out pkcs1.sig cohort
reject key.pub "$pin" cohort pkcs1.sig
openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:0 -out salt0.sig cohort
reject key.pub "$pin" cohort salt0.sig
openssl dgst -sha256 -sign key.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 -sigopt rsa_mgf1_md:sha384 -out mgf384.sig cohort
reject key.pub "$pin" cohort mgf384.sig
printf 'OTHER-DOMAIN\n{"fixture":"native-signature-only"}\n' > wrong-domain
sign wrong-domain wrong-domain.sig
reject key.pub "$pin" wrong-domain wrong-domain.sig
printf 'UKE-PROTECTED-COHORT-v1\n' > empty-domain
sign empty-domain empty-domain.sig
reject key.pub "$pin" empty-domain empty-domain.sig
head -c511 cohort.sig > short.sig
reject key.pub "$pin" cohort short.sig
cp cohort.sig long.sig
printf x >> long.sig
reject key.pub "$pin" cohort long.sig
cat key.pub other.pub > concatenated.pub
reject concatenated.pub "$pin" cohort cohort.sig
cp key.pub garbage.pub
printf garbage >> garbage.pub
reject garbage.pub "$pin" cohort cohort.sig
reject key.pem "$pin" cohort cohort.sig
cat > encrypted-public.pub <<'PEM'
-----BEGIN PUBLIC KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: AES-256-CBC,00000000000000000000000000000000

AAAAAAAAAAAAAAAAAAAAAA==
-----END PUBLIC KEY-----
PEM
reject encrypted-public.pub "$pin" cohort cohort.sig
cp cohort boundary
truncate -s65536 boundary
sign boundary boundary.sig
"$tool" key.pub "$pin" boundary boundary.sig > boundary.json
printf x >> boundary
reject key.pub "$pin" boundary boundary.sig
cp key.pub big.pub
truncate -s8193 big.pub
reject big.pub "$pin" cohort cohort.sig
for name in key.pub cohort cohort.sig; do
    ln -s "$name" linked
    case $name in
        key.pub) reject linked "$pin" cohort cohort.sig;;
        cohort) reject key.pub "$pin" linked cohort.sig;;
        cohort.sig) reject key.pub "$pin" cohort linked;;
    esac
    unlink linked
done
mkdir parent
cp cohort parent/cohort
ln -s parent parent-link
reject key.pub "$pin" parent-link/cohort cohort.sig
mkfifo fifo
reject key.pub "$pin" fifo cohort.sig
reject key.pub "$pin" /dev/null cohort.sig
reject key.pub "$pin" parent cohort.sig
reject key.pub "$pin" /proc/self/fd/0 cohort.sig < cohort
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out weak.pem 2> weak-keygen.log
openssl pkey -in weak.pem -pubout -out weak.pub
openssl dgst -sha256 -sign weak.pem -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 -out weak.sig cohort
truncate -s512 weak.sig
reject weak.pub "$pin" cohort weak.sig
sha256sum -c original-inputs.sha256 > unchanged.log
[[ $refusals == 27 ]]
jq -n --arg pin "$pin" --argjson refused "$refusals" \
    '{schema_version:1,native_architecture:"aarch64",openssl_interoperability:true,
      rsa_bits:4096,signature:"RSA-PSS-SHA256",mgf1:"SHA256",salt_bytes:32,
      signer_spki_sha256:$pin,refused_cases:$refused,maximum_payload_bytes:65536,
      exact_limit_passed:true,original_inputs_unchanged:true,
      keys_are_ephemeral_fixtures:true,manifest_semantics_admitted:false,
      role_admitted:false,snapshot_authenticated:false,hardware_trust_qualified:false,
      storage_or_key_release_executed:false}' > "$report"
