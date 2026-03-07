import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage("recencyWeightEnabled") private var recencyWeightEnabled = true

    let shortcutsStore: SearchShortcutStore

    var body: some View {
        Form {
            Section("Main Hotkey") {
                KeyboardShortcuts.Recorder("Show search panel", name: .openSearch)
            }

            Section("Behavior") {
                Toggle("Use recency weighting", isOn: $recencyWeightEnabled)
            }

            Section("Data") {
                Button("Reset learned shortcuts") {
                    shortcutsStore.resetShortcuts()
                }
            }
        }
        .padding()
        .frame(width: 420)
    }
}
