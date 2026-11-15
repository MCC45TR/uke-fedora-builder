#!/usr/bin/bash
# Exercise the hosted entry point through dispatch to a stub builder only.
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/bin" "$fixture/workspace"
export HOSTED_FIXTURE=$fixture
cat > "$fixture/bin/git" <<'GIT'
#!/usr/bin/bash
printf '%s/workspace\n' "$HOSTED_FIXTURE"
GIT
cat > "$fixture/bin/uname" <<'UNAME'
#!/usr/bin/bash
printf 'aarch64\n'
UNAME
cat > "$fixture/workspace/ukelinux.sh" <<'BUILD'
#!/usr/bin/bash
printf '%s\n' "$@" > "$HOSTED_FIXTURE/arguments"
exit 77
BUILD
chmod +x "$fixture/bin/"* "$fixture/workspace/ukelinux.sh"
for desktop in kde gnome cutefish plasma-mobile; do
    status=0
    PATH="$fixture/bin:$PATH" RUNNER_TEMP=$fixture GITHUB_OUTPUT=$fixture/output GITHUB_RUN_ID=1 IMAGE_DESKTOP=$desktop IMAGE_KERNEL_RPM=7.3.3-28.fc46 bash "$root/scripts/hosted-image.sh" || status=$?
    [[ $status == 77 ]]
    grep -Fx "$desktop" "$fixture/arguments" > /dev/null
    grep -Fx -- '--kernel-profile' "$fixture/arguments" > /dev/null
    grep -Fx 'unstable' "$fixture/arguments" > /dev/null
    grep -Fx '7.3.3-28.fc46' "$fixture/arguments" > /dev/null
done
status=0
PATH="$fixture/bin:$PATH" IMAGE_DESKTOP=unsupported bash "$root/scripts/hosted-image.sh" || status=$?
[[ $status == 2 ]]
printf 'Hosted KDE, GNOME, Cutefish and Plasma Mobile selection reached the stub builder; invalid selection refused.\n'
