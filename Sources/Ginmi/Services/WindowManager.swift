import AppKit
import ApplicationServices
import Foundation

protocol WindowManaging {
    func fetchAllWindows() -> [WindowInfo]
    func icon(for window: WindowInfo) -> NSImage
    func currentFrontmostWindowID() -> Int?
    @discardableResult
    func activate(window: WindowInfo) -> Bool
}

final class WindowManager: WindowManaging {
    private let debugWindowList = ProcessInfo.processInfo.environment["GINMI_DEBUG_WINDOWS"] == "1"
    private let debugWindowFiltering = ProcessInfo.processInfo.environment["GINMI_DEBUG_WINDOWS_VERBOSE"] == "1"

    func fetchAllWindows() -> [WindowInfo] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var seenWindowIDs = Set<Int>()
        var seenSignatures = Set<String>()
        var dedupedWindows: [WindowInfo] = []
        var titleAllocationCursor: [String: Int] = [:]

        for info in infoList {
            guard
                let windowID = info[kCGWindowNumber as String] as? Int,
                let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                let layer = info[kCGWindowLayer as String] as? Int
            else {
                continue
            }

            guard layer == 0 else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "layer!=0", info: info)
                continue
            }
            guard ownerName != "Window Server", ownerName != "Dock" else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "system-owner", info: info)
                continue
            }
            guard !ownerName.localizedCaseInsensitiveContains("UIViewService") else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "UIViewService-owner", info: info)
                continue
            }

            let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard let bounds = boundsRect(from: info[kCGWindowBounds as String]) else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "missing-bounds", info: info)
                continue
            }
            guard bounds.size.width > 1, bounds.size.height > 1 else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "zero-size-bounds", info: info)
                continue
            }
            let boundsKey = boundsSignature(from: bounds)

            let pid = pid_t(ownerPID)
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? "unknown"
            guard ownerPID != ProcessInfo.processInfo.processIdentifier else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "own-process", info: info)
                continue
            }
            guard bundleID != Bundle.main.bundleIdentifier else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "own-app", info: info)
                continue
            }
            guard seenWindowIDs.insert(windowID).inserted else {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "duplicate-window-id", info: info)
                continue
            }

            let cgTitle = info[kCGWindowName as String] as? String ?? ""
            let axTitle: String?
            if cgTitle.isEmpty {
                let allocationKey = "\(ownerPID)|\(boundsKey)"
                let candidates = fetchAXTitleCandidates(pid: pid, windowID: windowID, bounds: bounds)
                if candidates.isEmpty {
                    axTitle = nil
                } else {
                    let cursor = titleAllocationCursor[allocationKey, default: 0]
                    let selectedIndex = min(cursor, candidates.count - 1)
                    axTitle = candidates[selectedIndex]
                    titleAllocationCursor[allocationKey] = cursor + 1
                }
            } else {
                axTitle = nil
            }
            let rawTitle = (axTitle?.isEmpty == false ? axTitle : cgTitle) ?? cgTitle
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            if title.isEmpty && app?.activationPolicy == .accessory {
                debugDrop(windowID: windowID, ownerName: ownerName, reason: "empty-title-accessory-app", info: info)
                continue
            }

            // Only signature-dedupe untitled surfaces. Titled windows may legitimately share title/bounds.
            if title.isEmpty {
                let signature = "\(bundleID)|<empty>|\(boundsKey)"
                guard seenSignatures.insert(signature).inserted else {
                    debugDrop(windowID: windowID, ownerName: ownerName, reason: "duplicate-signature:\(signature)", info: info)
                    continue
                }
            }

            dedupedWindows.append(WindowInfo(
                id: windowID,
                ownerPID: pid,
                ownerName: ownerName,
                ownerBundleID: bundleID,
                title: title,
                layer: layer,
                isOnScreen: onScreen,
                alpha: alpha,
                bounds: bounds
            ))
        }

        dedupedWindows = dedupedWindows.filter { window in
            let keep = shouldKeepWindow(window)
            if debugWindowFiltering, !keep {
                print("DROP_FILTER id=\(window.id) pid=\(window.ownerPID) bundle=\(window.ownerBundleID) app=\(window.ownerName) title=\"\(window.title)\" bounds=\(window.boundsSignature)")
            }
            return keep
        }
        dedupedWindows = filterGenericUntitledCompanions(dedupedWindows)
        dedupedWindows = collapseDuplicateTitledWindows(dedupedWindows)

        if debugWindowList {
            debugLogWindows(dedupedWindows)
        }

        return dedupedWindows
    }

    func icon(for window: WindowInfo) -> NSImage {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else {
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        return app.icon ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    func currentFrontmostWindowID() -> Int? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return fallbackFrontmostWindowID()
        }

        let pid = frontmostApp.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            return fallbackFrontmostWindowID()
        }

        let appElement = AXUIElementCreateApplication(pid)
        let focusedWindow = copyAXWindow(
            attribute: kAXFocusedWindowAttribute as CFString,
            from: appElement
        ) ?? copyAXWindow(
            attribute: kAXMainWindowAttribute as CFString,
            from: appElement
        )

        let focusedTitle = focusedWindow.flatMap { copyAXString(attribute: kAXTitleAttribute as CFString, element: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedBounds = focusedWindow.flatMap { copyAXRect(element: $0) }

        if debugWindowFiltering || debugWindowList {
            print(
                "FRONTMOST_APP pid=\(pid) bundle=\(frontmostApp.bundleIdentifier ?? "unknown") " +
                    "title=\"\(focusedTitle ?? "")\" bounds=\(focusedBounds.map(boundsSignature(from:)) ?? "unknown")"
            )
        }

        if let matched = matchFrontmostWindowID(pid: pid, title: focusedTitle, bounds: focusedBounds) {
            return matched
        }

        return fallbackFrontmostWindowID(preferredPID: pid)
    }

    @discardableResult
    func activate(window: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return false }
        app.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(window.ownerPID)
        guard let windows = copyAXWindows(for: appElement) else { return true }

        var bestMatch: AXUIElement?
        for axWindow in windows {
            let title = copyAXString(attribute: kAXTitleAttribute as CFString, element: axWindow)
            if title?.trimmingCharacters(in: .whitespacesAndNewlines) == window.title {
                bestMatch = axWindow
                break
            }
        }

        guard let target = bestMatch ?? windows.first else { return true }

        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        return true
    }

    private func fetchAXTitleCandidates(pid: pid_t, windowID: Int, bounds: CGRect) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAXWindows(for: appElement) else { return [] }

        var boundsMatchTitles: [String] = []
        for window in windows {
            if let axWindowID = copyAXInt(attribute: "AXWindowNumber", element: window), axWindowID == windowID {
                if let title = copyAXString(attribute: kAXTitleAttribute as CFString, element: window), !title.isEmpty {
                    return [title]
                }
            }

            if let axBounds = copyAXRect(element: window), rectsRoughlyEqual(axBounds, bounds) {
                let title = copyAXString(attribute: kAXTitleAttribute as CFString, element: window)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty, !boundsMatchTitles.contains(title) {
                    boundsMatchTitles.append(title)
                }
            }
        }
        return boundsMatchTitles
    }

    private func copyAXWindows(for appElement: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            return nil
        }
        return windows
    }

    private func copyAXWindow(attribute: CFString, from appElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, attribute, &value)
        guard result == .success, let window = value else { return nil }
        return unsafeDowncast(window, to: AXUIElement.self)
    }

    private func copyAXString(attribute: CFString, element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copyAXInt(attribute: String, element: AXUIElement) -> Int? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private func copyAXRect(element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard
            positionResult == .success,
            sizeResult == .success,
            let positionObject = positionValue,
            let sizeObject = sizeValue
        else {
            return nil
        }
        let positionAX = positionObject as! AXValue
        let sizeAX = sizeObject as! AXValue

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionAX) == .cgPoint, AXValueGetValue(positionAX, .cgPoint, &point) else {
            return nil
        }
        guard AXValueGetType(sizeAX) == .cgSize, AXValueGetValue(sizeAX, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private func rectsRoughlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 3 &&
            abs(lhs.origin.y - rhs.origin.y) < 3 &&
            abs(lhs.size.width - rhs.size.width) < 3 &&
            abs(lhs.size.height - rhs.size.height) < 3
    }

    private func boundsRect(from raw: Any?) -> CGRect? {
        guard let dict = raw as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    private func boundsSignature(from rect: CGRect) -> String {
        let x = Int(rect.origin.x.rounded())
        let y = Int(rect.origin.y.rounded())
        let w = Int(rect.size.width.rounded())
        let h = Int(rect.size.height.rounded())
        return "\(x),\(y),\(w),\(h)"
    }

    private func matchFrontmostWindowID(pid: pid_t, title: String?, bounds: CGRect?) -> Int? {
        guard
            let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let candidates = infoList.compactMap { info -> (id: Int, title: String, bounds: CGRect)? in
            guard
                let windowID = info[kCGWindowNumber as String] as? Int,
                let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                ownerPID == pid,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let cgBounds = boundsRect(from: info[kCGWindowBounds as String])
            else {
                return nil
            }

            let cgTitle = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (windowID, cgTitle, cgBounds)
        }

        if let title {
            if let exactTitleAndBounds = candidates.first(where: { candidate in
                candidate.title == title && bounds.map { rectsRoughlyEqual(candidate.bounds, $0) } != false
            }) {
                return exactTitleAndBounds.id
            }

            if let exactTitle = candidates.first(where: { $0.title == title }) {
                return exactTitle.id
            }
        }

        if let bounds, let exactBounds = candidates.first(where: { rectsRoughlyEqual($0.bounds, bounds) }) {
            return exactBounds.id
        }

        return candidates.first?.id
    }

    private func fallbackFrontmostWindowID(preferredPID: pid_t? = nil) -> Int? {
        guard
            let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        if let preferredPID {
            for info in infoList {
                guard
                    let windowID = info[kCGWindowNumber as String] as? Int,
                    let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                    ownerPID == preferredPID,
                    let layer = info[kCGWindowLayer as String] as? Int,
                    layer == 0
                else {
                    continue
                }
                return windowID
            }
        }

        for info in infoList {
            guard
                let windowID = info[kCGWindowNumber as String] as? Int,
                let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                let ownerName = info[kCGWindowOwnerName as String] as? String
            else {
                continue
            }

            guard ownerName != "Window Server", ownerName != "Dock" else { continue }
            let pid = pid_t(ownerPID)
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
            guard bundleID != Bundle.main.bundleIdentifier else { continue }
            return windowID
        }

        return nil
    }

    private func shouldKeepWindow(_ window: WindowInfo) -> Bool {
        if !window.title.isEmpty {
            return true
        }

        let width = window.bounds.size.width
        let height = window.bounds.size.height

        // Ignore title-bar-like helper surfaces commonly emitted by Chromium/Electron.
        if height <= 60, width >= 600 {
            return false
        }

        // Ignore tiny floating utility artifacts.
        if width <= 120 || height <= 120 {
            return false
        }

        return true
    }

    func filterGenericUntitledCompanions(_ windows: [WindowInfo]) -> [WindowInfo] {
        let groupedByPID = Dictionary(grouping: windows, by: \.ownerPID)
        var kept: [WindowInfo] = []
        kept.reserveCapacity(windows.count)

        for window in windows {
            let siblings = groupedByPID[window.ownerPID] ?? []
            let hasTitledSibling = siblings.contains { $0.id != window.id && !$0.title.isEmpty }
            let shouldDrop = window.title.isEmpty && hasTitledSibling

            if shouldDrop {
                if debugWindowFiltering || debugWindowList {
                    print(
                        "DROP_COMPANION id=\(window.id) pid=\(window.ownerPID) bundle=\(window.ownerBundleID) app=\(window.ownerName) " +
                            "title=\"\(window.title)\" bounds=\(window.boundsSignature) reason=untitled-companion-to-titled-window"
                    )
                }
                continue
            }

            kept.append(window)
        }

        return kept
    }

    func collapseDuplicateTitledWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var groupedIndices: [String: [Int]] = [:]

        for (index, window) in windows.enumerated() {
            let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedTitle.isEmpty else { continue }
            let key = "\(window.ownerPID)|\(normalizedTitle)|\(window.boundsSignature)"
            groupedIndices[key, default: []].append(index)
        }

        var keptByKey: [String: WindowInfo] = [:]
        for (key, indices) in groupedIndices {
            let candidates = indices.map { windows[$0] }
            let best = candidates.max { lhs, rhs in
                if lhs.isOnScreen != rhs.isOnScreen {
                    return !lhs.isOnScreen && rhs.isOnScreen
                }
                if lhs.alpha != rhs.alpha {
                    return lhs.alpha < rhs.alpha
                }
                return lhs.id > rhs.id
            }
            if let best {
                keptByKey[key] = best
            }
        }

        var collapsed: [WindowInfo] = []
        collapsed.reserveCapacity(windows.count)

        for window in windows {
            let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedTitle.isEmpty else {
                collapsed.append(window)
                continue
            }

            let key = "\(window.ownerPID)|\(normalizedTitle)|\(window.boundsSignature)"
            guard let kept = keptByKey[key] else {
                collapsed.append(window)
                continue
            }

            if kept.id == window.id {
                collapsed.append(window)
            } else if debugWindowFiltering || debugWindowList {
                print(
                    "DROP_DUPLICATE_TITLED id=\(window.id) pid=\(window.ownerPID) bundle=\(window.ownerBundleID) app=\(window.ownerName) " +
                        "title=\"\(window.title)\" bounds=\(window.boundsSignature) kept=\(kept.id)"
                )
            }
        }

        return collapsed
    }

    private func debugDrop(windowID: Int, ownerName: String, reason: String, info: [String: Any]) {
        guard debugWindowFiltering else { return }
        let pid = info[kCGWindowOwnerPID as String] as? Int ?? -1
        let title = (info[kCGWindowName as String] as? String) ?? ""
        let bounds = boundsRect(from: info[kCGWindowBounds as String]).map(boundsSignature(from:)) ?? "unknown"
        print("DROP_RAW id=\(windowID) pid=\(pid) app=\(ownerName) title=\"\(title)\" bounds=\(bounds) reason=\(reason)")
    }

    private func debugLogWindows(_ windows: [WindowInfo]) {
        print("=== Ginmi Window Dump (count: \(windows.count)) ===")
        for window in windows {
            print(
                "id=\(window.id) pid=\(window.ownerPID) bundle=\(window.ownerBundleID) app=\(window.ownerName) " +
                    "title=\"\(window.title)\" emptyTitle=\(window.title.isEmpty) bounds=\(window.boundsSignature) onScreen=\(window.isOnScreen) alpha=\(window.alpha)"
            )
        }

        let groups = Dictionary(grouping: windows) { "\($0.ownerBundleID)|\($0.title.lowercased())" }
        let duplicates = groups.filter { $0.value.count > 1 }
        if duplicates.isEmpty {
            print("No duplicate groups by [bundleID + title].")
        } else {
            print("Duplicate groups by [bundleID + title]:")
            for (key, groupedWindows) in duplicates.sorted(by: { $0.key < $1.key }) {
                print("group=\(key) count=\(groupedWindows.count)")
                for window in groupedWindows.sorted(by: { $0.id < $1.id }) {
                    print("  -> id=\(window.id) bounds=\(window.boundsSignature) onScreen=\(window.isOnScreen) alpha=\(window.alpha)")
                }
            }
        }
        print("=== End Ginmi Window Dump ===")
    }
}
