// UI.swift: the window. CAMERA language (MANTRA_MANIFEST language-camera.md): words, no boxes, colour is the state
// (green on, grey off, amber warning or needs you). Two choices on the first screen: CLEAN START | FULL START.
// The list sits behind its groups, each a folder with a one-line "what is inside" (simple-first.md).
import AppKit
import SwiftUI

enum Palette {
    static let ground = Color(red: 0x0E / 255, green: 0x10 / 255, blue: 0x13 / 255)
    static let white = Color(red: 0xE8 / 255, green: 0xEA / 255, blue: 0xED / 255)
    static let green = Color(red: 0x33 / 255, green: 0xD1 / 255, blue: 0x7A / 255)
    static let grey = Color(red: 0x7A / 255, green: 0x80 / 255, blue: 0x87 / 255)
    static let amber = Color(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x3D / 255)
    static let dark = Color(red: 0x33 / 255, green: 0x38 / 255, blue: 0x3E / 255)
    static let line = Color.white.opacity(0.10)
}

func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

final class Model: ObservableObject {
    let engine: Engine
    @Published var scan = ScanResult()
    @Published var busy = false
    @Published var status: [String] = []
    @Published var askRestart = false
    @Published var confirm: String? = nil      // a question before anything changes (missing permission)
    private var pending: ((Bool) -> Engine.Outcome)? = nil
    @Published var open: Set<Kind> = []
    private var scanning = false

    init(engine: Engine) {
        self.engine = engine
        if ProcessInfo.processInfo.environment["CLEANSTART_EXPAND"] == "1" { open = Set(Kind.allCases) }
    }

    func refresh() {
        guard !scanning, !busy else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let s = self.engine.scan()
            DispatchQueue.main.async { self.scan = s; self.scanning = false }
        }
    }

    /// job(skipLogins). A question in the window comes back as `confirm`; nothing was changed then.
    private func run(_ job: @escaping (Bool) -> Engine.Outcome, skip: Bool = false) {
        guard !busy else { return }
        busy = true
        status = []
        confirm = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let o = job(skip)
            let s = self.engine.scan()
            DispatchQueue.main.async {
                self.status = o.lines
                self.confirm = o.confirm
                self.pending = o.confirm == nil ? nil : job
                self.scan = s
                self.busy = false
            }
        }
    }
    func clean() { run { self.engine.clean(skipLogins: $0) } }
    func full() { run { self.engine.full(skipLogins: $0) } }
    func restartPressed() { askRestart = true }
    func restartAnswer(_ yes: Bool) {
        askRestart = false
        if yes { status = engine.restart() } else { status = ["Cancelled: the Mac was not restarted."] }
    }
    func set(_ i: StartItem, _ on: Bool) { run { _ in self.engine.set(i.id, on: on) } }
    func answer(_ yes: Bool) {
        guard let job = pending else { return }
        pending = nil
        if yes { run(job, skip: true) } else { confirm = nil; status = ["Cancelled: nothing changed."] }
    }

    /// PERMISSIONS: the check is made fresh on the click; the system's own question once, then the Settings page.
    func askPermission() {
        if engine.isTest {
            status = ["Test mode: PERMISSIONS would ask macOS once (tell application \"System Events\" to count login items), then open x-apple.systempreferences:com.apple.preference.security?Privacy_Automation. Nothing was opened."]
            return
        }
        var st = automationStatusStartingSystemEvents()
        if st == -1744 { _ = appleScript("tell application \"System Events\" to count login items"); st = automationStatus() }
        if st != noErr, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(u)
        }
        refresh()
    }
}

struct PressHover: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var hot = false
    func body(content: Content) -> some View {
        let on = hot && enabled
        content
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(on ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(on ? 0.55 : 0), lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: on)
            .onHover { inside in
                hot = inside
                if enabled { if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
    }
}
extension View { func pressHover() -> some View { modifier(PressHover()) } }

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.line).frame(height: 1).frame(maxWidth: .infinity) }
}

