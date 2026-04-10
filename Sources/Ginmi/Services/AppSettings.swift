import Foundation

enum AppSettings {
    static let recencyWeightEnabledKey = "recencyWeightEnabled"
    static let searchInstalledAppsFallbackEnabledKey = "searchInstalledAppsFallbackEnabled"
    static let commandTabQuickSwitchEnabledKey = "commandTabQuickSwitchEnabled"
    static let commandTabHoldDelayMsKey = "commandTabHoldDelayMs"
    static let excludedWindowTitleKeywordsKey = "excludedWindowTitleKeywords"

    static let recencyWeightEnabledDefault = true
    static let searchInstalledAppsFallbackEnabledDefault = true
    static let commandTabQuickSwitchEnabledDefault = true
    static let commandTabHoldDelayMsDefault = 200
    static let excludedWindowTitleKeywordsDefault = "autofill"
}
