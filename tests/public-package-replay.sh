#!/usr/bin/env bash
# Real DNF5/RPM fixture, only inside a disposable host SDK; no device operations.
# shellcheck disable=SC2034
set -Eeuo pipefail
[[ $(id -u) == 0 ]]
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../src/public/packages.sh
# shellcheck disable=SC1091
source "$root/src/public/packages.sh"
work=$(mktemp -d /tmp/uke-package-replay.XXXXXX)
trap 'find "$work" -depth -delete' EXIT
mkdir -p "$work"/{repo,keys,top/{SPECS,SOURCES,RPMS,SRPMS,BUILD},repos}
chmod 700 "$work/keys"
export GNUPGHOME=$work/keys
gpg --batch --passphrase '' --quick-generate-key 'Replay fixture <fixture@example.invalid>' rsa2048 sign 1d >/dev/null 2>&1
fingerprint=$(gpg --batch --with-colons --list-keys | awk -F: '$1=="fpr" {print $10;exit}')
gpg --batch --armor --export "$fingerprint" > "$work/key.asc"
cat > "$work/top/SPECS/fixture.spec" <<'SPEC'
Name: uke-replay-fixture
Version: 1
Release: 1
Summary: Disposable host transaction fixture
License: MIT
BuildArch: noarch
AutoReqProv: no
%description
No device code or scriptlets.
%install
mkdir -p %{buildroot}/usr/share/%{name}
printf 'fixed payload\n' > %{buildroot}/usr/share/%{name}/value
%files
/usr/share/%{name}/value
SPEC
rpmbuild -bb --define "_topdir $work/top" "$work/top/SPECS/fixture.spec" > "$work/build.log" 2>&1
archive=$work/top/RPMS/noarch/uke-replay-fixture-1-1.noarch.rpm
rpmsign --define "_openpgp_sign_id $fingerprint" --define '_openpgp_sign gpg' --addsign "$archive" > "$work/sign.log" 2>&1
cp "$archive" "$work/repo/"
sed -i 's/^Name: uke-replay-fixture$/Name: uke-replay-local/' "$work/top/SPECS/fixture.spec"
rpmbuild -bb --define "_topdir $work/top" "$work/top/SPECS/fixture.spec" > "$work/build.log" 2>&1
local_archive=$work/top/RPMS/noarch/uke-replay-local-1-1.noarch.rpm
sed -i 's/^Name: uke-replay-local$/Name: uke-replay-unsigned/' "$work/top/SPECS/fixture.spec"
rpmbuild -bb --define "_topdir $work/top" "$work/top/SPECS/fixture.spec" > "$work/build.log" 2>&1
cp "$work/top/RPMS/noarch/uke-replay-unsigned-1-1.noarch.rpm" "$work/repo/"
createrepo_c --quiet "$work/repo"
cat > "$work/repos/fixture.repo" <<REPO
[fixture]
name=Disposable replay fixture
baseurl=file://$work/repo
enabled=0
gpgcheck=1
gpgkey=file://$work/key.asc
REPO
cat > "$work/repos/source.repo" <<REPO
[uke-source-build]
name=Disposable local-source fixture
baseurl=file://$work/repo
enabled=0
gpgcheck=0
REPO
transaction=$work/transaction
select_root() {
    rpm_root=$work/$1
    mkdir -p "$rpm_root"
    rpmkeys --root "$rpm_root" --import "$work/key.asc"
    dnf=(dnf5 --use-host-config --installroot="$rpm_root" --releasever=rawhide
        --disable-repo='*' --setopt="reposdir=$work/repos" --setopt=gpgcheck=True
        --setopt=install_weak_deps=False)
}
select_root first
repositories=(--enable-repo=fixture)
public_packages "$transaction" install uke-replay-fixture "$local_archive" > "$work/store.log" 2>&1 || { cat "$work/store.log"; cat "$transaction/transaction.json"; exit 1; }
[[ $(find "$transaction" -name '*.rpm' | wc -l) == 2 ]]
public_packages "$work/no-op" install uke-replay-fixture > "$work/no-op.log" 2>&1 || { cat "$work/no-op.log"; exit 1; }
[[ -f $work/no-op/NO_CHANGES ]]
if public_packages "$work/unsigned-remote" install uke-replay-unsigned > "$work/unsigned.log" 2>&1; then exit 1; fi
[[ ! -e $work/first/usr/share/uke-replay-unsigned/value ]]
select_root local-source
repositories=(--enable-repo=uke-source-build)
public_packages "$work/local-source-transaction" install uke-replay-unsigned > "$work/local-source.log" 2>&1 || { cat "$work/local-source.log"; exit 1; }
[[ -f $rpm_root/usr/share/uke-replay-unsigned/value ]]
# Exercise the actual builddep plugin used by both static and dynamic passes.
select_root build-dependencies
repositories=(--enable-repo=fixture)
sed -i '/^AutoReqProv:/a BuildRequires: uke-replay-fixture = 1-1' "$work/top/SPECS/fixture.spec"
rpmbuild -bs --define "_topdir $work/top" "$work/top/SPECS/fixture.spec" > "$work/build.log" 2>&1
public_packages "$work/builddep-transaction" builddep "$work/top/SRPMS/uke-replay-unsigned-1-1.src.rpm" > "$work/builddep.log" 2>&1 || { cat "$work/builddep.log"; exit 1; }
rpm --root "$rpm_root" -q uke-replay-fixture > /dev/null
# The source repository is gone; the second empty root must use the captured RPM.
mv "$work/repo" "$work/repo-disabled"
select_root second
public_replay "$transaction" > "$work/replay.log" 2>&1 || { cat "$work/replay.log"; exit 1; }
for target in first second; do
    rpm --root "$work/$target" -qa --qf '%{NEVRA}\n' | LC_ALL=C sort > "$work/$target.tsv"
