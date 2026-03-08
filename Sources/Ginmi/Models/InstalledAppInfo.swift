import AppKit
import Foundation

struct InstalledAppInfo: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String
    let url: URL

    var id: String {
        bundleIdentifier.isEmpty ? url.path : bundleIdentifier
    }
}
