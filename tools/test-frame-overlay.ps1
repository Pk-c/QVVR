[CmdletBinding()]
param([string]$BashPath='C:\Program Files\Git\bin\bash.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'package-assets/QVVR-Frame-Setup.ps1')
if(!(Test-Path -LiteralPath $BashPath -PathType Leaf)){throw 'Git Bash is required for the POSIX Frame-overlay regression fixture.'}
$fixtureRoot=Join-Path $root ('artifacts/frame-overlay-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$encoding=New-Object Text.UTF8Encoding($false)
function Write-ShellFixture([string]$Name,[string]$Text){[IO.File]::WriteAllText((Join-Path $fixtureRoot $Name),($Text -replace "`r`n","`n"),$encoding)}
$helper=Get-QvvrFrameHelper
Write-ShellFixture 'production.sh' $helper
# Only translate the two storage-prefix gates into the private fixture root;
# every operation, checksum, path/link guard, conflict and backup is production.
$gate='case "$game" in /home/steamos/*|/run/media/*)'
if(([regex]::Matches($helper,[regex]::Escape($gate))).Count -ne 2){throw 'Production storage gates changed; update the fixture deliberately.'}
Write-ShellFixture 'manage.sh' ($helper.Replace($gate,'case "$game" in "$QVVR_TEST_ROOT"/*)'))
$tests=@'
#!/bin/sh
set -eu
root=$(cd "$1" && pwd -P)
payload=$(cygpath -u "$2")
export QVVR_TEST_ROOT=$root
export QVVR_TEST_RUNNING=0
mkdir "$root/bin"
cat >"$root/bin/pgrep" <<'PGREP'
#!/bin/sh
case "$QVVR_TEST_RUNNING" in 0) exit 1;; 1) exit 0;; *) exit 2;; esac
PGREP
cat >"$root/bin/bsdtar" <<'TAR'
#!/bin/sh
exec /c/Windows/System32/tar.exe "$@"
TAR
chmod +x "$root/bin/pgrep" "$root/bin/bsdtar"
PATH="$root/bin:$PATH"
export PATH
checks=0
assert() { checks=$((checks+1)); if ! "$@"; then echo "Assertion $checks failed: $*" >&2; exit 1; fi; }
reject() { checks=$((checks+1)); if "$@" >"$root/expected-rejection.log" 2>&1; then echo "Expected rejection $checks: $*" >&2; exit 1; fi; }
game="$root/QV game with spaces"
mkdir -p "$game/QV_Data" "$game/BepInEx/config" "$game/BepInEx/plugins/OtherMod"
printf 'original game' >"$game/QV.exe"
printf 'my settings' >"$game/BepInEx/config/dev.qvvr.prototype.cfg"
printf 'other mod' >"$game/BepInEx/plugins/OtherMod/keep.dll"
run() {
    action=$1
    session=$root/session-$2
    mkdir "$session"
    if test "$action" = Install; then cp "$payload" "$session/package.zip"; fi
    sh "$root/manage.sh" "$action" "$game" "$session" "${3:-0}"
}
mkdir "$root/reject-session"
reject sh "$root/production.sh" Check "$game" "$root/reject-session" 0
printf 'unrelated uninstaller' >"$game/uninstall.bat"
reject run Install unowned-uninstaller
assert test "$(cat "$game/uninstall.bat")" = 'unrelated uninstaller'
assert test ! -d "$game/.qvvr-backups/Install-session-unowned-uninstaller"
rm "$game/uninstall.bat"
run Install first
assert test -f "$game/BepInEx/plugins/QVVR/QVVR.dll"
assert test -f "$game/uninstall.ps1"
assert test "$(cat "$game/QV.exe")" = 'original game'
assert test "$(cat "$game/BepInEx/config/dev.qvvr.prototype.cfg")" = 'my settings'
assert test "$(cat "$game/BepInEx/plugins/OtherMod/keep.dll")" = 'other mod'
assert test -z "$(grep -F 'BepInEx/config/dev.qvvr.prototype.cfg' "$game/.qvvr-backups/Install-session-first/installed-files.txt" || true)"
assert test -f "$game/.qvvr-backups/Install-session-first/new-files.txt"
printf 'old private plugin' >"$game/BepInEx/plugins/QVVR/QVVR.dll"
run Install second
assert test "$(cat "$game/.qvvr-backups/Install-session-second/BepInEx/plugins/QVVR/QVVR.dll")" = 'old private plugin'
assert cmp -s "$root/session-first/stage/BepInEx/plugins/QVVR/QVVR.dll" "$game/BepInEx/plugins/QVVR/QVVR.dll"
assert test "$(cat "$game/BepInEx/config/dev.qvvr.prototype.cfg")" = 'my settings'
printf 'user edited documentation' >"$game/README.txt"
reject run Install edited-readme
assert test "$(cat "$game/README.txt")" = 'user edited documentation'
assert test ! -d "$game/.qvvr-backups/Install-session-edited-readme"
cp "$root/session-first/stage/README.txt" "$game/README.txt"
printf 'different shared loader' >"$game/BepInEx/core/BepInEx.dll"
reject run Install incompatible-loader
assert test ! -d "$game/.qvvr-backups/Install-session-incompatible-loader"
assert test "$(cat "$game/BepInEx/core/BepInEx.dll")" = 'different shared loader'
assert cmp -s "$root/session-first/stage/BepInEx/plugins/QVVR/QVVR.dll" "$game/BepInEx/plugins/QVVR/QVVR.dll"
export QVVR_TEST_RUNNING=1
reject run Install running-install
reject run Uninstall running-uninstall
assert test -f "$game/BepInEx/plugins/QVVR/QVVR.dll"
export QVVR_TEST_RUNNING=2
reject run Uninstall process-error
export QVVR_TEST_RUNNING=0
MSYS=winsymlinks:nativestrict ln -s "$game/BepInEx/plugins/OtherMod" "$game/BepInEx/plugins/QVVR/linked"
assert test -L "$game/BepInEx/plugins/QVVR/linked"
reject run Uninstall linked-plugin
assert test -f "$game/BepInEx/plugins/OtherMod/keep.dll"
rm "$game/BepInEx/plugins/QVVR/linked"
run Uninstall remove
assert test ! -d "$game/BepInEx/plugins/QVVR"
assert test -f "$game/.qvvr-backups/Uninstall-session-remove/BepInEx/plugins/QVVR/QVVR.dll"
assert test "$(cat "$game/BepInEx/core/BepInEx.dll")" = 'different shared loader'
assert test -f "$game/winhttp.dll"
assert test "$(cat "$game/BepInEx/config/dev.qvvr.prototype.cfg")" = 'my settings'
run Uninstall repeated
assert test ! -d "$game/.qvvr-backups/Uninstall-session-repeated"
run Uninstall remove-config 1
assert test ! -f "$game/BepInEx/config/dev.qvvr.prototype.cfg"
assert test "$(cat "$game/.qvvr-backups/Uninstall-session-remove-config/BepInEx/config/dev.qvvr.prototype.cfg")" = 'my settings'
assert test "$(cat "$game/QV.exe")" = 'original game'
assert test "$(cat "$game/BepInEx/plugins/OtherMod/keep.dll")" = 'other mod'
echo "Frame POSIX overlay: $checks assertions passed (local fixtures, not hardware deployment)."
'@
Write-ShellFixture 'tests.sh' $tests
$shellRoot=$fixtureRoot.Replace('\','/')
# The Frame receives the overlay rebuilt from the release PC/ folder.
$overlayZip=Join-Path $fixtureRoot 'overlay.zip'
New-QvvrUploadArchive (Join-Path $root 'build/release/QVVR-v0.1.0.zip') $overlayZip
$zip=$overlayZip.Replace('\','/')
& $BashPath --noprofile --norc (Join-Path $fixtureRoot 'tests.sh') $shellRoot $zip
if($LASTEXITCODE -ne 0){throw "Frame overlay shell fixture failed. Inspect $fixtureRoot"}