/// A word that is a button (a real Accessibility button, labelled).
struct WordButton: View {
    let word: String
    let color: Color
    var size: CGFloat = 12
    let id: String
    var label: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(word).font(mono(size, .bold)).foregroundColor(color).lineLimit(1).fixedSize()
                .padding(.horizontal, 5).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .pressHover()
        .accessibilityLabel(label ?? word.capitalized)
        .accessibilityIdentifier(id)
    }
}

struct ContentView: View {
    @ObservedObject var m: Model
    var shotWidth: CGFloat? = nil
    let margin: CGFloat = 18

    var body: some View {
        Group {
            if let w = shotWidth {
                VStack(spacing: 0) {
                    TopRow(m: m)
                    Hairline()
                    page(width: w).padding(.vertical, 14)
                }
                .frame(width: w)
                .background(Palette.ground)
            } else {
                GeometryReader { g in
                    VStack(spacing: 0) {
                        TopRow(m: m)
                        Hairline()
                        ScrollView(.vertical) { page(width: g.size.width).padding(.vertical, 14) }
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
                .background(Palette.ground)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .preferredColorScheme(.dark)
    }

    func page(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeBlock(m: m)
            Hairline()
            ForEach(m.scan.groups, id: \.self) { k in
                GroupView(m: m, kind: k)
                Hairline()
            }
            Text("Apple system items: \(m.scan.appleCount), not touched.")
                .font(mono(11)).foregroundColor(Palette.grey).fixedSize(horizontal: false, vertical: true)
            Text("The state before CLEAN START is kept in \(m.engine.store.snapURL.path), a dated copy in backups/ at every press.")
                .font(.system(size: 11)).foregroundColor(Palette.grey).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(width: max(200, width - 2 * margin), alignment: .leading)
        .padding(.horizontal, margin)
    }
}

struct TopRow: View {
    @ObservedObject var m: Model
    var body: some View {
        ZStack {
            Text(APP_NAME).font(mono(13, .bold)).foregroundColor(Palette.white).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if m.scan.needsAutomation {
                    WordButton(word: "PERMISSIONS", color: Palette.amber, id: "permissions",
                               label: "Permissions: allow Automation of System Events") { m.askPermission() }
                }
                WordButton(word: "v\(VERSION)", color: Palette.grey, id: "version", label: "Version \(VERSION), open the latest release") {
                    if let u = URL(string: RELEASES) { NSWorkspace.shared.open(u) }
                }
            }
        }
        .padding(.leading, 78).padding(.trailing, 12)
        .frame(height: 38)
    }
}

struct ModeBlock: View {
    @ObservedObject var m: Model
    var s: ScanResult { m.scan }
    var pool: [StartItem] { s.items.filter { $0.changeable && !$0.keep } }
    var keptLine: String { s.keptCount > 0 ? " \(s.keptCount) iLok / PACE item\(s.keptCount == 1 ? " is" : "s are") KEPT on, so your audio plug-ins keep authorising." : "" }

    var nowLine: String {
        let on = pool.filter { $0.on }.count
        if s.items.isEmpty { return "Reading what starts by itself…" }
        // The mode is read from launchd and the login items, item by item: CLEAN while anything that CLEAN START
        // switched off is still off; FULL when FULL START would change nothing.
        switch s.mode {
        case .clean:
            let kept = pool.filter { $0.on && $0.choice == true }.count
            var t = "Now: CLEAN START. \(s.heldOff) item\(s.heldOff == 1 ? " is" : "s are") off for the next start; FULL START brings \(s.heldOff == 1 ? "it" : "them") back."
            let back = pool.filter { $0.on && $0.choice != true }.count
            if back > 0 { t += " \(back) came back on by \(back == 1 ? "itself" : "themselves")." }
            if kept > 0 { t += " \(kept) kept on by your choice." }
            return t + keptLine
        case .full:
            let off = pool.filter { !$0.on }.count
            return "Now: FULL START. \(on) of \(pool.count) items start by themselves" + (off > 0 ? "; \(off) \(off == 1 ? "was" : "were") already off before any CLEAN START, or by your choice." : ".") + keptLine
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                WordButton(word: "CLEAN START", color: s.mode == .clean ? Palette.green : Palette.grey, size: 20, id: "clean",
                           label: "Clean start: switch every item off for the next start") { m.clean() }
                Text("|").font(mono(20)).foregroundColor(Palette.dark)
                WordButton(word: "FULL START", color: s.mode == .full ? Palette.green : Palette.grey, size: 20, id: "full",
                           label: "Full start: bring back everything that was on before the first clean start") { m.full() }
                Text("|").font(mono(20)).foregroundColor(Palette.dark)
                WordButton(word: "RESTART", color: Palette.grey, size: 20, id: "restart",
                           label: "Restart: restart the whole Mac now, apps are asked to save") { m.restartPressed() }
                Spacer(minLength: 0)
                if m.busy { Text("WORKING").font(mono(12, .bold)).foregroundColor(Palette.amber) }
            }
            .disabled(m.busy || s.items.isEmpty)
            Text(nowLine).font(mono(12)).foregroundColor(Palette.white).fixedSize(horizontal: false, vertical: true)
            Text("CLEAN START switches every item below off for the next login and boot; what runs now keeps running until you restart. FULL START brings back everything that was on before the first CLEAN START (it asks for your administrator password once), except what you switched yourself; restart the Mac after either. Apple's own items are never touched.")
                .font(.system(size: 11)).foregroundColor(Palette.grey).fixedSize(horizontal: false, vertical: true)
            if let p = m.engine.testPrefix {
                Text("TEST MODE: only labels starting with \(p) are switched; everything else is shown and locked.")
                    .font(mono(11, .bold)).foregroundColor(Palette.amber).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array((m.status + s.problems).enumerated()), id: \.offset) { _, line in
                let bad = line.contains("did not") || line.hasPrefix("Nothing changed") || line.contains("refused")
                    || line.hasPrefix("Left as") || line.contains("not changed") || line.contains("cannot")
                Text(line).font(.system(size: 11)).foregroundColor(bad ? Palette.amber : Palette.green).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("status")
            }
            if m.askRestart {
                Text("Restart the Mac now? Open apps will be asked to save.").font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("restart.question")
                HStack(spacing: 10) {
                    WordButton(word: "RESTART", color: Palette.amber, id: "restart.yes", label: "Restart the Mac now") { m.restartAnswer(true) }
                    Text("|").font(mono(12)).foregroundColor(Palette.dark)
                    WordButton(word: "CANCEL", color: Palette.grey, id: "restart.no", label: "Cancel, do not restart") { m.restartAnswer(false) }
                }
            }
            if let q = m.confirm {
                Text(q).font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("confirm.question")
                HStack(spacing: 10) {
                    WordButton(word: "SWITCH THE REST", color: Palette.amber, id: "confirm.yes",
                               label: "Switch the rest, leave the Open at Login apps as they are") { m.answer(true) }
                    Text("|").font(mono(12)).foregroundColor(Palette.dark)
                    WordButton(word: "CANCEL", color: Palette.grey, id: "confirm.no", label: "Cancel, change nothing") { m.answer(false) }
                }
            }
        }
    }
}

struct GroupView: View {
    @ObservedObject var m: Model
    let kind: Kind
    var items: [StartItem] { m.scan.items.filter { $0.kind == kind } }

    var body: some View {
        let isOpen = m.open.contains(kind)
        let on = items.filter { $0.on }.count
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if isOpen { m.open.remove(kind) } else { m.open.insert(kind) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isOpen ? "▾" : "▸").font(mono(13)).foregroundColor(Palette.grey)
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(kind.title).font(mono(13, .bold)).foregroundColor(Palette.white)
                         + Text("   \(items.count) · \(on) on").font(mono(12)).foregroundColor(Palette.grey))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(kind.about).font(.system(size: 11)).foregroundColor(Palette.grey)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressHover()
            .accessibilityLabel("\(kind.title.capitalized), \(items.count) items, \(on) on, \(isOpen ? "open" : "closed")")
            .accessibilityIdentifier("group.\(kind.rawValue)")
            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { RowView(m: m, item: $0) }
                }
                .padding(.leading, 21)
            }
        }
    }
}

