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
16. **21.11.2026, a score cannot reach 10 on what only Marko's hand proves.** The real administrator password dialog, real
    System Events changes and a real login after a Clean are his to press and restart; v5 stays at 9 of 10 and says so.
17. **21.11.2026, the master's first plan missed the order of a press.** It did not say the administrator step comes first;
    it was found only at scoring (lesson 10). A plan for anything that changes system state names what happens when the
    user cancels half way.
18. **22.11.2026, a Clean must not kill what authorises his work.** v1-v5 switched iLok/PACE off, so audio plug-ins would stop
    authorising after a Clean. From v6 anything matching the PACE patterns is KEPT on (never disabled, switched on if found off).
    A "turn everything off" tool needs a protected list from the first version; ask which licence helpers his work depends on.
19. **22.11.2026, the test lock must let a dummy carry a protected label.** To prove the keep rule without touching the real PACE
    daemon, dummies in the test folders may have a com.paceap.* label; real items stay locked. `--version` is not a flag: it opens the
    window (use `--status`).
20. **23.11.2026, the mode shown must be read item by item, and a press must leave a trace before it can hang.** Marko: "I put it
    on full start, and it's again a clean start." The CLEAN of 22.11.2026 14:47 was still in force (57 items off), log.txt had no
    NORMAL press after it, and v6's window said "Now: NORMAL START" in green because 6 items had come back on by themselves: the
    mode was "NORMAL unless every item is off". A press that waits for the administrator password wrote nothing before the
    prompt, so a press stuck behind a hidden prompt (or quit) leaves no trace. From v7: CLEAN while anything FULL START would
    bring back is still off; the press and the system labels are logged before the prompt; the window comes to the front first.
21. **23.11.2026, one snapshot is one point of failure.** The "before Clean" state lived only in snapshot.json; once a Clean was
    marked finished (or the file was lost or broken), a second CLEAN would have recorded "off" as the before. From v7 log.txt is a
    ledger: whatever this app switched off last and never back comes back with FULL START, and the newest backup stands in for
    a missing or broken snapshot. Tested with dummies: clean, clean again, full; snapshot forced inactive then CLEAN again;
    snapshot and backups deleted; snapshot made garbage: every dummy came back each time.
