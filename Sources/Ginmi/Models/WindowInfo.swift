import AppKit
import Foundation

struct WindowInfo: Identifiable, Hashable {
    let id: Int
    let ownerPID: pid_t
    let ownerName: String
    let ownerBundleID: String
    let title: String
    let layer: Int
    let isOnScreen: Bool
    let alpha: Double
    let bounds: CGRect

    var boundsSignature: String {
        let x = Int(bounds.origin.x.rounded())
        let y = Int(bounds.origin.y.rounded())
        let w = Int(bounds.size.width.rounded())
        let h = Int(bounds.size.height.rounded())
        return "\(x),\(y),\(w),\(h)"
    }

    var searchableText: String {
        "\(ownerName) \(title)"
    }

    var displayTitle: String {
        title.isEmpty ? ownerName : title
    }

    var identifier: String {
        "\(ownerBundleID)#\(id)#\(displayTitle.lowercased())"
    }
}
