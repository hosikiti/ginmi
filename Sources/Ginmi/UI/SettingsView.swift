import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage("recencyWeightEnabled") private var recencyWeightEnabled = true
    @AppStorage("searchInstalledAppsFallbackEnabled") private var searchInstalledAppsFallbackEnabled = true

    let shortcutsStore: SearchShortcutStore

    var body: some View {
        Form {
            Section("Main Hotkey") {
                KeyboardShortcuts.Recorder("Show search panel", name: .openSearch)
            }

            Section("Behavior") {
                Toggle("Use recency weighting", isOn: $recencyWeightEnabled)
                Toggle("Include installed apps in search results", isOn: $searchInstalledAppsFallbackEnabled)
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
