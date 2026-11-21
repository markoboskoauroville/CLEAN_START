// Clean Start (Mantra): one window, CLEAN START or NORMAL START, and the list of everything that starts by itself.
// Marko, 21.11.2026 (momentaryupdates.md). What it is, how each source is switched, the snapshot: TAKEOVER.md.
//
// Command line (the same engine as the window):
//   --status                      JSON of every item and the mode, then exit
//   --clean | --normal            press the button headless (refused outside test mode unless --yes-real)
//   --set <key> on|off            one switch, remembered as his choice (same rule)
//   --skip-login-items            with --clean/--normal: switch the rest when Automation is missing (the window asks)
//   --shot <png> [--width N]      draw the window off screen into a PNG, every group open
// Test mode: CLEANSTART_TEST_PREFIX=<label prefix> (only labels with it are switched), CLEANSTART_TEST_DIR=<dir of dummy
// plists>, CLEANSTART_STATE_DIR=<dir> (snapshot and choices kept apart from the real ones), CLEANSTART_TEST_FRAME=x,y,w,h,
// CLEANSTART_TEST_SYSDIR=<dir> (dummies as system items: the root step), CLEANSTART_TEST_ROOT=cancel (refused password,
// simulated), CLEANSTART_TEST_FAIL=<label,...> (launchctl failure, simulated), CLEANSTART_TEST_PERMISSION=missing,
// CLEANSTART_TEST_LOGIN=1 (one fake Open at Login dummy), CLEANSTART_TEST_UPDATE=1 (the updater runs in test mode: no activation, the new copy is not opened).
import AppKit
import SwiftUI

let VERSION = 5
let APP_NAME = "Clean Start (Mantra)"
let RELEASES = "https://github.com/markoboskoauroville/CLEAN_START/releases/latest"

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let engine = Engine()
        let real = !engine.isTest
        let allowed = !real || args.contains("--yes-real")

        if args.contains("--status") {
            _ = NSApplication.shared
            print(statusJSON(engine.scan(), engine))
            exit(0)
        }
        if args.contains("--clean") || args.contains("--normal") || args.contains("--set") {
            _ = NSApplication.shared
            guard allowed else {
                print("Refused: outside test mode the command line needs --yes-real. Use the window instead.")
                exit(2)
            }
            let skip = args.contains("--skip-login-items")
            var o = Engine.Outcome()
            if args.contains("--clean") { o = engine.clean(skipLogins: skip) }
            else if args.contains("--normal") { o = engine.normal(skipLogins: skip) }
            else if let i = args.firstIndex(of: "--set"), i + 2 < args.count { o = engine.set(args[i + 1], on: args[i + 2] == "on") }
            o.lines.forEach { print($0) }
            if let q = o.confirm { print(q); print("(again with --skip-login-items to switch the rest)") }
            print(statusJSON(engine.scan(), engine))
            exit(0)
        }
        if let png = arg("--shot") {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let width = CGFloat(Double(arg("--width") ?? "") ?? 860)
            let ok = Shot.render(engine: engine, width: width, to: png)
            print(ok ? "shot \(png) width \(Int(width))" : "shot failed")
            exit(ok ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(engine: engine)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

func statusJSON(_ s: ScanResult, _ e: Engine) -> String {
    let items: [[String: Any]] = s.items.map { i in
        var d: [String: Any] = ["key": i.id, "name": i.name, "owner": i.owner, "kind": i.kind.rawValue, "mech": i.mech.rawValue,
                                "on": i.on, "switchable": i.switchable, "locked": i.locked, "path": i.path, "trigger": i.trigger]
        if let c = i.choice { d["choice"] = c }
        if !i.notes.isEmpty { d["notes"] = i.notes }
        if !i.warnings.isEmpty { d["warnings"] = i.warnings }
        return d
    }
    var counts: [String: Int] = [:]
    for i in s.items { counts[i.kind.rawValue, default: 0] += 1 }
    let d: [String: Any] = ["app": APP_NAME, "version": VERSION, "mode": s.mode.rawValue, "test": e.isTest,
                            "snapshotActive": s.snapshotActive, "stillOn": s.stillOn, "appleNotTouched": s.appleCount,
                            "automation": Int(s.automation), "counts": counts, "problems": s.problems,
                            "stateDir": e.store.dir.path, "items": items]
    let data = (try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine: Engine
    let model: Model
    var window: NSWindow!

    init(engine: Engine) {
        self.engine = engine
        self.model = Model(engine: engine)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = APP_NAME
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.contentMinSize = NSSize(width: 520, height: 420)
        w.backgroundColor = NSColor(Palette.ground)
        w.delegate = self
        let host = NSHostingView(rootView: ContentView(m: model))
        host.sizingOptions = []
        w.contentView = host
        let env = ProcessInfo.processInfo.environment
        if let f = env["CLEANSTART_TEST_FRAME"], engine.isTest {
            let n = f.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 { w.setFrame(NSRect(x: n[0], y: n[1], width: n[2], height: n[3]), display: true) }
        } else {
            w.center()
            w.setFrameAutosaveName("CleanStartMain")
        }
        window = w
        enforceOneTitle()
        if engine.isTest { w.orderFront(nil) } else { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        DispatchQueue.main.async { self.enforceOneTitle() }
        if engine.isTest { print("window \(w.windowNumber)"); fflush(stdout) }
        model.refresh()
        if !engine.isTest || env["CLEANSTART_TEST_UPDATE"] == "1" {
            Updater.quiet = engine.isTest
            Updater.checkAtStart()
        }
    }

    /// One title only (MANTRA_MANIFEST one-title-only.md): the app draws its own; the system's stays hidden in every state.
    func enforceOneTitle() {
        guard let w = window else { return }
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        if let bar = w.standardWindowButton(.closeButton)?.superview {
            for v in bar.subviews { if let t = v as? NSTextField, t.stringValue == w.title { t.isHidden = true } }
        }
    }
    func windowDidBecomeKey(_ n: Notification) { enforceOneTitle(); model.refresh() }
    func windowDidResignKey(_ n: Notification) { enforceOneTitle() }
    func windowDidResize(_ n: Notification) { enforceOneTitle() }
    func windowDidEnterFullScreen(_ n: Notification) { enforceOneTitle() }
    func windowDidExitFullScreen(_ n: Notification) { enforceOneTitle() }
    func windowWillClose(_ n: Notification) { DispatchQueue.main.async { NSApp.terminate(nil) } }   // the X quits the app
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(APP_NAME)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

/// Off-screen drawing of the window's content, every group open, the whole list (no scrolling).
enum Shot {
    static func render(engine: Engine, width: CGFloat, to path: String) -> Bool {
        let m = Model(engine: engine)
        m.scan = engine.scan()
        m.open = Set(Kind.allCases)
        let host = NSHostingView(rootView: ContentView(m: m, shotWidth: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        let h = max(400, host.fittingSize.height)
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: h), styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: h)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
