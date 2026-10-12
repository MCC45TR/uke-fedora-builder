#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
check() { bash "$root/src/boot/vmlinux-exports.sh" "$fixture/Module.symvers"; }
printf '0x00000000 core_two vmlinux EXPORT_SYMBOL_GPL NS\n0x00000000 core_one vmlinux EXPORT_SYMBOL\n0x00000000 module_only drivers/example EXPORT_SYMBOL\n' > "$fixture/Module.symvers"
printf '0x00000000 core_one vmlinux EXPORT_SYMBOL\n0x00000000 core_two vmlinux EXPORT_SYMBOL_GPL NS\n' > "$fixture/expected"
cp "$fixture/expected" "$fixture/vmlinux.symvers"
check > "$fixture/actual"
cmp "$fixture/expected" "$fixture/actual"
# A stale legacy receipt still matches, but changed current exports must reject.
sed -i 's/core_two/core_changed/' "$fixture/Module.symvers"
check > "$fixture/actual"
if cmp -s "$fixture/expected" "$fixture/actual"; then echo 'Changed current export hidden by stale receipt' >&2; exit 1; fi
cmp "$fixture/expected" "$fixture/vmlinux.symvers"
sed -i 's/core_changed/core_two/; s/module_only/changed_module_export/' "$fixture/Module.symvers"
check > "$fixture/actual"
cmp "$fixture/expected" "$fixture/actual"
sed -i 's/0x00000000 core_one/0x12345678 core_one/' "$fixture/Module.symvers"
check > "$fixture/actual"
if cmp -s "$fixture/expected" "$fixture/actual"; then echo 'Changed core CRC accepted' >&2; exit 1; fi
printf '0x00000000 module_only drivers/example EXPORT_SYMBOL\n' > "$fixture/Module.symvers"
if check >/dev/null; then echo 'Missing core export table accepted' >&2; exit 1; fi
: > "$fixture/Module.symvers"
if check >/dev/null; then echo 'Empty modpost table accepted' >&2; exit 1; fi
rm "$fixture/Module.symvers"
if check >/dev/null; then echo 'Absent modpost table accepted' >&2; exit 1; fi
echo 'Current modpost exports: ordering/module-only changes accepted; stale receipt, changed core/CRC and missing tables rejected'
