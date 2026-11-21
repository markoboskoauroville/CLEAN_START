#!/bin/sh
# Clean Start (Mantra): built ONLY by GitHub Actions (.github/workflows/mac-swift.yml, MANTRA_MANIFEST compile-on-github.md).
# Never run on the Mac. The Mac installs the release (TAKEOVER.md, Install).
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
APP="build/Clean Start (Mantra).app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
./tools/check_one_title.sh
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/Clean Start (Mantra)" app/*.swift \
  -framework AppKit -framework SwiftUI -framework Carbon
# the icon, drawn in code (tools/make_icon.swift): CLE / STA over a power symbol, black tile (six-letter-icon.md)
swift tools/make_icon.swift build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp build/icon_1024.png "$APP/Contents/Resources/six_1024.png"
sed "s/__VERSION__/$V/g" Info.plist > "$APP/Contents/Info.plist"
codesign --force -s "${SIGN:-Mantra Apps}" "$APP"
echo "built $APP (v$V)"
if [ "${NO_INSTALL:-0}" = "1" ]; then echo "not installed (NO_INSTALL=1)"; exit 0; fi
echo "This script does not install: the Mac installs the GitHub release (TAKEOVER.md, Install)."