done
cmp "$work/first.tsv" "$work/second.tsv"
cmp "$work/first/usr/share/uke-replay-fixture/value" "$work/second/usr/share/uke-replay-fixture/value"
if public_packages "$transaction" install uke-replay-fixture > /dev/null 2>&1; then exit 1; fi
# A different installed version must fail strict replay.
sed -i -e 's/^Version: 1$/Version: 2/' -e 's/^Name: uke-replay-unsigned$/Name: uke-replay-fixture/' -e '/^BuildRequires:/d' "$work/top/SPECS/fixture.spec"
rpmbuild -bb --define "_topdir $work/top" "$work/top/SPECS/fixture.spec" > "$work/build.log" 2>&1
rpmsign --define "_openpgp_sign_id $fingerprint" --define '_openpgp_sign gpg' --addsign "$work/top/RPMS/noarch/uke-replay-fixture-2-1.noarch.rpm" > "$work/sign.log" 2>&1
select_root upgrade
rpm --root "$rpm_root" -i "$transaction/packages/uke-replay-fixture-1-1.noarch.rpm"
repositories=()
public_packages "$work/upgrade-transaction" install "$work/top/RPMS/noarch/uke-replay-fixture-2-1.noarch.rpm" > "$work/upgrade.log" 2>&1 || { cat "$work/upgrade.log"; cat "$work/upgrade-transaction/transaction.json"; exit 1; }
[[ $(rpm --root "$rpm_root" -q uke-replay-fixture --qf '%{VERSION}') == 2 ]]
select_root second
rpm --root "$work/second" -U "$work/top/RPMS/noarch/uke-replay-fixture-2-1.noarch.rpm"
if public_replay "$transaction" > "$work/version.log" 2>&1; then exit 1; fi
# Missing captured bytes must fail even if the original repository was available.
find "$transaction" -name '*.rpm' -delete
select_root third
if public_replay "$transaction" > "$work/missing.log" 2>&1; then exit 1; fi
echo 'Signed remote/local-source inputs and builddep passed; independent roots match without the source repository; unsigned remote, duplicate, version and missing-input refusals passed'
