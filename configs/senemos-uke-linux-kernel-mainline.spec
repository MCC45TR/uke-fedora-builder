%global debug_package %{nil}
%global _build_id_links none
%global __os_install_post %{nil}
%global _source_filedigest_algorithm 8
%global _binary_filedigest_algorithm 8
%global krel %{version}-senemos-uke
%global _uke_jobs %{?_smp_build_ncpus}%{!?_smp_build_ncpus:4}
%global _uke_out %{_topdir}/kernel-out

Name: senemos-uke-linux-kernel-mainline
Version: 7.2.9
Release: %{?senemos_package_release}%{!?senemos_package_release:1.3}%{?dist}
Summary: Senemos mainline kernel build candidate for Xiaomi Uke
License: GPL-2.0-only
URL: https://github.com/MCC45TR/senemos-uke-kernel-mainline
Source0: linux-%{version}.tar.xz
Source1: senemos-uke-adaptation-%{version}.tar.xz
Source2: linux-%{version}.tar.sign
Source3: linux-stable.asc
ExclusiveArch: aarch64
BuildRequires: bash bc bison flex clang llvm lld make gcc perl
BuildRequires: elfutils-libelf-devel openssl-devel ncurses-devel
BuildRequires: rsync tar xz zstd kmod git-core jq gnupg2
Requires: %{name}-core = %{version}-%{release}
Requires: %{name}-modules = %{version}-%{release}
Requires: %{name}-dtbs = %{version}-%{release}

%description
Uke/SM7675 source-build candidate. Package and compile validation do not
establish tablet boot or hardware support. Firmware and boot routing are
managed separately. No Android partition or boot selection is changed.

%package core
Summary: Senemos Uke ARM64 kernel Image and build identity
Provides: installonlypkg(kernel)
Provides: kernel-uname-r(%{krel})
# Revisions of one upstream version share krel and cannot coexist. Omit the
# release in the equality so all revisions of this version are replaced;
# other upstream versions keep their separate installonly fallback paths.
Obsoletes: %{name}-core = %{version}

%description core
The EFI-enabled ARM64 Image, configuration and System.map for Senemos Uke.

%package modules
Summary: Modules matching the Senemos Uke kernel
Requires: %{name}-core = %{version}-%{release}
Requires: kmod
Provides: installonlypkg(kernel)
Obsoletes: %{name}-modules = %{version}

%description modules
Rebuilt AArch64 modules from the same source and configuration as Image.

%package dtbs
Summary: Independent Uke compile-stage device tree
Requires: %{name}-core = %{version}-%{release}
Provides: installonlypkg(kernel)
Obsoletes: %{name}-dtbs = %{version}

%description dtbs
Uke-specific CPU, interrupt and static reservation description. The future
UEFI handoff must supply exact-profile RAM and dynamic reservations. This
device tree is not physically accepted and unreviewed peripherals are disabled.

%prep
expected=$(tar -xOJf %{SOURCE1} senemos-adaptation/source-lock.json | jq -er .source_sha256)
test "$(sha256sum %{SOURCE0} | cut -d ' ' -f1)" = "$expected"
signer=$(tar -xOJf %{SOURCE1} senemos-adaptation/source-lock.json | jq -er .signer)
mkdir -p %{_topdir}/gnupg
chmod 700 %{_topdir}/gnupg
gpg --homedir %{_topdir}/gnupg --batch --import %{SOURCE3}
xz -cd %{SOURCE0} | gpg --homedir %{_topdir}/gnupg --batch --status-fd=1 \
    --verify %{SOURCE2} - > %{_topdir}/source-verification.txt
grep -F "[GNUPG:] VALIDSIG $signer " %{_topdir}/source-verification.txt
%setup -q -n linux-%{version}
tar -xJf %{SOURCE1}
# Keep git apply rooted here even when the RPM development tree is nested
# inside a workspace repository. Otherwise Git silently skips those paths.
git -c init.defaultBranch=senemos init -q
while IFS= read -r patch_name; do
    test -n "$patch_name" || continue
    git apply --check "senemos-adaptation/patches/$patch_name" || exit 1
    git apply "senemos-adaptation/patches/$patch_name" || exit 1
done < senemos-adaptation/patches/series

%build
%if !0%{?uke_package_only}
export ARCH=arm64 LLVM=1
export KBUILD_BUILD_USER=senemos KBUILD_BUILD_HOST=uke-builder
export KBUILD_BUILD_TIMESTAMP='2026-10-03 10:44:10 UTC' KBUILD_BUILD_VERSION=1
export SOURCE_DATE_EPOCH=1791024250
# A killed fixdep can leave a partially written .cmd file. Preserve completed
# objects and discard only dependency records that no longer parse as Make.
if test -d %{_uke_out}; then
    find %{_uke_out} -type f -name '.*.cmd' | while IFS= read -r record; do
        if ! make -s -rR -f "$record" --eval '.PHONY: senemos_parse_check' \
            --eval 'senemos_parse_check: ; @:' senemos_parse_check >/dev/null 2>&1; then
            rm -f "$record"
            echo 'Discarded an incomplete dependency record from an interrupted build'
        fi
    done
