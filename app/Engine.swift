// Engine.swift: everything that starts by itself on this Mac, read and switched.
//
// Sources (macOS 15): launchd plists in ~/Library/LaunchAgents, /Library/LaunchAgents, /Library/LaunchDaemons;
// the Background Task Management database (/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm,
// readable by every user) for "Open at Login" apps, login items and agents/daemons inside app bundles, and for which
// vendor each item belongs to; system extensions (systemextensionsctl); cron @reboot, login hooks, /Library/StartupItems.
//
// Switching: launchd jobs with `launchctl disable|enable gui/<uid>/<label>` (no password) and `system/<label>` (one
// administrator prompt per apply, all commands in one call). That changes only the next login or boot: nothing that runs
// now is stopped. "Open at Login" apps are removed and re-added through System Events (Automation permission), their path
// and hidden flag kept in the snapshot. What has no honest switch (system extensions, login hooks, cron) is shown
// read-only with the place where macOS switches it.
//
// Apple's own items (/System/Library, labels com.apple.*) are never listed as switchable and never touched.
import AppKit
import Carbon

// MARK: - Model

enum Kind: String, Codable, CaseIterable {
    case test, openAtLogin, appLoginItem, userAgent, allUsersAgent, appAgent, daemon, appDaemon, sysExt, other

    var title: String {
        switch self {
        case .test: return "TEST DUMMIES"
        case .openAtLogin: return "OPEN AT LOGIN"
        case .appLoginItem: return "LOGIN ITEMS INSIDE APPS"
        case .userAgent: return "YOUR LAUNCH AGENTS"
        case .allUsersAgent: return "LAUNCH AGENTS FOR EVERY USER"
        case .appAgent: return "AGENTS INSIDE APPS"
        case .daemon: return "LAUNCH DAEMONS"
        case .appDaemon: return "DAEMONS INSIDE APPS"
        case .sysExt: return "SYSTEM EXTENSIONS"
        case .other: return "OTHER STARTERS"
        }
    }
    var about: String {
        switch self {
        case .test: return "Dummy agents made by a test (they run /usr/bin/true). Only these are switched in test mode."
        case .openAtLogin: return "Apps that open when you log in. Switched through System Events; the path and the hidden flag are kept to put them back."
        case .appLoginItem: return "Small helpers an app registered to start at login (SMAppService). Switched by launchd's own off list."
        case .userAgent: return "~/Library/LaunchAgents: start when you log in, only for you."
        case .allUsersAgent: return "/Library/LaunchAgents: start at every login. Switched for you only, no password."
        case .appAgent: return "Background agents an app registered from inside its bundle. Switched by launchd's own off list."
        case .daemon: return "/Library/LaunchDaemons: start at boot, before anyone logs in. Switching them asks for your password once."
        case .appDaemon: return "Root helpers an app registered from inside its bundle. Switching them asks for your password once."
        case .sysExt: return "Drivers, network and camera extensions. macOS lets only System Settings switch them, so they are shown, not switched."
        case .other: return "cron @reboot lines, login hooks and /Library/StartupItems. Shown so nothing is hidden; edit them by hand."
        }
    }
    var short: String {
        switch self {
        case .test: return "test agent"
        case .openAtLogin: return "open at login"
        case .appLoginItem: return "login item"
        case .userAgent, .allUsersAgent: return "launch agent"
        case .appAgent: return "app agent"
        case .daemon: return "launch daemon"
        case .appDaemon: return "app daemon"
        case .sysExt: return "system extension"
        case .other: return "other"
        }
    }
}

enum Mech: String, Codable { case gui, system, loginItem, readOnly }

struct StartItem: Identifiable {
    var id: String              // gui:<label> · system:<label> · login:<path> · ro:<...>
    var name: String
    var owner: String
    var kind: Kind
    var mech: Mech
    var label: String
    var path: String
    var runs: String = ""
    var trigger: String = ""
    var on: Bool = true
    var notes: [String] = []
    var warnings: [String] = []   // amber: something is wrong with the item itself (program missing)
    var readOnlyWhy: String? = nil
    var settingsURL: String? = nil
    var hidden: Bool = false
    var running: Bool = false
    var locked: Bool = false    // test mode: a real item, never touched
    var choice: Bool? = nil     // Marko's own switch, remembered
    var keep = false            // iLok / PACE Anti-Piracy: always on, in a Clean too (KEPT)
    var switchable: Bool { mech != .readOnly }
    var changeable: Bool { switchable && !locked }
}

enum Mode: String { case clean = "CLEAN START", full = "FULL START" }

struct ScanResult {
    var items: [StartItem] = []
    var appleCount = 0
    var mode: Mode = .full
    var heldOff = 0              // items CLEAN START holds off that FULL START brings back (the real mode: >0 = CLEAN)
    var restoreFrom = ""         // where FULL START takes "as it was" from: snapshot.json, a backup, or the log
    var snapshotActive = false
    var snapshotDate: String? = nil
    var keptCount = 0            // iLok / PACE items, always on
    var stillOn = 0              // items that would keep starting although CLEAN is set
    var automation: OSStatus = noErr
    var problems: [String] = []
    var forcePermission = false   // test flag CLEANSTART_TEST_PERMISSION=missing
    var groups: [Kind] { Kind.allCases.filter { k in items.contains { $0.kind == k } } }
    var needsAutomation: Bool {
        forcePermission || items.contains { $0.mech == .loginItem && $0.changeable } && automation != noErr
    }
}

// MARK: - Snapshot and choices (~/Library/Application Support/Clean Start (Mantra)/)

struct SnapEntry: Codable {
    var name: String
    var mech: Mech
    var label: String
    var path: String
    var wasOn: Bool
    var hidden: Bool?
}

struct Snapshot: Codable {
    var format = 1
    var app = APP_NAME
    var appVersion = VERSION
    var created: String
    var active: Bool
    var lastClean: String?
    var lastNormal: String?
    var items: [String: SnapEntry]
}

