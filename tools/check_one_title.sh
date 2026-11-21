#!/bin/bash
# GUARD "one title only" (Marko 15.11.2026), copied from MANTRA_ROOM/mac/check_one_title.sh (MANTRA_MANIFEST
# modules/one-title-only.md). Run by build.sh before the compile, so the GitHub run fails when it breaks.
# Change from the original: the TOP check runs only when the app has a TOP toggle (this app has none; the original
# line failed every app without TopRow.float).
cd "$(dirname "$0")/../app" || exit 1
fail=0
for f in $(grep -l "NSWindow(\|NSPanel(" *.swift); do
  grep -q "titleVisibility = .hidden" "$f" || { echo "FAIL $f creates a window but never sets titleVisibility = .hidden"; fail=1; }
done
grep -q "func enforceOneTitle" *.swift || { echo "FAIL enforceOneTitle() is missing"; fail=1; }
for h in windowDidBecomeKey windowDidResize windowDidEnterFullScreen windowDidExitFullScreen; do
  grep -q "func $h.*enforceOneTitle" *.swift || { echo "FAIL $h does not call enforceOneTitle"; fail=1; }
done
if grep -q "TopRow.float" *.swift; then
  grep -A1 "static func float" *.swift | grep -q enforceOneTitle || { echo "FAIL the TOP toggle does not re-enforce the title"; fail=1; }
fi
grep -q "titleVisibility = .visible" *.swift && { echo "FAIL titleVisibility = .visible found"; fail=1; }
[ $fail = 0 ] && echo "one title only: OK"
exit $fail
