# LESSONS: Clean Start (Mantra)

Every mistake met on the way, and what it taught. Newest last.

1. **21.11.2026, the one-title guard copied from MANTRA_ROOM fails every app without TOP.** Its line
   `grep -q TopRow.float && … || FAIL` runs FAIL when the app has no TopRow.float. Our copy checks TOP only when TOP exists.
2. **21.11.2026, the BTM database is readable without a password.** `/private/var/db/com.apple.backgroundtaskmanagement/
   BackgroundItems-v13.btm` is -rw-r--r--, so `sfltool dumpbtm` (needs root) is not needed. It is an NSKeyedArchiver
   archive: decode with your own NSCoding classes mapped by `setClass(_:forClassName:)`; PropertyListSerialization alone
   gives opaque UID objects.
3. **21.11.2026, BTM keeps records of old users** (eleven GeneratedUIDs on this Mac after migrations). Only the current
   user's GeneratedUID and the root record are read, or old items appear twice.
4. **21.11.2026, the Automation check must not ask.** `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)`
   returns -600 while System Events is not running; start it in the background (`open -g -j`) and check again, never
   send an Apple event to find out (that would raise the dialog).
5. **21.11.2026, dummies outside ~/Library/LaunchAgents.** A new plist there raises macOS's "Background Items Added"
   notification on Marko's screen. Test plists live in a scratch folder given by CLEANSTART_TEST_DIR; the real
   `launchctl disable/enable gui/<uid>/<label>` path is exercised the same way.
6. **21.11.2026, empty plists exist.** Two Google keystone agents are `{}`: say "empty plist", not "could not be read".
7. **21.11.2026, reading must not create.** v1 created the state folder on `--status`; from v2 it is made on the first write.
8. **21.11.2026, off-screen SwiftUI switches draw without the accent colour.** `.tint(Palette.green)` makes ON green in
   the shot and the window alike.
9. **21.11.2026, `sips -c --cropOffset` does not crop from the top as expected** when slicing tall screenshots; PIL crops
   did. Look at the top of a shot before judging it.
10. **21.11.2026 (Fable's score 7/10 for v2), half a press is worse than none.** v2 switched the gui items first and asked
    for the password after: a cancel left Marko half clean. Now the administrator step comes first, a missing permission is
    asked about before anything changes, and every change is read back from launchd before it is counted.
11. **21.11.2026, a test mode must not hide the updater.** v2 skipped the updater in test mode and activated itself in real
    mode, so the update could not be proven without taking focus. From v3 `CLEANSTART_TEST_UPDATE=1` runs it quietly; the
    proof had to go v3 → v4 instead of v2 → v3.
12. **21.11.2026, the main queue is not served while NSAlert.runModal runs.** A `DispatchQueue.main.asyncAfter` print never
    came; a Timer added to `.modalPanel` does. The alert itself is placed by AppKit on the main screen (the BenQ).
13. **21.11.2026, read-only beats locked.** v4 showed LOCKED on system extensions in test mode; a row that has no switch
    shows SETTINGS/SHOWN in every mode.
14. **21.11.2026, inactive windows grey every switch.** The state is said in words beside the switch (ON green, OFF grey),
    which keep their colour.
15. **21.11.2026, zsh does not split a command kept in a variable** (`AX="python3 ax.py"; $AX` fails): use a function.