fi
make O=%{_uke_out} defconfig
scripts/kconfig/merge_config.sh -m -O %{_uke_out} %{_uke_out}/.config \
    senemos-adaptation/configs/arm64-qcom.config \
    senemos-adaptation/configs/uke.config senemos-adaptation/configs/fedora.config
make O=%{_uke_out} LOCALVERSION=-senemos-uke olddefconfig
# Kconfig can silently drop a requested symbol when its dependencies are absent.
# Check every enabled/value requirement after dependency resolution.
for fragment in senemos-adaptation/configs/uke.config senemos-adaptation/configs/fedora.config; do
    while IFS= read -r item; do
        case "$item" in CONFIG_*=*) grep -Fx "$item" %{_uke_out}/.config || exit 1;; esac
    done < "$fragment"
done
for item in CONFIG_PINCTRL_CLIFFS=y CONFIG_SM_GCC_CLIFFS=y \
    CONFIG_QCOM_RPMH_UKE=y CONFIG_INTERCONNECT_QCOM_CLIFFS_USB=y \
    CONFIG_EFI=y CONFIG_EFI_STUB=y CONFIG_MODULES=y; do
    grep -Fx "$item" %{_uke_out}/.config || exit 1
done
make O=%{_uke_out} LOCALVERSION=-senemos-uke -j%{_uke_jobs} Image dtbs modules
test "$(make -s O=%{_uke_out} LOCALVERSION=-senemos-uke kernelrelease)" = '%{krel}'
%else
# A lifecycle-test release repackages the already verified build, without
# short-circuit RPM dependencies or a second kernel compilation.
test -s %{_uke_out}/arch/arm64/boot/Image
test -s %{_uke_out}/Module.symvers
%endif

%install
export ARCH=arm64 LLVM=1
make O=%{_uke_out} LOCALVERSION=-senemos-uke modules_install \
    INSTALL_MOD_PATH=%{buildroot} INSTALL_MOD_STRIP=1 DEPMOD=true
module_dir=%{buildroot}/lib/modules/%{krel}
rm -f "$module_dir/build" "$module_dir/source"
mkdir -p %{buildroot}%{_prefix}/lib/modules
mv "$module_dir" %{buildroot}%{_prefix}/lib/modules/
rm -rf %{buildroot}/lib
module_dir=%{buildroot}%{_prefix}/lib/modules/%{krel}
find "$module_dir" -name '*.ko' -type f -exec zstd -q -T1 --rm {} \;
install -m644 %{_uke_out}/arch/arm64/boot/Image "$module_dir/vmlinuz"
install -m644 %{_uke_out}/.config "$module_dir/config"
install -m644 %{_uke_out}/System.map "$module_dir/System.map"
mkdir -p "$module_dir/dtb/qcom"
install -m644 %{_uke_out}/arch/arm64/boot/dts/qcom/sm7675-xiaomi-uke.dtb "$module_dir/dtb/qcom/"
depmod -b %{buildroot} -m /usr/lib/modules -a %{krel}
mkdir -p %{buildroot}%{_datadir}/senemos/uke/%{krel}
install -m644 senemos-adaptation/source-lock.json \
    %{buildroot}%{_datadir}/senemos/uke/%{krel}/source-lock.json

%post modules -p /bin/sh
if command -v depmod >/dev/null 2>&1; then depmod -a %{krel}; fi

%postun modules -p /bin/sh
# Reindex only when another release of this module package remains installed.
# On the last removal, regenerating indexes would leave unowned kernel files.
if test "$1" -gt 0 && command -v depmod >/dev/null 2>&1 && test -d /usr/lib/modules/%{krel}; then
    depmod -a %{krel}
fi

%files
%doc senemos-adaptation/README.md
%license COPYING

%files core
%dir /usr/lib/modules/%{krel}
/usr/lib/modules/%{krel}/vmlinuz
/usr/lib/modules/%{krel}/config
/usr/lib/modules/%{krel}/System.map
/usr/lib/modules/%{krel}/modules.builtin
/usr/lib/modules/%{krel}/modules.builtin.modinfo
%verify(not mtime) /usr/lib/modules/%{krel}/modules.builtin*.bin
/usr/lib/modules/%{krel}/modules.order
/usr/share/senemos/uke/%{krel}/source-lock.json

%files modules
/usr/lib/modules/%{krel}/kernel/
%verify(not mtime) /usr/lib/modules/%{krel}/modules.alias*
%verify(not mtime) /usr/lib/modules/%{krel}/modules.dep*
%verify(not mtime) /usr/lib/modules/%{krel}/modules.devname
%verify(not mtime) /usr/lib/modules/%{krel}/modules.softdep
%verify(not mtime) /usr/lib/modules/%{krel}/modules.symbols*
%verify(not mtime) /usr/lib/modules/%{krel}/modules.weakdep

%files dtbs
/usr/lib/modules/%{krel}/dtb/

%changelog
* Sun Oct 04 2026 Senemos Maintainers <MCC45TR@users.noreply.github.com> - 7.2.9-1
- Build the Uke platform adaptations with Fedora Rawhide packaging.
