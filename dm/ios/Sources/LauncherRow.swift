// One launcher setting as a row (a menu, a slider with its percentage, a toggle), shared by the iOS launcher (Launcher.swift) and the Mac app's settings window (dm/mac/Launcher.swift).
// A row whose setting is fixed by an env file or by the launch environment is shown but disabled.
import SwiftUI

extension LauncherModel {
    func binding(_ s: Setting) -> Binding<String> { Binding(get: { self.values[s.env] ?? s.def }, set: { self.values[s.env] = $0 }) }
}

struct SettingRow: View {
    let s: Setting
    @ObservedObject var m: LauncherModel

    private var locked: Bool { m.fixed.contains(s.env) }
    private var note: String {
        guard locked else { return s.note }
        return (s.note.isEmpty ? "" : s.note + " · ") + (m.fromLaunch.contains(s.env) ? "Set at launch" : "Set by an env file")
    }
    private var rangeValue: Binding<Double> {
        Binding(get: { Double(m.values[s.env] ?? s.def) ?? s.max ?? 1 },
                set: { m.values[s.env] = String(format: "%.2f", $0) })
    }
    private var percentage: String { m.rangeLabel(s, rangeValue.wrappedValue) }

    private var settingLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.label)
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    var body: some View {
        Group {
            switch s.kind {
            case "choice":
                Picker(selection: m.binding(s)) {
                    ForEach(s.options ?? [], id: \.[0]) { Text($0[1]).tag($0[0]) }
                } label: {
                    settingLabel
                }
                .pickerStyle(.menu)
            case "range":
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingLabel
                        Spacer()
                        Text(percentage).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: rangeValue, in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05)
                        .accessibilityLabel(s.label)
                        .accessibilityValue(percentage)
                }
            default:
                Toggle(isOn: Binding(get: { (m.values[s.env] ?? s.def) == s.onValue }, set: { m.values[s.env] = $0 ? s.onValue : s.offValue })) {
                    settingLabel
                }
            }
        }
        .disabled(locked)
    }
}

/// Button mapping: what each button of a connected controller sends to the game (DM_PAD_MAP, dm/host/input_map.h), kept as the saved choice launcher.DM_PAD_MAP.
/// The Mac's launcher.c applies that saved choice itself (saved_control); the iOS launcher puts it in the environment at Play (Launcher.swift applyPadMap).
/// Only the buttons the player changed are kept ("A=B,B=A"); the touch gamepad and the Mac keyboard are not mapped. Not a launcher.json row: a map is none of its kinds
let padMapKey = "launcher.DM_PAD_MAP"
let padMapButtons: [(name: String, label: String)] = [
    ("A", "A"), ("B", "B"), ("X", "X"), ("Y", "Y"), ("L", "L"), ("R", "R"), ("ZL", "ZL"), ("ZR", "ZR"), ("Plus", "+"), ("Minus", "−"),
    ("LS", "Left stick press"), ("RS", "Right stick press"), ("Up", "D-pad up"), ("Down", "D-pad down"), ("Left", "D-pad left"), ("Right", "D-pad right"),
]   // input_map.h's names for the 16 buttons
/// The saved map as button -> what it sends ("none" for nothing); entries that are not two known names are left out, as the host leaves them out
func padMapParse(_ s: String) -> [String: String] {
    let names = Set(padMapButtons.map(\.name))
    var m: [String: String] = [:]
    for entry in s.split(separator: ",") {
        let p = entry.split(separator: "=", maxSplits: 1).map(String.init)
        if p.count == 2, names.contains(p[0]), names.contains(p[1]) || p[1] == "none" { m[p[0]] = p[1] }
    }
    return m
}
func padMapText(_ m: [String: String]) -> String {
    padMapButtons.compactMap { b in m[b.name].flatMap { $0 == b.name ? nil : "\(b.name)=\($0)" } }.joined(separator: ",")
}

struct ButtonMappingSection: View {
    let fixed: Bool   // an env file or the launch set DM_PAD_MAP: it wins, so the rows are shown but disabled
    @AppStorage(padMapKey) private var saved = ""
    @State private var open = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $open) {
                ForEach(padMapButtons, id: \.name) { b in
                    Picker(b.label, selection: sends(b.name)) {
                        ForEach(padMapButtons, id: \.name) { t in Text(t.label).tag(t.name) }
                        Text("Nothing").tag("none")
                    }
                }
                Button("Reset buttons") { saved = "" }.disabled(saved.isEmpty)
            } label: {
                HStack { Text("Controller buttons"); Spacer(); Text(summary).foregroundStyle(.secondary) }
            }
            .disabled(fixed)
        } header: { Text("Button mapping") } footer: {
            Text(fixed ? "Set by an env file or at launch." : "What each button on a connected controller sends to the game. The on-screen controls keep their own buttons.")
        }
    }

    private var summary: String { let n = padMapParse(saved).count; return n == 0 ? "As printed" : n == 1 ? "1 changed" : "\(n) changed" }
    private func sends(_ name: String) -> Binding<String> {
        Binding(get: { padMapParse(saved)[name] ?? name },
                set: { v in var m = padMapParse(saved); m[name] = v == name ? nil : v; saved = padMapText(m) })
    }
}
