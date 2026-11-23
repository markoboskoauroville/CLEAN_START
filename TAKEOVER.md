# TAKEOVER: Clean Start (Mantra)

Public and unpromoted repository: no README and no description (MANTRA_MANIFEST repo-privacy.md). Everything about the
app is in this file. Requests word for word: `momentaryupdates.md`. Mistakes and what they taught: `LESSONS.md`.

## Status: v8 (23.11.2026, RESTART button); v7 installed 23.11.2026 (FULL START that really brings everything back)

v8 (23.11.2026, Marko: "next to clean start, full start, add another pipe, and give action button restart to restart the whole computer."):
third button RESTART (AX id `restart`) after CLEAN START | FULL START | . It asks inline in the window (`restart.question`
"Restart the Mac now? Open apps will be asked to save.", `restart.yes` RESTART, `restart.no` CANCEL), logs "RESTART pressed" to log.txt,
then `tell application "System Events" to restart` (apps asked to save); if System Events refuses, `/sbin/shutdown -r now` through the
administrator prompt. Command line `--restart` (test mode only unless --yes-real). Test mode never restarts: it writes
`would-restart.sh` into the state folder and a log line. Engine.restart(), Model.restartPressed/restartAnswer.


v7 (23.11.2026, Marko: "I put it on full start, and it's again a clean start. I cannot go back to the full start. Please
give two options, clean start, full start, and they actually work."). Found: the CLEAN of 22.11.2026 14:47 was still in
force (57 items off: 7 Open at Login apps, 32 agents, 18 daemons) and log.txt holds NO NORMAL press after it, so no press
ever got past the administrator step; and v6's window said "Now: NORMAL START" in green because 6 items had come back on
by themselves (iBoysoft, Path Finder launcher, arkaudiod, SoundSource, Little Snitch daemon, Pearcleaner helper). Fixed in v7,
see "FULL START (v7)" below. Waiting for Marko: press FULL START, give the administrator password, restart.


v6 (22.11.2026, Marko: "It should not kill ... iLok works. My audio plug-ins are working. Only that part you need to change."): everything of iLok / PACE Anti-Piracy is a protected KEPT group, see "iLok / PACE is KEPT" below. Before that, CLOSED 21.11.2026: v5 installed, release Latest, Fable score 9 of 10 (v2 scored 7; seven corrections). Waiting for Marko: (1) the real test,
CLEAN START, restart, look, FULL START, restart; (2) the root daemon `com.love.russia.plist` points at the missing
`/Users/markobosko/.start`; (3) whether the Path Finder and iBoysoft helpers stay on by default in a Clean (his cracked apps:
the app does not decide for him); (4) Queen's clean-start skill is installed (queen_skills/clean-start.md) but her chat
route gave 502, so it is not yet tried in her chat.

## What it is

A Mac app (Swift, macOS 14+, written for Marko's macOS 15 on Apple silicon) with one window:

- **CLEAN START**: every non-Apple thing that starts by itself is switched off for the next login and boot.
- **FULL START** (called NORMAL START until v6): everything comes back exactly as it was before the first CLEAN START, except
  what Marko switched himself; iLok / PACE always on.
- **The list** of everything that starts by itself, grouped by kind, each group a folder (name, count, one line saying
  what is inside). Each row: a switch (or SETTINGS for what macOS lets only System Settings switch), the name, the vendor
  or app it belongs to, the kind, when it starts, notes (also off in System Settings, running now), the plist path and the
  command it runs.
- His own switch in a row is remembered as **his choice** and wins in both modes: switched off stays off after FULL
  START, switched on stays on after CLEAN START. The row says "your choice: on/off, kept in both modes".
- Nothing that runs now is stopped: every change is for the next start. A row switched off while its program runs says
  so.
- Apple's own items are never listed as switchable and never touched; the window shows only their count
  ("Apple system items: 835, not touched" on 21.11.2026). SIP is off on this Mac, so this rule matters more.
- The window's X quits the app (no ON/OFF). Standard NSWindow, resizable on every edge, frame autosave, the app's own
  title once (system title hidden in every state, guarded in CI by `tools/check_one_title.sh`). Version `vN` top right,
  a click opens the latest release. Amber **PERMISSIONS** top right only while Automation of System Events is missing
  and there are Open at Login apps to switch; a click asks macOS once, then opens Privacy › Automation.
- It asks to update at start (kits/mac-updater, `Updater.checkAtStart()`), repo `markoboskoauroville/CLEAN_START`.
- It adds no startup item of its own and leaves no helper running.

## Where each source comes from, and how it is switched

| Group in the window | Read from | Switched by | Password |
|---|---|---|---|
| OPEN AT LOGIN | BTM database: type 0x2 (app) with the enabled bit | System Events: `delete (every login item whose path is …)`; back with `make login item … {path, hidden}` | no; needs Automation of System Events |
| LOGIN ITEMS INSIDE APPS | BTM type 0x4 (SMAppService login items; launchd shows them as "submitted by smd") | `launchctl disable/enable gui/<uid>/<bundle id>` | no |
| YOUR LAUNCH AGENTS | `~/Library/LaunchAgents/*.plist` | `launchctl disable/enable gui/<uid>/<label>` | no |
| LAUNCH AGENTS FOR EVERY USER | `/Library/LaunchAgents/*.plist` | same, in your gui domain (for you only) | no |
| AGENTS INSIDE APPS | BTM type 0x8 without the legacy bit | `launchctl … gui/<uid>/<label>` | no |
| LAUNCH DAEMONS | `/Library/LaunchDaemons/*.plist` | `launchctl disable/enable system/<label>`, all of one apply in ONE `do shell script … with administrator privileges` | once per apply |
| DAEMONS INSIDE APPS | BTM type 0x10 without the legacy bit (root user record) | same as daemons | once per apply |
| SYSTEM EXTENSIONS | `systemextensionsctl list` | read only, SETTINGS opens Login Items & Extensions | – |
| OTHER STARTERS | `crontab -l` @reboot lines, LoginHook/LogoutHook in com.apple.loginwindow, /Library/StartupItems | read only, the row says how to remove it | – |
| TEST DUMMIES | `$CLEANSTART_TEST_DIR` (test mode only) | `launchctl … gui/<uid>/<label>` | no |

State of a launchd row: `launchctl print-disabled gui/<uid>` / `system` first (`disabled`/`true` = off), else the plist's
`Disabled` key, else on. Read at launch, after every change and whenever the window becomes key. The mode shown is read
from that real state (v7: CLEAN while anything FULL START would switch back on is still off, else FULL; see FULL START (v7)).
Until v6: CLEAN when every switchable item is off except his ON choices, else NORMAL (and if a Clean is in
force but items came back on, the line says how many).

The BTM database is `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v<N>.btm` (the newest N), readable
by every user, an NSKeyedArchiver archive (classes Storage, ItemRecord, BTMUserSettings). The app decodes it with its own
classes (`BTMStorage`, `BTMItem`, Engine.swift). Records are keyed by the user's GeneratedUID (`dscl . -read /Users/<me>
GeneratedUID`); daemons sit under `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE`. Disposition bits: 1 enabled, 2 allowed (the
switch in System Settings), 4 hidden, 8 notified. Type bits: 0x2 app, 0x4 login item, 0x8 agent, 0x10 daemon, 0x20
developer group, 0x40 Spotlight, 0x800 Quick Look, 0x10000 legacy (a plist file). It also gives the vendor names.

## iLok / PACE is KEPT (v6, 22.11.2026)

An item is KEPT when its label, plist path, name, vendor or command contains (case-insensitive) `paceap`, `ilok`, `pace anti-piracy`,
`paceantipiracy` or `ldsvc` (`Engine.keepPatterns`, so future PACE versions are covered). On this Mac: the daemon
`com.paceap.eden.licensed` (/Library/LaunchDaemons) and the agent `com.paceap.eden.licensed.agent` (/Library/LaunchAgents), both
ON on 22.11.2026; the PACEAntiPiracy folder in /Library/Application Support; no PACE system extension or kext. A KEPT row shows the word
KEPT (green) instead of ON, with a note; if found OFF it shows OFF (amber). CLEAN START never disables it and switches it ON if it is off;
FULL START switches it ON if it is off. Rule in `Engine.target`: a KEPT item is always on in both presses (his row switch still works
at once, but the next press puts it back on). KEPT items do not count in the CLEAN/FULL mode reading; the "Now" line says how many are
kept. Test mode: a dummy with such a label in the test folders is switchable, real PACE items stay locked (shown KEPT). `would-run-*.sh`
carry a `# KEPT ON` line for them. Not added (only listed): Waves `com.waves.wls`, `com.waves.central.InstlHelper`, Universal Audio
`com.uaudio.uac.launch-helper`, `com.uaudio.bsd.helper` (hardware helpers, no licence daemon), Steinberg/NI/Arturia/Plugin Alliance: none found.
Decision for Marko: whether the Waves licence agent (`com.waves.wls`) joins KEPT.

## What cannot be switched, and why

- **The "allowed" switch of System Settings › Login Items** (BTM disposition bit 2): Apple has no API for another app's
  item, and `sfltool` only dumps or resets. Clean Start does not need it: launchd's own off list is checked before any
  job starts. Rows where System Settings is already off say "also off in System Settings › Login Items".
- **System extensions** (drivers, network, camera): only System Settings may switch them. Read only, SETTINGS button.
- **Agents limited to the LoginWindow or another non-Aqua session** (e.g. RealVNC prelogin): they run outside the user's
  gui domain, so `gui/<uid>` does not reach them. Read only, with that reason.
- **cron @reboot, login hooks, StartupItems**: shown read only; none exist on this Mac (21.11.2026). The root crontab
  cannot be read without a password and is not listed.

## A press is all or nothing (v3, from Fable's score of v2)

Order of every apply (`Engine.apply`): (1) if Open at Login apps would change and Automation of System Events is
missing, NOTHING changes and the window asks "Switch the rest and leave them as they are?" (SWITCH THE REST | CANCEL;
`--skip-login-items` on the command line); (2) the administrator step FIRST, one prompt for every system item: refused
or failed = nothing at all is changed, the status line says so; (3) your launchd domain; (4) Open at Login apps. Every
launchd change is read back from `launchctl print-disabled` before it is counted: the status line says "N of M switched;
K did not: name (reason)", green when all went well, amber when not, and the mode shown is read back from launchd.
CLEAN writes the snapshot before the prompt but marks it active only once something really changed; FULL leaves it
active until every item is back.

A row whose program (or the script given to a shell or interpreter) is not on disk says "program missing: <path>" in
amber; nothing is changed or removed. On this Mac: the daemon com.love.russia.plist runs `/bin/bash /Users/markobosko/.start`
as root with KeepAlive, and that file does not exist.

The left column of every row says what the row is, in words that keep their colour in an inactive window: a switch with
ON (green) / OFF (grey) under it; LOCKED (test mode, amber); SETTINGS or SHOWN with on/off for read-only rows.

## FULL START (v7, 23.11.2026)

- **The mode is read item by item** (`Engine.scan`, step 8): CLEAN while anything FULL START would switch back on is still
  off (`heldOff` > 0, each such row says "off by CLEAN START; FULL START switches it back on"); FULL when FULL START would
  change nothing. The "Now" line says how many are off and how many came back on by themselves. v6 called it NORMAL as soon
  as one item came back on.
- **What "as it was" means** (`Engine.restoreBase`, `Base.wasOn`): (1) every item whose LAST action by this app in log.txt
  was `disable` / `remove` comes back on (the ledger, `Store.ledger`), whatever a later snapshot says; (2) otherwise
  snapshot.json's `wasOn`, but only while its Clean is in force (`active: true`); (3) if snapshot.json is missing or broken,
  the newest readable file in backups/ (its Clean counts as in force when the last press in log.txt was a CLEAN); (4) with
  neither, log.txt alone. His own switch (choices.json) still wins; KEPT items are always on.
- **The "before" cannot be lost**: a second CLEAN while a Clean is in force only adds new items (as before); a fresh CLEAN
  counts as ON every item the ledger says this app left off, so a CLEAN on top of an unfinished Clean never turns "was on"
  into "was off". A broken snapshot.json is moved to `backups/snapshot-broken-<time>.json` by a successful FULL START.
- **Every item is in the log by name**: `press CLEAN|FULL: N to switch`, `system: asking for the administrator password,
  N items: enable <label>, ...` (written BEFORE the prompt, so a press that hangs at the password is visible), then per item
  `system enable|disable <label> -> ok|still off` (read back), `gui enable|disable <label> -> 0`, `login add|remove <path>
  -> ok|not read back` (read back from System Events), and `FULL START n changed, k failed`.
- **The window comes to the front** before the administrator prompt (`Engine.bringToFront`).
- **Result list**: "FULL START: n of m switched back for the next start. Restart the Mac ...", then "Back on (n): names",
  and every one that did not, with its reason (amber).
- Command line: `--full` (`--normal` still accepted). `--status` gives `heldOff` and `restoreFrom`. AX id of the button:
  `full`, "Full start: bring back everything that was on before the first clean start". Test mode writes
  `would-run-full.sh` from the REAL state folder's base (read only), so it shows what FULL START will do on this Mac.

## The snapshot (format 1)

`~/Library/Application Support/Clean Start (Mantra)/` (made on the first write; reading never creates it):

- `snapshot.json`: `{format, app, appVersion, created, active, lastClean, lastNormal, items: {<key>: {name, mech, label,
  path, wasOn, hidden}}}`. Keys: `gui:<label>`, `system:<label>`, `login:<app path>`. `mech` is gui · system · loginItem.
  `hidden` only for Open at Login apps (read from System Events at Clean time).
- `choices.json`: `{<key>: true|false}`, his own switches.
- `backups/snapshot-YYYY-MM-DD-HHMMSS.json`: a copy at every CLEAN press.
- `log.txt`: every command and its result.

Rules: CLEAN writes the snapshot BEFORE changing anything; if the snapshot cannot be written or read, CLEAN refuses and
changes nothing. While a Clean is in force (`active: true`) a second CLEAN never overwrites the "before" state: only items
new since then are added. FULL restores every item (see FULL START (v7)), then sets `active: false` (the file stays;
the field is still called `lastNormal`). The next CLEAN after a FULL captures a fresh "before". Open at Login apps taken out by Clean stay listed from the
snapshot (switched off) so they can be switched back one by one. All of it survives quitting, updating and restarting.

## Command line and test mode

Same engine as the window (`app/App.swift` header):

    "/Applications/Clean Start (Mantra).app/Contents/MacOS/Clean Start (Mantra)" --status
    … --clean | --full | --restart | --set <key> on|off     (refused outside test mode unless --yes-real)
    … --shot out.png --width 860                    (off-screen drawing, every group open, the whole list)

Test mode (never touches a real item):

    export CLEANSTART_TEST_PREFIX=com.mantra.cleanstart.testdummy.   # only labels with this prefix are switched
    export CLEANSTART_TEST_DIR=<folder with dummy plists>            # listed as TEST DUMMIES, gui domain
    export CLEANSTART_STATE_DIR=<folder>                             # snapshot/choices apart from the real ones
    export CLEANSTART_TEST_FRAME=1500,420,860,800                    # window frame (MacBook screen), no autosave
    export CLEANSTART_EXPAND=1                                       # every group open

More test hooks (v3+, test mode only): `CLEANSTART_TEST_SYSDIR` (dummy plists treated as system items, so the root step
is exercised), `CLEANSTART_TEST_ROOT=cancel` (a refused password, simulated), `CLEANSTART_TEST_FAIL=<label,...>` (a
launchctl failure, simulated), `CLEANSTART_TEST_PERMISSION=missing` (PERMISSIONS shown; its click only writes what it
would open), `CLEANSTART_TEST_LOGIN=1` (one fake Open at Login dummy; System Events is never called in test mode),
`CLEANSTART_TEST_UPDATE=1` (the updater runs: no activation, the installed copy is not reopened).
`python3 tools/ax.py <pid> list|press <id>|status` drives the window by AXPress only (no mouse, no focus).

AX labels and identifiers: `clean` "Clean start: switch every item off for the next start" · `full` "Full start: bring
back everything that was on before the first clean start" · `version` "Version N, open the latest release" · `permissions` "Permissions: allow Automation
of System Events" · `group.<kind>` "<Group>, N items, M on, open/closed" · `item.<key>` (AXCheckBox) "<name> starts by
itself" · `settings.<key>` "Open System Settings for <name>" · `confirm.yes` "Switch the rest, leave the Open at Login
apps as they are" · `confirm.no` "Cancel, change nothing" · status lines `status`, the question `confirm.question`.
The updater's alert: `action-button-1` Update, `action-button-2` Later.

In test mode everything real is listed and locked, the updater does not run, the window is not activated, and CLEAN /
FULL also write `would-run-clean.sh` / `would-run-full.sh` into the state folder: the exact commands a real press
would run on the real items (gui launchctl lines, the System Events scripts, the one root command), NOT run.

Dummies live in a scratch folder, not in ~/Library/LaunchAgents: a new plist there makes macOS post a "Background Items
Added" notification on Marko's screen. Each dummy: Label `com.mantra.cleanstart.testdummy.<x>`, ProgramArguments
`/usr/bin/true`, RunAtLoad. `launchctl enable` at the end leaves "<label> => enabled" lines in launchd's override list
(they cannot be removed without root and do nothing).

## Build and install

Compiled only by GitHub Actions (`.github/workflows/mac-swift.yml`, the MANTRA_MANIFEST template with APP set) on every
push to main: `build.sh` runs the one-title guard, swiftc, draws the icon (`tools/make_icon.swift`), signs ad hoc; the
workflow zips it and makes release vN marked Latest. NEVER build on the Mac. Install:

    gh release download --repo markoboskoauroville/CLEAN_START --pattern app.zip -D <scratch> --clobber
    ditto -x -k <scratch>/app.zip /Applications && codesign --force -s "Mantra Apps" "/Applications/Clean Start (Mantra).app"

From v2 on, a running copy asks to update by itself. Proven v3 → v4 and v4 → v5 (21.11.2026): the question shown, Update
pressed by AXPress, the installed copy became the new version, signed "Mantra Apps" (leaf 3411F707…), bundle id kept.

Icon: CLE / STA over the power symbol on the black tile (icon/README.md, icon/six_1024.png). Bundle id
`com.mantra.cleanstart`. Version: `let VERSION = N` in app/App.swift, whole numbers.

## Files

- `app/App.swift`: VERSION, command line, window, one-title, off-screen shot.
- `app/Engine.swift`: reading every source, the BTM decoder, switching, snapshot and choices.
- `app/UI.swift`: the SwiftUI page (CAMERA language: words, colour is the state).
- `app/Updater.swift`: kits/mac-updater, repo set.
- `tools/check_one_title.sh`, `tools/make_icon.swift`, `build.sh`, `Info.plist`.

## Found on this Mac, 21.11.2026

Open at Login 8 · login items inside apps 5 · your launch agents 23 · launch agents for every user 12 · launch daemons 20 ·
daemons inside apps 1 · system extensions 12 (read only) · other 0 · Apple items 835 (not touched). Two of
~/Library/LaunchAgents (com.google.keystone.agent, .xpcservice) are empty plists. One daemon, `com.love.russia.plist`
(runs /bin/bash as root at boot, no vendor), is worth a look by Marko.

## Not yet proven

- A real CLEAN on Marko's real items was pressed (21.11 and 22.11.2026, both logged fine); a real NORMAL once (22.11.2026
  05:40, fine). FULL START v7 on the real items and a real login after it: Marko's press. Only dummies were switched by sessions.
- The real administrator prompt (`do shell script … with administrator privileges`) was never shown; its refusal was
  simulated in test mode and the exact command written to would-run-root.sh / would-run-clean.sh.
- System Events delete/re-add of Open at Login apps: the scripts were written, never run. Reading the list through
  System Events (paths and hidden flags) matched the BTM list exactly.
- That `launchctl disable gui/<uid>/<id>` stops an SMAppService login item at the next login (launchd documents the off
  list for every job it loads; not watched across a login here).