final class Store {
    let dir: URL
    init(dir: URL) { self.dir = dir }
    /// Made on the first write only: reading the state never creates anything.
    func ensureDir() {
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("backups"), withIntermediateDirectories: true)
    }
    var snapURL: URL { dir.appendingPathComponent("snapshot.json") }
    var choicesURL: URL { dir.appendingPathComponent("choices.json") }

    enum SnapRead { case none, ok(Snapshot), broken(String) }
    func readSnapshot() -> SnapRead {
        guard FileManager.default.fileExists(atPath: snapURL.path) else { return .none }
        do { return .ok(try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: snapURL))) }
        catch { return .broken("\(error)") }
    }
    func write(_ s: Snapshot) throws {
        ensureDir()
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(s).write(to: snapURL, options: .atomic)
    }
    func backup() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let to = dir.appendingPathComponent("backups/snapshot-\(f.string(from: Date())).json")
        try? FileManager.default.copyItem(at: snapURL, to: to)
    }
    func choices() -> [String: Bool] {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: choicesURL))) ?? [:]
    }
    func saveChoices(_ c: [String: Bool]) {
        ensureDir()
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(c).write(to: choicesURL, options: .atomic)
    }
    /// The newest readable copy in backups/ (used when snapshot.json is missing or broken).
    func newestBackup() -> (Snapshot, String)? {
        let b = dir.appendingPathComponent("backups")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: b.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted().reversed()
        for n in names {
            if let s = try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: b.appendingPathComponent(n))) { return (s, "backups/\(n)") }
        }
        return nil
    }
    /// What the app itself last did to each item, read from log.txt (v7, 23.11.2026): key -> on (true) / off (false).
    /// An item whose last action by this app was "disable" or "remove" is held off by the app, and FULL START brings it
    /// back whatever a later snapshot says. Lines: "gui enable|disable <label> -> 0", "system enable|disable <label> -> ok"
    /// (from v7), "login add|remove <path> -> ok". Before v7 system lines named no labels ("system N items -> ok").
    func ledger() -> [String: Bool] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("log.txt"), encoding: .utf8) else { return [:] }
        var last: [String: Bool] = [:]
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard let sp = line.firstIndex(of: " "), let arrow = line.range(of: " -> ", options: .backwards) else { continue }
            let body = String(line[line.index(after: sp)..<arrow.lowerBound])
            let result = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            for (prefix, mech, on) in [("gui enable ", "gui", true), ("gui disable ", "gui", false),
                                       ("system enable ", "system", true), ("system disable ", "system", false),
                                       ("login add ", "login", true), ("login remove ", "login", false)] {
                guard body.hasPrefix(prefix) else { continue }
                let subject = String(body.dropFirst(prefix.count))
                guard !subject.isEmpty else { break }
                let ok = mech == "gui" ? result == "0" : result == "ok"
                if ok { last[mech + ":" + subject] = on }
                break
            }
        }
        return last
    }

    /// True when the last press written in log.txt was a CLEAN START that changed something (a Clean is in force).
    func lastPressWasClean() -> Bool {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("log.txt"), encoding: .utf8) else { return false }
        for raw in text.split(separator: "\n").reversed() {
            if raw.contains(" CLEAN START ") && !raw.contains("aborted") { return true }
            if raw.contains(" NORMAL START ") || raw.contains(" FULL START ") { if !raw.contains("aborted") && raw.contains(" 0 failed") { return false } }
        }
        return false
    }

    func log(_ s: String) {
        ensureDir()
        let line = "\(stamp()) \(s)\n"
        let u = dir.appendingPathComponent("log.txt")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: u) }
    }
}

func stamp() -> String { ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]) }

// MARK: - Small helpers

