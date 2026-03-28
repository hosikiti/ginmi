import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage("recencyWeightEnabled") private var recencyWeightEnabled = true
    @AppStorage("searchInstalledAppsFallbackEnabled") private var searchInstalledAppsFallbackEnabled = true
    @AppStorage("commandTabQuickSwitchEnabled") private var commandTabQuickSwitchEnabled = true
    @AppStorage("commandTabHoldDelayMs") private var commandTabHoldDelayMs = 300
    @AppStorage("excludedWindowTitleKeywords") private var excludedWindowTitleKeywords = "autofill"

    let shortcutsStore: SearchShortcutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Main Hotkey") {
                HStack(alignment: .center, spacing: 16) {
                    Text("Show search panel")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .openSearch)
                }
            }

            settingsSection("Behavior") {
                Toggle("Use recency weighting", isOn: $recencyWeightEnabled)
                Toggle("Include installed apps in search results", isOn: $searchInstalledAppsFallbackEnabled)
                Toggle("Enable Cmd+Tab quick switch", isOn: $commandTabQuickSwitchEnabled)
                HStack(alignment: .center, spacing: 12) {
                    Text("Cmd+Tab hold delay")
                    Spacer()
                    TextField("300", value: $commandTabHoldDelayMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .disabled(!commandTabQuickSwitchEnabled)
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
                Text(
                    commandTabQuickSwitchEnabled
                        ? "Hold Cmd longer than this delay to show the switcher. Release earlier to jump to the previous window."
                        : "Quick switch is disabled. Cmd+Tab shows the switcher immediately."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded window title keywords")
                    TextEditor(text: $excludedWindowTitleKeywords)
                        .font(.body)
                        .frame(height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                    Text("Use comma, semicolon, or a new line to add multiple patterns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Example: autofill, private, floating panel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsSection("Data") {
                Button("Reset learned shortcuts") {
                    shortcutsStore.resetShortcuts()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .frame(width: 640, height: 500)
        .onChange(of: commandTabHoldDelayMs) { _, newValue in
            commandTabHoldDelayMs = max(0, newValue)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }
}
