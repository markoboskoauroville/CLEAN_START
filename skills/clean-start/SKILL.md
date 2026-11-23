---
name: clean-start
description: Clean Start (Mantra), Marko's Mac app (repo CLEAN_START) with CLEAN START (every non-Apple item that starts by itself off for the next start), FULL START (NORMAL START until v6: back as it was before the first Clean, except his own switches) and a list of every startup item with its own switch; launchd, BTM database, login items, daemons, snapshot, dummy-only tests. Use for ANY Clean Start / startup items / login items / launch agents / launch daemons / clean boot / "start the Mac without anything" task.
---
# Clean Start (Mantra), asked by Marko on 21.11.2026

Shape: MANTRA_MANIFEST modules/skills-as-movies.md. The full module: MANTRA_MANIFEST modules/clean-start.md. The repo's own
TAKEOVER.md and LESSONS.md are the source of facts (read them first).

## SPACE
- **The app**: `/Applications/Clean Start (Mantra).app`, bundle id `com.mantra.cleanstart`; v7 installed on 23.11.2026 (v5 on 21.11.2026, release Latest, Fable score 9 of 10, the tenth is Marko's real press and restart).
- **The repo**: ~/Developer/CLEAN_START, https://github.com/markoboskoauroville/CLEAN_START (public, main, no README: TAKEOVER.md says all).
- **The state folder**: `~/Library/Application Support/Clean Start (Mantra)/` (snapshot.json, choices.json, backups/, log.txt).
- **The star row** `cleanstart` (group Mac), icon CLE / STA over the power symbol, black default look.

## CHARACTERS
| Character | Who / what | Can | Cannot / must not |
|---|---|---|---|
| **Marko** | the owner | presses CLEAN START and FULL START, switches single rows, restarts the Mac, is the tester | |
| **The session** | Claude | plans, briefs workers, reads TAKEOVER, scores, writes the documents | never presses CLEAN START or FULL START on real items; never builds on the Mac |
| **Workers** | Opus built it; Sonnet / Haiku for the rest | build, test with dummies, document | never touch a real item |
| **Queen** | the local AI (skill queen_skills/clean-start.md) | tell him what it is, open the app | never presses CLEAN START herself |
| **Apple's own items** | 835 on 21.11.2026 | | never listed as switchable, never touched (SIP is off on this Mac) |

## PLOT
1. Read ~/Developer/CLEAN_START/TAKEOVER.md and LESSONS.md.
2. Change code in the repo, push to main; GitHub Actions compiles and marks the release Latest (never gradlew/swiftc/build.sh on the Mac).
3. Install: `gh release download --repo markoboskoauroville/CLEAN_START --pattern app.zip -D <scratch> --clobber`, `ditto -x -k`, sign "Mantra Apps".
4. Test only in test mode with dummy plists in a scratch folder (`CLEANSTART_TEST_PREFIX`, `CLEANSTART_TEST_DIR`, `CLEANSTART_STATE_DIR`); look at the `would-run-*.sh` files, never run them on real items.
5. The real test is Marko's: press CLEAN START once, restart, look, press FULL START (administrator password), restart.

## RULES
- How each kind is switched: launch agents and daemons by `launchctl disable/enable` (gui/<uid> or system, one administrator prompt per apply for the system ones); Open at Login apps by System Events; system extensions, cron @reboot, login hooks, StartupItems are read only.
- The BTM database is readable without a password (NSKeyedArchiver; decode with own classes; only the current user's records and the root record).
- CLEAN writes the snapshot before changing anything and refuses if it cannot; reading never creates the state folder; his own switch wins in both modes.
- The mode is read item by item: CLEAN while anything FULL START would bring back is still off (v7). FULL START brings back whatever log.txt says this app switched off last and never back, plus the snapshot's "before" while its Clean is in force; a missing or broken snapshot falls back to the newest backup, then the log alone.
- A press is all or nothing: administrator step first (a refused password changes nothing); a missing Automation of System Events asks SWITCH THE REST or CANCEL before anything changes; every change is read back from launchd.
- Rows say ON / OFF, LOCKED, SETTINGS or SHOWN in words; a missing program is flagged "program missing" in amber.
- Nothing that runs now is stopped: every change is for the next start.
- Dummies never go in ~/Library/LaunchAgents (macOS raises a "Background Items Added" notification).
- Not proven: the real password dialog, real System Events changes, a real login after a Clean (Marko's test). The updater was proven v3 to v4 to v5 and keeps the "Mantra Apps" signature.
- Built under the Fable rule: Fable plans, workers build, Fable scores to 10 of 10 (modules/fable-plans-and-scores.md).

## HISTORY
- 21.11.2026: asked; v1 to v5 built and installed; Fable scored v2 7 of 10 (seven corrections), v5 9 of 10; documents, star row, Queen skill and hub written the same day.
- 22.11.2026: v6. Marko: "It should not kill ... iLok works. My audio plug-ins are working." Everything iLok / PACE (com.paceap.*, iLok, ldsvc; today com.paceap.eden.licensed daemon + agent) is KEPT on: never disabled by CLEAN START, switched on by CLEAN or NORMAL START if off (Engine.keepPatterns). Waves/UAD helpers listed, not added.
- 23.11.2026: v7. Marko: "I put it on full start, and it's again a clean start ... give two options, clean start, full start, and they actually work." Found: the CLEAN of 22.11 14:47 still in force (57 items off), no NORMAL press in log.txt after it (nothing logged before the admin prompt), and the v6 window said "Now: NORMAL START" because 6 items came back by themselves. v7: NORMAL START renamed FULL START; mode read item by item; log.txt ledger + backups so the "before" can never be lost; press and system labels logged before the prompt; window to the front before it; Open at Login read back; result list "Back on (n)". Run 45254640719 green, installed, dummy tests (clean, clean again, full; forced-overwrite; lost snapshot; broken snapshot) all passed. Waiting: Marko presses FULL START, password, restart.