@discardableResult
func sh(_ exe: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    p.standardOutput = pipe; p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func asq(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

/// AppleScript always on the main thread (NSAppleScript is not thread safe).
func appleScript(_ src: String) -> (ok: Bool, result: NSAppleEventDescriptor?, error: String?) {
    var out: (Bool, NSAppleEventDescriptor?, String?) = (false, nil, nil)
    let work = {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err { out = (false, nil, (err[NSAppleScript.errorMessage] as? String) ?? "\(err)") }
        else { out = (true, r, nil) }
    }
    if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    return out
}

/// Automation permission for System Events, asked of macOS WITHOUT showing a dialog.
/// noErr granted · -1744 not asked yet · -1743 refused · -600 System Events not running.
func automationStatus() -> OSStatus {
    var addr = AEAddressDesc()
    let bid = "com.apple.systemevents"
    let made = bid.withCString { p in AECreateDesc(DescType(typeApplicationBundleID), p, Int(strlen(p)), &addr) }
    guard made == noErr else { return OSStatus(made) }
    defer { AEDisposeDesc(&addr) }
    return AEDeterminePermissionToAutomateTarget(&addr, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
}

func noApp(_ s: String) -> String { s.hasSuffix(".app") ? String(s.dropLast(4)) : s }

/// The outermost app in a path: "/Applications/Zoom.app/Contents/.../ZoomUpdater" -> "Zoom".
func appName(inPath p: String) -> String? {
    guard let r = p.range(of: ".app/") ?? (p.hasSuffix(".app") ? p.range(of: ".app", options: .backwards) : nil) else { return nil }
    return (String(p[..<r.lowerBound]) as NSString).lastPathComponent
}

/// System Events must run before macOS can say whether the permission is there; it is a faceless helper, opened in the background.
func automationStatusStartingSystemEvents() -> OSStatus {
    var st = automationStatus()
    if st == OSStatus(procNotFound) {
        sh("/usr/bin/open", ["-g", "-j", "/System/Library/CoreServices/System Events.app"])
        for _ in 0..<20 where st == OSStatus(procNotFound) { usleep(150_000); st = automationStatus() }
    }
    return st
}

func vendor(fromLabel l: String) -> String {
    let parts = l.split(separator: ".")
    guard parts.count >= 2 else { return l }
    let generic: Set<String> = ["com", "org", "net", "io", "at", "us", "sh", "pro", "ch", "de", "community", "homebrew"]
    let v = generic.contains(String(parts[0])) ? parts[1] : parts[0]
    return v.prefix(1).uppercased() + v.dropFirst()
}

/// The program of a launchd job, or the script an interpreter is told to run, when it is not on disk. Never changes anything.
func missingProgram(_ program: String, _ args: [String], home: String) -> String? {
    let fm = FileManager.default
    if program.hasPrefix("/") && !fm.fileExists(atPath: program) { return program }
    let base = (program as NSString).lastPathComponent
    let shells: Set<String> = ["bash", "sh", "zsh", "dash", "ksh", "csh", "tcsh", "perl", "ruby", "node", "osascript", "php"]
    guard shells.contains(base) || base.hasPrefix("python") else { return nil }
    let rest = Array(args.dropFirst())
    if rest.contains("-c") || rest.contains("-e") || rest.contains("-m") { return nil }   // inline code or a module
    guard let script = rest.first(where: { !$0.hasPrefix("-") }) else { return nil }
    let path = script.hasPrefix("~/") ? home + script.dropFirst(1) : script
    guard path.hasPrefix("/") else { return nil }
    return fm.fileExists(atPath: path) ? nil : script
}

// MARK: - Background Task Management database

@objc(CSBTMItem) final class BTMItem: NSObject, NSCoding {
    var type = 0, disposition = 0
    var name: String?, identifier: String?, developerName: String?, container: String?
    var bundleIdentifier: String?, executablePath: String?
    var url: URL?
    required init?(coder c: NSCoder) {
        type = c.decodeInteger(forKey: "type")
        disposition = c.decodeInteger(forKey: "disposition")
        name = c.decodeObject(forKey: "name") as? String
        identifier = c.decodeObject(forKey: "identifier") as? String
        developerName = c.decodeObject(forKey: "developerName") as? String
        container = c.decodeObject(forKey: "container") as? String
        bundleIdentifier = c.decodeObject(forKey: "bundleIdentifier") as? String
        executablePath = c.decodeObject(forKey: "executablePath") as? String
        url = c.decodeObject(forKey: "url") as? URL
        super.init()
    }
    func encode(with coder: NSCoder) {}
    var enabled: Bool { disposition & 1 != 0 }
    var allowed: Bool { disposition & 2 != 0 }
    var legacy: Bool { type & 0x10000 != 0 }
    /// "8.com.foo.bar" -> "com.foo.bar"
    var label: String? {
        guard let id = identifier, let dot = id.firstIndex(of: "."), Int(id[..<dot]) != nil else { return identifier }
        return String(id[id.index(after: dot)...])
    }
    var urlPath: String? {
        guard let url else { return nil }
        let p = url.path
        return p.isEmpty ? nil : p
    }
}

@objc(CSBTMStorage) final class BTMStorage: NSObject, NSCoding {
    var items: [String: [BTMItem]] = [:]
    required init?(coder c: NSCoder) {
        if let d = c.decodeObject(forKey: "itemsByUserIdentifier") as? NSDictionary {
            for (k, v) in d {
                if let k = k as? String, let a = v as? NSArray { items[k] = a.compactMap { $0 as? BTMItem } }
            }
        }
        super.init()
    }
    func encode(with coder: NSCoder) {}
}

@objc(CSBTMNothing) final class BTMNothing: NSObject, NSCoding {
    required init?(coder c: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}

struct BTM {
    var user: [BTMItem] = []
    var root: [BTMItem] = []
    var byPlist: [String: BTMItem] = [:]
    var byId: [String: BTMItem] = [:]
    var problem: String?

    static let rootUser = "FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE"

    static func load() -> BTM {
        var b = BTM()
        let dir = "/private/var/db/com.apple.backgroundtaskmanagement"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix("BackgroundItems-v") && $0.hasSuffix(".btm") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) > (Int($1.filter(\.isNumber)) ?? 0) }
        guard let f = files.first, let data = FileManager.default.contents(atPath: "\(dir)/\(f)") else {
            b.problem = "The Background Task Management database could not be read; login items inside apps are not listed."
            return b
        }
        do {
            let u = try NSKeyedUnarchiver(forReadingFrom: data)
            u.requiresSecureCoding = false
            u.decodingFailurePolicy = .setErrorAndReturn
            u.setClass(BTMStorage.self, forClassName: "Storage")
            u.setClass(BTMItem.self, forClassName: "ItemRecord")
            u.setClass(BTMNothing.self, forClassName: "BTMUserSettings")
            let store = u.decodeObject(forKey: "store") as? BTMStorage
            u.finishDecoding()
            guard let store else { b.problem = "The Background Task Management database has an unknown shape (\(f))."; return b }
            let me = currentUserGUID()
            b.user = store.items[me] ?? []
            b.root = store.items[rootUser] ?? []
        } catch {
            b.problem = "The Background Task Management database could not be decoded: \(error.localizedDescription)"
        }
        for it in b.user + b.root {
            if let id = it.identifier, b.byId[id] == nil { b.byId[id] = it }
            if let p = it.urlPath, p.hasSuffix(".plist") { b.byPlist[p] = it }
        }
        return b
    }

    static func currentUserGUID() -> String {
        let r = sh("/usr/bin/dscl", [".", "-read", "/Users/\(NSUserName())", "GeneratedUID"])
        return r.out.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
    }

    func owner(of it: BTMItem?) -> String? {
        guard let it else { return nil }
        if let d = it.developerName, !d.isEmpty { return d }
        if let c = it.container, let parent = byId[c], let n = parent.name ?? parent.developerName { return n }
        return nil
    }
    func containerPath(of it: BTMItem) -> String? {
        guard let c = it.container, let parent = byId[c] else { return nil }
        return parent.urlPath
    }
}

// MARK: - The engine

final class Engine {
    let uid = getuid()
    let testPrefix: String?
    let testDir: String?
    let testSysDir: String?       // test: dummy plists treated as system-domain items (root step), never really run
    let testRoot: String?         // test: "cancel" simulates a refused administrator password
    let testFail: Set<String>     // test: labels whose launchctl line is made to fail (simulated, not run)
    let testPermissionMissing: Bool
    let testLogin: Bool           // test: one fake Open at Login dummy (System Events is never called in test mode)
    let store: Store
    var isTest: Bool { testPrefix != nil }

    init() {
        let env = ProcessInfo.processInfo.environment
        let prefix = env["CLEANSTART_TEST_PREFIX"].flatMap { $0.isEmpty ? nil : $0 }
        testPrefix = prefix
        testDir = env["CLEANSTART_TEST_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        testSysDir = prefix == nil ? nil : env["CLEANSTART_TEST_SYSDIR"].flatMap { $0.isEmpty ? nil : $0 }
        testRoot = prefix == nil ? nil : env["CLEANSTART_TEST_ROOT"]
        testFail = prefix == nil ? [] : Set((env["CLEANSTART_TEST_FAIL"] ?? "").split(separator: ",").map(String.init))
        testPermissionMissing = prefix != nil && env["CLEANSTART_TEST_PERMISSION"] == "missing"
        testLogin = prefix != nil && env["CLEANSTART_TEST_LOGIN"] == "1"
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(APP_NAME)")
        if let d = env["CLEANSTART_STATE_DIR"], !d.isEmpty, prefix != nil { store = Store(dir: URL(fileURLWithPath: d)) }
        else if prefix != nil { store = Store(dir: support.appendingPathComponent("test")) }
        else { store = Store(dir: support) }
    }

    // MARK: reading

    func overrides(_ domain: String) -> [String: Bool] {   // label -> disabled
        var d: [String: Bool] = [:]
        for line in sh("/bin/launchctl", ["print-disabled", domain]).out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("\""), let close = s.dropFirst().firstIndex(of: "\""),
                  let arrow = s.range(of: "=> ") else { continue }
            let label = String(s[s.index(after: s.startIndex)..<close])
            let v = s[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            d[label] = (v == "disabled" || v == "true")
        }
        return d
    }

    func runningGUI() -> Set<String> {
        var r = Set<String>()
        for line in sh("/bin/launchctl", ["list"]).out.split(separator: "\n").dropFirst() {
            let c = line.split(separator: "\t")
            if c.count >= 3, c[0] != "-" { r.insert(String(c[2])) }
        }
        return r
    }

    func isApple(_ label: String, _ path: String) -> Bool { label.hasPrefix("com.apple.") || path.hasPrefix("/System/") }

    /// iLok / PACE Anti-Piracy licensing (labels com.paceap.*, iLok License Manager, PACE's LDSvc, /PACEAntiPiracy/):
    /// his audio plug-ins stop authorising without it, so CLEAN START never switches it off. Matched by pattern so
    /// future PACE versions are covered too.
    static let keepPatterns = ["paceap", "ilok", "pace anti-piracy", "pace anti piracy", "paceantipiracy", "ldsvc"]
    func isKeep(_ i: StartItem) -> Bool {
        let hay = [i.label, i.path, i.name, i.owner, i.runs].joined(separator: "\n").lowercased()
        return Engine.keepPatterns.contains { hay.contains($0) }
    }
    /// What FULL START restores, and from where: snapshot.json; if it is missing or broken, the newest backup; plus the
    /// log's ledger of what this app itself switched off and never switched back (v7, 23.11.2026).
    struct Base {
        var snap: Snapshot?
        var from: String
        var leftOff: Set<String>      // keys this app switched off last (log.txt), brought back by FULL START
        var isEmpty: Bool { snap == nil && leftOff.isEmpty }
        /// The "before" of a snapshot counts only while its Clean is in force; after a complete FULL START only the log does.
        func wasOn(_ key: String) -> Bool? { leftOff.contains(key) ? true : (snap?.active == true ? snap?.items[key]?.wasOn : nil) }
    }
    func restoreBase() -> Base {
        let led = store.ledger()
        let off = Set(led.filter { !$0.value }.keys)
        switch store.readSnapshot() {
        case .ok(let s): return Base(snap: s, from: "snapshot.json", leftOff: off)
        default:
            if let found = store.newestBackup() { var b = found.0; b.active = store.lastPressWasClean(); return Base(snap: b, from: found.1, leftOff: off) }
            return Base(snap: nil, from: off.isEmpty ? "" : "log.txt", leftOff: off)
        }
    }

    /// What an item should be after a press: a kept item is always on; the rest follow his choice, else off (CLEAN) or
    /// as it was before the first CLEAN (FULL: anything this app switched off comes back on).
    func target(_ i: StartItem, clean: Bool, base: Base?) -> Bool {
        if i.keep { return true }
        if let c = i.choice { return c }
        return clean ? false : (base?.wasOn(i.id) ?? i.on)
    }

    func trigger(_ p: [String: Any], start: String) -> String {
        var t: [String] = []
        if (p["RunAtLoad"] as? Bool) == true { t.append(start) }
        if let k = p["KeepAlive"], (k as? Bool) == true || k is [String: Any] { t.append("kept running") }
        if let s = p["StartInterval"] as? Int { t.append(s >= 3600 ? "every \(s / 3600) h" : s >= 60 ? "every \(s / 60) min" : "every \(s) s") }
        if p["StartCalendarInterval"] != nil { t.append("on a timetable") }
        if p["WatchPaths"] != nil || p["QueueDirectories"] != nil { t.append("when files change") }
        if (p["StartOnMount"] as? Bool) == true { t.append("when a disk mounts") }
        if t.isEmpty { t.append(p["MachServices"] != nil || p["Sockets"] != nil ? "when an app asks for it" : "only when asked") }
        return t.joined(separator: ", ")
    }

    func scan() -> ScanResult {
        var r = ScanResult()
        let ovGUI = overrides("gui/\(uid)"), ovSys = overrides("system")
        let running = runningGUI()
        let btm = BTM.load()
        if let p = btm.problem { r.problems.append(p) }
        let choices = store.choices()
        var seen = Set<String>()
        var items: [StartItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        func add(_ i: StartItem) {
            guard !seen.contains(i.id) else { return }
            seen.insert(i.id); items.append(i)
        }

        // 1. launchd plists
        var dirs: [(String, Kind, Mech)] = [
            ("\(home)/Library/LaunchAgents", .userAgent, .gui),
            ("/Library/LaunchAgents", .allUsersAgent, .gui),
            ("/Library/LaunchDaemons", .daemon, .system),
        ]
        if let t = testDir { dirs.insert((t, .test, .gui), at: 0) }
        if let t = testSysDir { dirs.insert((t, .test, .system), at: 0) }
        for (dir, kind, mech) in dirs {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
            for f in files {
                let path = "\(dir)/\(f)"
                let read = NSDictionary(contentsOfFile: path) as? [String: Any]
                let p = read ?? [:]
                let label = (p["Label"] as? String) ?? String(f.dropLast(6))
                if isApple(label, path) { r.appleCount += 1; continue }
                let args = (p["ProgramArguments"] as? [String]) ?? []
                let program = (p["Program"] as? String) ?? args.first ?? ""
                let b = btm.byPlist[path]
                var i = StartItem(id: "\(mech.rawValue):\(label)",
                                  name: appName(inPath: program) ?? label,
                                  owner: btm.owner(of: b) ?? appName(inPath: program) ?? vendor(fromLabel: label),
                                  kind: kind, mech: mech, label: label, path: path)
                i.runs = ([program] + args.dropFirst()).filter { !$0.isEmpty }.joined(separator: " ")
                i.trigger = trigger(p, start: mech == .system ? "at boot" : "at login")
                let ov = mech == .system ? ovSys : ovGUI
                if let disabled = ov[label] { i.on = !disabled } else { i.on = !((p["Disabled"] as? Bool) ?? false) }
                if let gone = missingProgram(program, args, home: home) { i.warnings.append("program missing: \(gone)") }
                if read == nil { i.notes.append("the plist could not be read") }
                else if p.isEmpty { i.notes.append("empty plist: launchd has nothing to start here") }
                if let b, !b.allowed { i.notes.append("also off in System Settings › Login Items") }
                if mech == .gui, running.contains(label) { i.running = true }
                if mech == .gui, let s = p["LimitLoadToSessionType"] {
                    let types = (s as? [String]) ?? [(s as? String) ?? ""]
                    if !types.contains("Aqua") {
                        i.mech = .readOnly
                        i.readOnlyWhy = "Runs in the \(types.joined(separator: "/")) session, outside your login; launchd's switch for you does not reach it."
                    }
                }
                add(i)
            }
        }

        // 2. Background Task Management: login items, agents and daemons inside app bundles, Open at Login apps
        for b in btm.user {
            if b.type & 0x4 != 0, let label = b.bundleIdentifier ?? b.label {
                if isApple(label, "") { r.appleCount += 1; continue }
                var path = b.urlPath ?? ""
                if let c = btm.containerPath(of: b), !path.hasPrefix("/") { path = (c as NSString).appendingPathComponent(path) }
                var i = StartItem(id: "gui:\(label)", name: b.name ?? label,
                                  owner: btm.owner(of: b) ?? appName(inPath: path) ?? vendor(fromLabel: label),
                                  kind: .appLoginItem, mech: .gui, label: label, path: path)
                i.trigger = "at login"
                i.on = !(ovGUI[label] ?? false)
                if !(b.enabled && b.allowed) { i.notes.append("also off in System Settings › Login Items") }
                if running.contains(label) { i.running = true }
                add(i)
            } else if b.type & 0x8 != 0, !b.legacy, let label = b.label {
                if isApple(label, "") { r.appleCount += 1; continue }
                var path = b.urlPath ?? ""
                if let c = btm.containerPath(of: b), !path.hasPrefix("/") { path = (c as NSString).appendingPathComponent(path) }
                var i = StartItem(id: "gui:\(label)", name: b.name ?? label, owner: btm.owner(of: b) ?? vendor(fromLabel: label),
                                  kind: .appAgent, mech: .gui, label: label, path: path)
                i.trigger = "at login"
                i.on = !(ovGUI[label] ?? false)
                if !b.allowed { i.notes.append("also off in System Settings › Login Items") }
                if running.contains(label) { i.running = true }
                add(i)
            } else if b.type & 0x2 != 0, b.enabled, let path = b.urlPath {
                let id = "login:\(path.hasSuffix("/") ? String(path.dropLast()) : path)"
                let clean = id.dropFirst(6)
                if clean.hasPrefix("/System/") { r.appleCount += 1; continue }
                let shown = noApp(b.name ?? appName(inPath: path) ?? path)
                var i = StartItem(id: id, name: shown,
                                  owner: b.developerName ?? shown, kind: .openAtLogin, mech: .loginItem,
                                  label: b.bundleIdentifier ?? "", path: String(clean))
                i.trigger = "at login"
                i.on = true
                if !FileManager.default.fileExists(atPath: i.path) { i.warnings.append("app missing: \(i.path)") }
                add(i)
            }
        }
        for b in btm.root where b.type & 0x10 != 0 && !b.legacy {
            guard let label = b.label else { continue }
            if isApple(label, "") { r.appleCount += 1; continue }
            var path = b.urlPath ?? ""
            if let c = btm.containerPath(of: b), !path.hasPrefix("/") { path = (c as NSString).appendingPathComponent(path) }
            var i = StartItem(id: "system:\(label)", name: b.name ?? label, owner: btm.owner(of: b) ?? vendor(fromLabel: label),
                              kind: .appDaemon, mech: .system, label: label, path: path)
            i.trigger = "when an app asks for it"
            i.on = !(ovSys[label] ?? false)
            if !b.allowed { i.notes.append("also off in System Settings › Login Items") }
            add(i)
        }

        if testLogin, let t = testPrefix {
            var i = StartItem(id: "login:/private/tmp/\(t)loginapp.app", name: "\(t)loginapp", owner: "test", kind: .test,
                              mech: .loginItem, label: "", path: "/private/tmp/\(t)loginapp.app")
            i.trigger = "at login"; i.on = true
            add(i)
        }

        // 3. Open at Login apps that Clean took out: still listed, switched off (from the snapshot, a backup, or the log)
        let base = restoreBase()
        if let s = base.snap {
            for (key, e) in s.items where e.mech == .loginItem && !seen.contains(key) {
                var i = StartItem(id: key, name: e.name, owner: e.name, kind: .openAtLogin, mech: .loginItem, label: e.label, path: e.path)
                i.trigger = "at login"; i.on = false; i.hidden = e.hidden ?? false
                add(i)
            }
        }
        for key in base.leftOff.sorted() where key.hasPrefix("login:") && !seen.contains(key) && !(testPrefix != nil && !key.contains(testPrefix!)) {
            let path = String(key.dropFirst(6))
            var i = StartItem(id: key, name: noApp((path as NSString).lastPathComponent), owner: noApp((path as NSString).lastPathComponent),
                              kind: testPrefix != nil ? .test : .openAtLogin, mech: .loginItem, label: "", path: path)
            i.trigger = "at login"; i.on = false
            add(i)
        }

        // 4. System extensions (read only)
        var section = ""
        for line in sh("/usr/bin/systemextensionsctl", ["list"]).out.split(separator: "\n") {
            if line.hasPrefix("---") {
                section = line.contains("network") ? "network extension" : line.contains("cmio") ? "camera extension"
                    : line.contains("driver") ? "driver extension" : "system extension"
                continue
            }
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 6, c[2] != "teamID" else { continue }
            let bundle = c[3].components(separatedBy: " (").first ?? c[3]
            if bundle.hasPrefix("com.apple.") { r.appleCount += 1; continue }
            var i = StartItem(id: "ro:sysext:\(bundle)", name: c[4], owner: vendor(fromLabel: bundle), kind: .sysExt,
                              mech: .readOnly, label: bundle, path: c[5])
            i.trigger = "at boot (\(section))"
            i.on = c[0] == "*"
            i.settingsURL = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            add(i)
        }

        // 5. Other starters (read only)
        for line in sh("/usr/bin/crontab", ["-l"]).out.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("@reboot") {
            var i = StartItem(id: "ro:cron:\(line)", name: "cron @reboot", owner: "you (crontab)", kind: .other, mech: .readOnly,
                              label: "", path: String(line))
            i.trigger = "at boot"; i.readOnlyWhy = "Edit with crontab -e in Terminal."
            add(i)
        }
        for pref in ["/Library/Preferences/com.apple.loginwindow.plist", "\(home)/Library/Preferences/com.apple.loginwindow.plist"] {
            let d = (NSDictionary(contentsOfFile: pref) as? [String: Any]) ?? [:]
            for key in ["LoginHook", "LogoutHook"] {
                if let v = d[key] as? String, !v.isEmpty {
                    var i = StartItem(id: "ro:hook:\(pref):\(key)", name: key, owner: "loginwindow", kind: .other, mech: .readOnly,
                                      label: key, path: v)
                    i.trigger = key == "LoginHook" ? "at login, as root" : "at logout, as root"
                    i.readOnlyWhy = "Remove with: sudo defaults delete com.apple.loginwindow \(key)"
                    add(i)
                }
            }
        }
        for f in ((try? FileManager.default.contentsOfDirectory(atPath: "/Library/StartupItems")) ?? []) where !f.hasPrefix(".") {
            var i = StartItem(id: "ro:startupitem:\(f)", name: f, owner: f, kind: .other, mech: .readOnly, label: f,
                              path: "/Library/StartupItems/\(f)")
            i.trigger = "at boot (old StartupItems)"
            i.readOnlyWhy = "macOS 15 no longer runs StartupItems; shown only so it is not hidden."
            add(i)
        }

        // 6. Apple's own launchd jobs, counted only
        for d in ["/System/Library/LaunchAgents", "/System/Library/LaunchDaemons"] {
            r.appleCount += ((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".plist") }.count
        }

        // 7. choices, test lock
        for k in items.indices {
            items[k].choice = choices[items[k].id]
            items[k].keep = items[k].switchable && isKeep(items[k])
            if let t = testPrefix {
                let subject = items[k].mech == .loginItem ? items[k].name : items[k].label
                // a dummy in the test folders may carry a PACE-like label, to prove the keep rule; real items stay locked
                items[k].locked = !(subject.hasPrefix(t) || (items[k].kind == .test && items[k].keep))
            }
        }
        let order = Kind.allCases
        items.sort { a, b in
            a.kind != b.kind ? order.firstIndex(of: a.kind)! < order.firstIndex(of: b.kind)!
                : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        r.items = items

        // 8. the mode, read from the real state
        if case .ok(let s) = store.readSnapshot() { r.snapshotActive = s.active; r.snapshotDate = s.lastClean ?? s.created }
        else if case .broken(let e) = store.readSnapshot() { r.problems.append("snapshot.json cannot be read (\(e)); CLEAN START is refused until it is fixed.") }
        // The mode is what FULL START would still change: anything it would switch back on means a Clean is in force.
        // (v6 said NORMAL as soon as one item came back on by itself, while 61 were still off: 23.11.2026.)
        let pool = items.filter { $0.changeable && !$0.keep }
        r.keptCount = items.filter { $0.keep }.count
        r.stillOn = pool.filter { $0.on && $0.choice != true }.count
        r.restoreFrom = base.from
        for k in items.indices where items[k].changeable && !items[k].keep && !items[k].on && target(items[k], clean: false, base: base) {
            r.heldOff += 1
            items[k].notes.append("off by CLEAN START; FULL START switches it back on")
        }
        r.items = items
        r.mode = r.heldOff > 0 ? .clean : .full
        r.automation = items.contains { $0.mech == .loginItem } ? automationStatusStartingSystemEvents() : noErr
        if testPermissionMissing { r.automation = -1744; r.forcePermission = true }
        return r
    }

    // MARK: switching

    struct Change { var item: StartItem; var to: Bool }

    /// What a press did. All or nothing up to the first real change: a refused password or a missing permission
    /// stops it before anything is touched.
    struct Outcome {
        var lines: [String] = []
        var confirm: String? = nil      // asked in the window before anything changes ("switch the rest?")
        var changed = 0
        var done: [String] = []         // names really switched (read back)
        var failed: [String] = []
        var aborted = false
    }

    func automationMissing() -> Bool { testPermissionMissing || automationStatusStartingSystemEvents() != noErr }

    /// The window comes to the front before the administrator prompt, so the prompt is not hidden behind other windows
    /// (v7: a NORMAL press of 23.11.2026 never got past this step; nothing of it is in the log).
    func bringToFront() {
        let work = { if NSApp != nil, NSApp.activationPolicy() == .regular { NSApp.activate(ignoringOtherApps: true) } }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    /// Applies the changes in a safe order: the administrator step FIRST (refused = nothing at all is changed), then your
    /// launchd domain, then the Open at Login apps. Every change is read back (launchd, System Events) before it is counted,
    /// and every item is written to log.txt by name, so FULL START can always find what this app switched off.
    func apply(_ changes: [Change], skipLogins: Bool) -> Outcome {
        var o = Outcome()
        let real = changes.filter { $0.item.changeable && $0.item.on != $0.to }
        var logins = real.filter { $0.item.mech == .loginItem }
        if !logins.isEmpty && automationMissing() {
            let names = logins.map { $0.item.name }.joined(separator: ", ")
            if !skipLogins {
                o.aborted = true
                o.confirm = "Nothing changed yet. \(logins.count) Open at Login app\(logins.count == 1 ? "" : "s") (\(names)) cannot be switched without PERMISSIONS (Automation of System Events). Switch the rest and leave \(logins.count == 1 ? "it" : "them") as \(logins.count == 1 ? "it is" : "they are")?"
                return o
            }
            o.lines.append("Left as they are (no Automation permission): \(names).")
            logins = []
        }
        // 1. root, one prompt, before anything else
        let sys = real.filter { $0.item.mech == .system }
        if !sys.isEmpty {
            let cmd = rootCommand(sys)
            var ok = false, why = ""
            let asked: [String] = sys.map { c in (c.to ? "enable " : "disable ") + c.item.label }
            store.log("system: asking for the administrator password, \(sys.count) items: " + asked.joined(separator: ", "))
            if isTest {
                try? FileManager.default.createDirectory(at: store.dir, withIntermediateDirectories: true)
                try? cmd.write(to: store.dir.appendingPathComponent("would-run-root.sh"), atomically: true, encoding: .utf8)
                if testRoot == "cancel" { why = "the administrator password was not given (test: simulated cancel; the command was written, not run)" }
                else { ok = true }
            } else {
                bringToFront()
                let src = "do shell script \"\(asq(cmd))\" with administrator privileges with prompt \"\(APP_NAME) switches \(sys.count) system item\(sys.count == 1 ? "" : "s") for the next start.\""
                let r = appleScript(src)
                ok = r.ok
                why = (r.error ?? "").contains("cancel") || (r.error ?? "").contains("-128") ? "the administrator password was not given" : (r.error ?? "the administrator step failed")
            }
            store.log("system \(sys.count) items -> \(ok ? "ok" : why)")
            if !ok {
                o.aborted = true
                o.lines.append("Nothing changed: \(why).")
                return o
            }
        }
        // 2. your launchd domain
        for c in real where c.item.mech == .gui {
            let verb = c.to ? "enable" : "disable"
            if testFail.contains(c.item.label) {
                store.log("gui \(verb) \(c.item.label) -> simulated failure (test)")
                continue
            }
            let r = sh("/bin/launchctl", [verb, "gui/\(uid)/\(c.item.label)"])
            store.log("gui \(verb) \(c.item.label) -> \(r.status)")
        }
        // read every launchd change back
        let ovG = overrides("gui/\(uid)"), ovS = overrides("system")
        for c in real where c.item.mech == .gui || c.item.mech == .system {
            let ov = c.item.mech == .gui ? ovG : ovS
            let good = ov[c.item.label].map { $0 == !c.to } ?? false
            if c.item.mech == .system && !(isTest) { store.log("system \(c.to ? "enable" : "disable") \(c.item.label) -> \(good ? "ok" : "still \(c.to ? "off" : "on")")") }
            if good { o.changed += 1; o.done.append(c.item.name) }
            else if isTest && c.item.mech == .system { o.failed.append("\(c.item.name) (test mode: root command written, not run)") }
            else if testFail.contains(c.item.label) { o.failed.append("\(c.item.name) (launchctl failed: simulated by the test)") }
            else { o.failed.append("\(c.item.name) (launchd still has it \(c.to ? "off" : "on"))") }
        }
        // 3. Open at Login apps, read back from System Events
        var done: [Change] = []
        for c in logins {
            if isTest { o.failed.append("\(c.item.name) (test mode: System Events script written, not run)"); continue }
            let r = appleScript(loginScript(c))
            if r.ok { done.append(c) } else { store.log("login \(c.to ? "add" : "remove") \(c.item.path) -> \(r.error ?? "?")"); o.failed.append("\(c.item.name) (\(r.error ?? "System Events refused"))") }
        }
        if !done.isEmpty {
            let now = loginHidden()
            for c in done {
                let present = now[c.item.path] != nil
                let good = now.isEmpty && c.to ? false : present == c.to
                store.log("login \(c.to ? "add" : "remove") \(c.item.path) -> \(good ? "ok" : "not read back")")
                if good { o.changed += 1; o.done.append(c.item.name) } else { o.failed.append("\(c.item.name) (System Events does not show it \(c.to ? "in" : "out of") the login items)") }
            }
        }
        return o
    }

    func summary(_ what: String, _ o: Outcome, total: Int, verb: String) -> [String] {
        var l = ["\(what): \(o.changed) of \(total) \(verb) for the next start" + (o.failed.isEmpty ? "." : "; \(o.failed.count) did not: \(o.failed.joined(separator: ", ")).")]
        if what == "CLEAN START", o.changed > 0 { l[0] += " What runs now keeps running until you restart." }
        if what == "FULL START", o.changed > 0 { l[0] += " Restart the Mac and they start by themselves again." }
        if !o.done.isEmpty { l.append("\(what == "FULL START" ? "Back on" : "Off") (\(o.done.count)): \(o.done.joined(separator: ", ")).") }
        return l + o.lines
    }

    func rootCommand(_ sys: [Change]) -> String {
        sys.map { "/bin/launchctl \($0.to ? "enable" : "disable") system/\(shq($0.item.label))" }.joined(separator: " ; ")
    }
    func loginScript(_ c: Change) -> String {
        if c.to {
            return "tell application \"System Events\" to make login item at end with properties {path:\"\(asq(c.item.path))\", hidden:\(c.item.hidden ? "true" : "false")}"
        }
        return "tell application \"System Events\" to delete (every login item whose path is \"\(asq(c.item.path))\")"
    }

    /// path -> hidden, from System Events (only with the Automation permission).
    func loginHidden() -> [String: Bool] {
        guard !automationMissing() else { return [:] }
        let r = appleScript("tell application \"System Events\" to get {path, hidden} of every login item")
        guard r.ok, let d = r.result, d.numberOfItems >= 2, let ps = d.atIndex(1), let hs = d.atIndex(2) else { return [:] }
        var m: [String: Bool] = [:]
        if ps.numberOfItems > 0 {
            for k in 1...ps.numberOfItems {
                if let p = ps.atIndex(k)?.stringValue { m[p.hasSuffix("/") ? String(p.dropLast()) : p] = hs.atIndex(k)?.booleanValue ?? false }
            }
        }
        return m
    }

    /// CLEAN START. The snapshot is written first, the press is all or nothing up to the first change, and the snapshot is
    /// marked active only once something really changed. The "before" is never lost (v7, 23.11.2026): while a Clean is in
    /// force a second CLEAN only adds new items; and a fresh "before" counts as ON every item this app itself switched off
    /// and never switched back (log.txt), so a CLEAN pressed on top of an unfinished Clean cannot turn "on" into "off".
    func clean(skipLogins: Bool = false) -> Outcome {
        var snap: Snapshot
        switch store.readSnapshot() {
        case .broken(let e): return Outcome(lines: ["CLEAN START refused: snapshot.json cannot be read (\(e)). Nothing was changed. FULL START still works from the backups and the log."], aborted: true)
        case .ok(let s): snap = s
        case .none: snap = Snapshot(created: stamp(), active: false, items: [:])
        }
        let s = scan()
        let leftOff = restoreBase().leftOff
        let fresh = !snap.active     // a new "before": the state now. While active, only new items are added.
        var changes: [Change] = []
        for i in s.items where i.changeable {
            let target = self.target(i, clean: true, base: nil)
            if i.on != target { changes.append(Change(item: i, to: target)) }
        }
        // permission question before anything is written or changed
        if !skipLogins, changes.contains(where: { $0.item.mech == .loginItem }), automationMissing() {
            return apply(changes, skipLogins: false)
        }
        let hidden = loginHidden()
        if fresh { snap.created = stamp(); snap.appVersion = VERSION }
        for i in s.items where i.changeable {
            let wasOn = i.on || leftOff.contains(i.id)
            if snap.items[i.id] == nil || (fresh && i.mech != .loginItem) || (fresh && i.mech == .loginItem && wasOn) {
                snap.items[i.id] = SnapEntry(name: i.name, mech: i.mech, label: i.label, path: i.path, wasOn: wasOn,
                                             hidden: i.mech == .loginItem ? (hidden[i.path] ?? snap.items[i.id]?.hidden ?? i.hidden) : nil)
            } else if !fresh, leftOff.contains(i.id), snap.items[i.id]?.wasOn == false {
                snap.items[i.id]?.wasOn = true
            }
        }
        do { try store.write(snap) } catch { return Outcome(lines: ["CLEAN START refused: the snapshot could not be written (\(error)). Nothing was changed."], aborted: true) }
        store.backup()
        for k in changes.indices where changes[k].item.mech == .loginItem { changes[k].item.hidden = snap.items[changes[k].item.id]?.hidden ?? false }
        if isTest { writeWouldRun(s, clean: true, base: nil) }
        store.log("press CLEAN: \(changes.count) to switch")
        var o = apply(changes, skipLogins: skipLogins)
        if !o.aborted && (o.changed > 0 || changes.isEmpty) {
            snap.active = true
            snap.lastClean = stamp()
            try? store.write(snap)
        }
        store.log("CLEAN START \(o.aborted ? "aborted, nothing changed" : "\(o.changed) changed, \(o.failed.count) failed"), snapshot \(fresh ? "new" : "kept"), active \(snap.active)")
        if !o.aborted { o.lines = summary("CLEAN START", o, total: changes.count, verb: "switched off") + (fresh ? [] : ["The first snapshot was kept: FULL START still brings back everything that was on before the first CLEAN START."]) }
        return o
    }

    /// FULL START (NORMAL START until v6): everything back as it was before the first CLEAN START, except what he switched
    /// himself; iLok / PACE always on. "As it was" comes from snapshot.json while its Clean is in force, else from the
    /// newest backup, and in every case anything this app itself switched off and never back (log.txt) comes back on.
    /// All or nothing up to the first change; the snapshot stays active until every item is back.
    func full(skipLogins: Bool = false) -> Outcome {
        let base = restoreBase()
        if base.isEmpty {
            if case .broken(let e) = store.readSnapshot() { return Outcome(lines: ["FULL START refused: snapshot.json cannot be read (\(e)) and there is no backup or log to restore from."], aborted: true) }
            return Outcome(lines: ["Nothing to restore: CLEAN START was never pressed. Everything is as it was."])
        }
        let s = scan()
        var changes: [Change] = []
        for var i in s.items where i.changeable {
            if i.mech == .loginItem { i.hidden = base.snap?.items[i.id]?.hidden ?? i.hidden }
            let target = self.target(i, clean: false, base: base)
            if i.on != target { changes.append(Change(item: i, to: target)) }
        }
        if isTest { writeWouldRun(s, clean: false, base: base) }
        store.log("press FULL: \(changes.count) to switch, restoring from \(base.from)")
        var o = apply(changes, skipLogins: skipLogins)
        if !o.aborted && o.failed.isEmpty {
            var snap: Snapshot
            switch store.readSnapshot() {
            case .ok(let x): snap = x
            case .broken:
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
                store.ensureDir()
                try? FileManager.default.moveItem(at: store.snapURL, to: store.dir.appendingPathComponent("backups/snapshot-broken-\(f.string(from: Date())).json"))
                snap = base.snap ?? Snapshot(created: stamp(), active: false, items: [:])
            case .none: snap = base.snap ?? Snapshot(created: stamp(), active: false, items: [:])
            }
            snap.active = false
            snap.lastNormal = stamp()
            try? store.write(snap)
        }
        store.log("FULL START \(o.aborted ? "aborted, nothing changed" : "\(o.changed) changed, \(o.failed.count) failed")")
        if !o.aborted {
            o.lines = summary("FULL START", o, total: changes.count, verb: "switched back")
            if base.from != "snapshot.json" { o.lines.append("Restored from \(base.from) (snapshot.json was missing or broken).") }
        }
        return o
    }

    /// One switch in the list: applied at once, then remembered as his choice (not when nothing could change).
    func set(_ key: String, on: Bool) -> Outcome {
        let s = scan()
        guard let i = s.items.first(where: { $0.id == key }) else { return Outcome(lines: ["\(key): not found"], aborted: true) }
        guard i.changeable else { return Outcome(lines: ["\(i.name): \(i.locked ? "locked in test mode" : "cannot be switched here")"], aborted: true) }
        var item = i
        if case .ok(let snap) = store.readSnapshot(), let e = snap.items[key], let h = e.hidden { item.hidden = h }
        var o = apply([Change(item: item, to: on)], skipLogins: false)
        if let q = o.confirm { o.confirm = nil; o.lines = [q.replacingOccurrences(of: " Switch the rest and leave it as it is?", with: "")] }
        if o.aborted { return o }
        if o.failed.isEmpty {
            var c = store.choices(); c[key] = on; store.saveChoices(c)
            store.log("choice \(key) = \(on)")
            o.lines = ["\(i.name): \(on ? "on" : "off") from the next start (your choice, kept in both modes)."] + o.lines
        } else {
            o.lines.insert("\(i.name) not changed: \(o.failed.joined(separator: ", ")).", at: 0)
        }
        return o
    }

    /// Test mode only: what CLEAN or FULL would run on the REAL items, written next to the test state, never run.
    /// In test mode the real base is read from the REAL state folder, so would-run-full.sh shows what FULL START will do
    /// on this Mac.
    func writeWouldRun(_ s: ScanResult, clean: Bool, base: Base?) {
        var lines: [String] = ["# \(APP_NAME) v\(VERSION) test mode, \(stamp()): what \(clean ? "CLEAN START" : "FULL START") would run on the real items. NOT RUN."]
        let realBase = clean ? nil : Engine.realBase()
        if let b = realBase { lines.append("# restoring from \(b.from) in the real state folder; switched off by this app and never back: \(b.leftOff.count)") }
        var sys: [Change] = []
        for var i in s.items where i.switchable && i.locked {
            i.locked = false
            let target = self.target(i, clean: clean, base: realBase)
            if i.keep { lines.append("# KEPT ON (iLok / PACE), never disabled: \(i.mech == .system ? "system" : "gui")/\(i.label) is \(i.on ? "on" : "OFF") now" + (i.on ? "" : "; this press switches it ON")) }
            guard i.on != target else { continue }
            switch i.mech {
            case .gui: lines.append("/bin/launchctl \(target ? "enable" : "disable") gui/\(uid)/\(shq(i.label))")
            case .system: sys.append(Change(item: i, to: target))
            case .loginItem: lines.append("osascript -e \(shq(loginScript(Change(item: i, to: target))))")
            case .readOnly: break
            }
        }
        if !sys.isEmpty {
            lines.append("# one administrator prompt, through: do shell script \"…\" with administrator privileges")
            lines.append(rootCommand(sys))
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: store.dir.appendingPathComponent("would-run-\(clean ? "clean" : "full").sh"), atomically: true, encoding: .utf8)
    }

    /// The real state folder's restore base (read only), for would-run-full.sh in test mode.
    static func realBase() -> Base {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(APP_NAME)")
        let st = Store(dir: support)
        let off = Set(st.ledger().filter { !$0.value }.keys)
        switch st.readSnapshot() {
        case .ok(let s): return Base(snap: s, from: "snapshot.json", leftOff: off)
        default:
            if let found = st.newestBackup() { var b = found.0; b.active = st.lastPressWasClean(); return Base(snap: b, from: found.1, leftOff: off) }
            return Base(snap: nil, from: "log.txt", leftOff: off)
        }
    }
}
