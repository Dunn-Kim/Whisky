#!/bin/bash
# Installs a local arm64 Wine runtime as WhiskyNative's engine. No arm64
# runtime is published yet, so the app cannot download one: this puts a
# runtime you already have, for example the `wine` folder of a Mach9 build,
# where the app looks for it.
#
# Usage: scripts/install-arm64-runtime.sh <runtime folder> <version>
#   e.g. scripts/install-arm64-runtime.sh ~/Downloads/mach9/wine 0.4.0
#
# The folder must hold an arm64 bin/wine, bin/wineserver and
# lib/wine/aarch64-unix. Its loader (lib/wine/aarch64-unix/wine.app) must be
# signed with the cross-architecture entitlement, as Mach9's is; the copy keeps
# that signature.
#
# Quit WhiskyNative and every program it started first: the script replaces
# the whole Libraries folder, as the app's own runtime install does.
set -euo pipefail

usage="usage: install-arm64-runtime.sh <runtime folder> <version>, e.g. ~/Downloads/mach9/wine 0.4.0"
SRC="${1:?$usage}"
VERSION="${2:?$usage}"
LIB="$HOME/Library/Application Support/io.github.dunn-kim.WhiskyNative/Libraries"

[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "version must be major.minor.patch: $VERSION"; exit 1; }
for f in bin/wine bin/wineserver lib/wine/aarch64-unix/ntdll.so lib/wine/aarch64-unix/wine.app; do
    [ -e "$SRC/$f" ] || { echo "not an arm64 Wine runtime: $SRC/$f is missing"; exit 1; }
done
file -b "$SRC/bin/wine" | grep -q arm64 || { echo "$SRC/bin/wine is not an arm64 binary"; exit 1; }
codesign -d --entitlements - --xml "$SRC/lib/wine/aarch64-unix/wine.app" 2>/dev/null \
    | grep -q com.apple.developer.cross-architecture-support \
    || { echo "the loader in $SRC lacks the cross-architecture entitlement, so x86 programs cannot run"; exit 1; }
if pgrep -f "$LIB/Wine/" >/dev/null; then
    echo "a program still runs on the installed engine; quit it first"
    exit 1
fi

# The app offers Enhanced Sync only on a runtime that says it implements msync.
msync=false
if grep -qa msync_abandon_mutexes "$SRC/bin/wineserver"; then msync=true; fi

# Assemble beside the old runtime and swap at the end, so a failed copy leaves it in place.
rm -rf "$LIB.new"
mkdir -p "$LIB.new"
ditto "$SRC" "$LIB.new/Wine"
cat > "$LIB.new/WhiskyWineVersion.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>version</key>
	<dict>
		<key>major</key>
		<integer>${BASH_REMATCH[1]}</integer>
		<key>minor</key>
		<integer>${BASH_REMATCH[2]}</integer>
		<key>patch</key>
		<integer>${BASH_REMATCH[3]}</integer>
	</dict>
	<key>msyncCapable</key>
	<${msync}/>
</dict>
</plist>
EOF
plutil -lint "$LIB.new/WhiskyWineVersion.plist" >/dev/null
rm -rf "$LIB"
mv "$LIB.new" "$LIB"
echo "installed $VERSION from $SRC into $LIB"
