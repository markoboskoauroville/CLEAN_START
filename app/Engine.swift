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
    var readOnlyWhy: String? = nil
    var settingsURL: String? = nil
    var hidden: Bool = false
    var running: Bool = false
    var locked: Bool = false    // test mode: a real item, never touched
    var choice: Bool? = nil     // Marko's own switch, remembered
    var switchable: Bool { mech != .readOnly }
    var changeable: Bool { switchable && !locked }
}

enum Mode: String { case clean = "CLEAN START", normal = "NORMAL START" }

struct ScanResult {
    var items: [StartItem] = []
    var appleCount = 0
    var mode: Mode = .normal
    var snapshotActive = false
    var snapshotDate: String? = nil
    var stillOn = 0              // items that would keep starting although CLEAN is set
    var automation: OSStatus = noErr
    var problems: [String] = []
    var groups: [Kind] { Kind.allCases.filter { k in items.contains { $0.kind == k } } }
    var needsAutomation: Bool {
        items.contains { $0.mech == .loginItem && $0.changeable } && automation != noErr
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
    init(dir: URL) {
        self.dir = dir
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
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(c).write(to: choicesURL, options: .atomic)
    }
    func log(_ s: String) {
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
    let store: Store
    var isTest: Bool { testPrefix != nil }

    init() {
        let env = ProcessInfo.processInfo.environment
        let prefix = env["CLEANSTART_TEST_PREFIX"].flatMap { $0.isEmpty ? nil : $0 }
        testPrefix = prefix
        testDir = env["CLEANSTART_TEST_DIR"].flatMap { $0.isEmpty ? nil : $0 }
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
        for (dir, kind, mech) in dirs {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".plist") }.sorted()
            for f in files {
                let path = "\(dir)/\(f)"
                let p = (NSDictionary(contentsOfFile: path) as? [String: Any]) ?? [:]
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
                if p.isEmpty { i.notes.append("the plist could not be read") }
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
                var i = StartItem(id: id, name: b.name ?? appName(inPath: path) ?? path,
                                  owner: b.developerName ?? b.name ?? "", kind: .openAtLogin, mech: .loginItem,
                                  label: b.bundleIdentifier ?? "", path: String(clean))
                i.trigger = "at login"
                i.on = true
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

        // 3. Open at Login apps that Clean took out: still listed, switched off
        if case .ok(let s) = store.readSnapshot() {
            for (key, e) in s.items where e.mech == .loginItem && !seen.contains(key) {
                var i = StartItem(id: key, name: e.name, owner: e.name, kind: .openAtLogin, mech: .loginItem, label: e.label, path: e.path)
                i.trigger = "at login"; i.on = false; i.hidden = e.hidden ?? false
                add(i)
            }
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
            i.readOnlyWhy = "macOS lets only System Settings › General › Login Items & Extensions switch an extension."
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
            if let t = testPrefix {
                let subject = items[k].mech == .loginItem ? items[k].name : items[k].label
                items[k].locked = !subject.hasPrefix(t)
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
        let pool = items.filter { $0.changeable }
        r.stillOn = pool.filter { $0.on && $0.choice != true }.count
        r.mode = (!pool.isEmpty && r.stillOn == 0) ? .clean : .normal
        r.automation = items.contains { $0.mech == .loginItem } ? automationStatusStartingSystemEvents() : noErr
        return r
    }

    // MARK: switching

    struct Change { var item: StartItem; var to: Bool }

    /// Applies the changes; returns lines for the window and the log.
    func apply(_ changes: [Change]) -> [String] {
        var msgs: [String] = []
        let real = changes.filter { $0.item.changeable && $0.item.on != $0.to }
        // launchd, your domain: no password
        for c in real where c.item.mech == .gui {
            let verb = c.to ? "enable" : "disable"
            let r = sh("/bin/launchctl", [verb, "gui/\(uid)/\(c.item.label)"])
            if r.status != 0 { msgs.append("\(c.item.name): launchctl \(verb) failed: \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))") }
            store.log("gui \(verb) \(c.item.label) -> \(r.status)")
        }
        // launchd, system domain: one administrator prompt for all of them
        let sys = real.filter { $0.item.mech == .system }
        if !sys.isEmpty {
            let cmd = rootCommand(sys)
            if isTest {
                try? cmd.write(to: store.dir.appendingPathComponent("would-run-root.sh"), atomically: true, encoding: .utf8)
                msgs.append("Test mode: the root command was written, not run.")
            } else {
                let src = "do shell script \"\(asq(cmd))\" with administrator privileges with prompt \"\(APP_NAME) switches \(sys.count) system item\(sys.count == 1 ? "" : "s") for the next start.\""
                let r = appleScript(src)
                store.log("system \(sys.count) items -> \(r.ok ? "ok" : (r.error ?? "?"))")
                if !r.ok { msgs.append("System items not changed: \(r.error ?? "the password was not given").") }
            }
        }
        // Open at Login apps: System Events
        let logins = real.filter { $0.item.mech == .loginItem }
        if !logins.isEmpty {
            if automationStatusStartingSystemEvents() != noErr {
                msgs.append("\(logins.count) Open at Login app\(logins.count == 1 ? "" : "s") not changed: PERMISSIONS (Automation of System Events) is needed.")
            } else {
                for c in logins {
                    let src = loginScript(c)
                    let r = appleScript(src)
                    store.log("login \(c.to ? "add" : "remove") \(c.item.path) -> \(r.ok ? "ok" : (r.error ?? "?"))")
                    if !r.ok { msgs.append("\(c.item.name): \(r.error ?? "System Events refused")") }
                }
            }
        }
        return msgs
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
        guard automationStatusStartingSystemEvents() == noErr else { return [:] }
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

    /// CLEAN START: snapshot first (never overwritten while a Clean is in force), then every item off except his ON choices.
    func clean() -> [String] {
        var snap: Snapshot
        switch store.readSnapshot() {
        case .broken(let e): return ["CLEAN START refused: snapshot.json cannot be read (\(e)). Nothing was changed."]
        case .ok(let s): snap = s
        case .none: snap = Snapshot(created: stamp(), active: false, items: [:])
        }
        let s = scan()
        let hidden = loginHidden()
        let fresh = !snap.active     // a new "before": the state now. While active, only new items are added.
        if fresh { snap.created = stamp(); snap.appVersion = VERSION }
        for i in s.items where i.changeable {
            if snap.items[i.id] == nil || (fresh && i.mech != .loginItem) || (fresh && i.mech == .loginItem && i.on) {
                snap.items[i.id] = SnapEntry(name: i.name, mech: i.mech, label: i.label, path: i.path, wasOn: i.on,
                                             hidden: i.mech == .loginItem ? (hidden[i.path] ?? i.hidden) : nil)
            }
        }
        snap.active = true
        snap.lastClean = stamp()
        do { try store.write(snap) } catch { return ["CLEAN START refused: the snapshot could not be written (\(error)). Nothing was changed."] }
        store.backup()
        store.log("CLEAN START, snapshot \(fresh ? "new" : "kept") with \(snap.items.count) items")
        var changes: [Change] = []
        for var i in s.items where i.changeable {
            if i.mech == .loginItem { i.hidden = snap.items[i.id]?.hidden ?? false }
            let target = i.choice ?? false
            if i.on != target { changes.append(Change(item: i, to: target)) }
        }
        if isTest { writeWouldRun(s, clean: true) }
        var msgs = apply(changes)
        msgs.insert("CLEAN START set for the next start: \(changes.filter { !$0.to }.count) switched off\(fresh ? "" : " (the first snapshot was kept)"). What runs now keeps running until you restart.", at: 0)
        return msgs
    }

    /// NORMAL START: everything back as the snapshot had it, except what he switched himself.
    func normal() -> [String] {
        guard case .ok(var snap) = store.readSnapshot() else {
            if case .broken(let e) = store.readSnapshot() { return ["NORMAL START refused: snapshot.json cannot be read (\(e))."] }
            return ["Nothing to restore: CLEAN START was never pressed. Everything is as it was."]
        }
        let s = scan()
        var changes: [Change] = []
        for var i in s.items where i.changeable {
            if i.mech == .loginItem { i.hidden = snap.items[i.id]?.hidden ?? i.hidden }
            let target = i.choice ?? snap.items[i.id]?.wasOn ?? i.on
            if i.on != target { changes.append(Change(item: i, to: target)) }
        }
        if isTest { writeWouldRun(s, clean: false, snap: snap) }
        var msgs = apply(changes)
        snap.active = false
        snap.lastNormal = stamp()
        try? store.write(snap)
        store.log("NORMAL START, \(changes.count) changes")
        msgs.insert("NORMAL START set for the next start: \(changes.filter { $0.to }.count) switched back on.", at: 0)
        return msgs
    }

    /// One switch in the list: remembered as his choice, applied at once.
    func set(_ key: String, on: Bool) -> [String] {
        let s = scan()
        guard let i = s.items.first(where: { $0.id == key }) else { return ["\(key): not found"] }
        guard i.changeable else { return ["\(i.name): \(i.locked ? "locked in test mode" : "cannot be switched here")"] }
        var c = store.choices(); c[key] = on; store.saveChoices(c)
        store.log("choice \(key) = \(on)")
        var item = i
        if case .ok(let snap) = store.readSnapshot(), let e = snap.items[key], let h = e.hidden { item.hidden = h }
        var msgs = apply([Change(item: item, to: on)])
        msgs.insert("\(i.name): \(on ? "on" : "off") from the next start (your choice, kept in both modes).", at: 0)
        return msgs
    }

    /// Test mode only: what CLEAN or NORMAL would run on the REAL items, written next to the test state, never run.
    func writeWouldRun(_ s: ScanResult, clean: Bool, snap: Snapshot? = nil) {
        var lines: [String] = ["# \(APP_NAME) v\(VERSION) test mode, \(stamp()): what \(clean ? "CLEAN START" : "NORMAL START") would run on the real items. NOT RUN."]
        var sys: [Change] = []
        for var i in s.items where i.switchable && i.locked {
            i.locked = false
            let target = clean ? (i.choice ?? false) : (i.choice ?? snap?.items[i.id]?.wasOn ?? i.on)
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
        try? (lines.joined(separator: "\n") + "\n").write(to: store.dir.appendingPathComponent("would-run-\(clean ? "clean" : "normal").sh"), atomically: true, encoding: .utf8)
    }
}