struct RowView: View {
    @ObservedObject var m: Model
    let item: StartItem

    var meta: String {
        var p = [item.owner, item.kind.short, item.trigger].filter { !$0.isEmpty }
        return p.joined(separator: " · ")
    }
    var lines: [(String, Color)] {
        var l: [(String, Color)] = []
        if item.keep { l.append((item.on ? "iLok / PACE Anti-Piracy: always kept on, CLEAN START never switches it off (your audio plug-ins need it)" : "iLok / PACE Anti-Piracy: found OFF; CLEAN START and FULL START switch it back on", item.on ? Palette.green : Palette.amber)) }
        if let c = item.choice, !item.keep { l.append(("your choice: \(c ? "on" : "off"), kept in both modes", Palette.green)) }
        for w in item.warnings { l.append((w, Palette.amber)) }
        for n in item.notes { l.append((n, Palette.grey)) }
        if item.running { l.append((item.on ? "running now" : "switched off; still running now, until you restart", item.on ? Palette.grey : Palette.amber)) }
        if let w = item.readOnlyWhy { l.append((w, Palette.grey)) }
        return l
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The left column says at a glance what the row is, in words that keep their colour in an inactive window:
            // a switch with ON (green) / OFF (grey) under it; LOCKED (test mode); SETTINGS or SHOWN for read-only rows.
            VStack(alignment: .leading, spacing: 3) {
                if item.changeable {
                    Toggle("", isOn: Binding(get: { item.on }, set: { m.set(item, $0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.green)
                        .disabled(m.busy)
                        .accessibilityLabel("\(item.name) starts by itself")
                        .accessibilityIdentifier("item.\(item.id)")
                    if item.keep {
                        Text(item.on ? "KEPT" : "OFF").font(mono(10, .bold)).foregroundColor(item.on ? Palette.green : Palette.amber)
                            .accessibilityLabel("\(item.name): kept on by CLEAN START")
                    } else {
                        Text(item.on ? "ON" : "OFF").font(mono(10, .bold)).foregroundColor(item.on ? Palette.green : Palette.grey)
                            .accessibilityHidden(true)
                    }
                } else if item.locked && item.switchable {
                    Text(item.keep ? "KEPT" : "LOCKED").font(mono(10, .bold)).foregroundColor(Palette.amber.opacity(0.75)).padding(.top, 2)
                        .accessibilityLabel("\(item.name): locked in test mode, \(item.on ? "on" : "off")")
                    Text(item.on ? "on" : "off").font(mono(10)).foregroundColor(Palette.grey)
                } else if let s = item.settingsURL {
                    WordButton(word: "SETTINGS", color: Palette.grey, size: 10, id: "settings.\(item.id)",
                               label: "Open System Settings for \(item.name)") {
                        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
                    }
                    Text(item.on ? "on" : "off").font(mono(10)).foregroundColor(Palette.grey).padding(.leading, 5)
                } else {
                    Text("SHOWN").font(mono(10, .bold)).foregroundColor(Palette.grey.opacity(0.7)).padding(.top, 3)
                    Text(item.on ? "on" : "off").font(mono(10)).foregroundColor(Palette.grey)
                }
            }
            .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(mono(12, .bold)).foregroundColor(item.on ? Palette.white : Palette.grey)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta).font(.system(size: 11)).foregroundColor(Palette.grey).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l.0).font(.system(size: 11)).foregroundColor(l.1).fixedSize(horizontal: false, vertical: true)
                }
                Text(item.path).font(mono(10)).foregroundColor(Palette.grey.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if !item.runs.isEmpty, item.runs != item.path {
                    Text("runs \(item.runs)").font(mono(10)).foregroundColor(Palette.grey.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
