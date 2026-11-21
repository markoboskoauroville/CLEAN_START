#!/usr/bin/env python3
"""ax.py: drive Clean Start (Mantra) through Accessibility only (AXPress, no mouse, no focus). Used by the dummy tests.

  python3 tools/ax.py <pid> list                 every control: role, label, identifier
  python3 tools/ax.py <pid> press <identifier>   AXPress on the element with that AXIdentifier
  python3 tools/ax.py <pid> pressTitle <title>   AXPress on a button with that title (the updater's alert)
  python3 tools/ax.py <pid> status               the status lines (AXIdentifier "status" / "confirm.question")
Needs pyobjc (ApplicationServices) and Accessibility for the calling terminal.
"""
import sys
from ApplicationServices import (AXUIElementCreateApplication, AXUIElementCopyAttributeValue,
                                 AXUIElementPerformAction, AXIsProcessTrusted)


def attr(e, name):
    err, v = AXUIElementCopyAttributeValue(e, name, None)
    return v if err == 0 else None


def walk(e, depth=0, out=None):
    out = [] if out is None else out
    if depth > 40:
        return out
    out.append(e)
    for c in attr(e, "AXChildren") or []:
        walk(c, depth + 1, out)
    return out


def main():
    if not AXIsProcessTrusted():
        print("this terminal has no Accessibility permission"); sys.exit(3)
    pid, cmd = int(sys.argv[1]), sys.argv[2]
    app = AXUIElementCreateApplication(pid)
    els = walk(app)
    if cmd == "list":
        for e in els:
            role = attr(e, "AXRole")
            if role in ("AXButton", "AXCheckBox", "AXSwitch", "AXToggle"):
                print(f"{role:12} label={attr(e, 'AXDescription') or attr(e, 'AXTitle')!r:70} id={attr(e, 'AXIdentifier')!r} value={attr(e, 'AXValue')!r}")
    elif cmd in ("press", "pressTitle"):
        key = sys.argv[3]
        for e in els:
            hit = attr(e, "AXIdentifier") == key if cmd == "press" else (attr(e, "AXRole") == "AXButton" and attr(e, "AXTitle") == key)
            if hit:
                r = AXUIElementPerformAction(e, "AXPress")
                print(f"AXPress {key} -> {r}"); sys.exit(0 if r == 0 else 1)
        print(f"not found: {key}"); sys.exit(2)
    elif cmd == "status":
        for e in els:
            if attr(e, "AXIdentifier") in ("status", "confirm.question"):
                print(attr(e, "AXValue") or attr(e, "AXDescription"))


main()
