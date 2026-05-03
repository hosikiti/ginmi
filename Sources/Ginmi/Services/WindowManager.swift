import AppKit
import ApplicationServices
import Foundation

protocol WindowManaging {
    func fetchAllWindows() -> [WindowInfo]
    func fetchCachedWindows() -> [WindowInfo]
    func predictedFrontmostWindowID() -> Int?
    func prewarmWindowCache()
    func icon(for window: WindowInfo) -> NSImage
    func currentFrontmostWindowID() -> Int?
    @discardableResult
    func activate(window: WindowInfo) -> Bool
}

final class WindowManager: WindowManaging, @unchecked Sendable {
    private enum DefaultsKey {
        static let excludedWindowTitleKeywords = "excludedWindowTitleKeywords"
    }

    private enum CGWindowDictionaryKey {
        static let workspace = "kCGWindowWorkspace"
    }

    private struct AXTitleCacheEntry {
        let titles: [String]
        let date: Date
    }

    private let defaults: UserDefaults
    private let debugWindowList = ProcessInfo.processInfo.environment["GINMI_DEBUG_WINDOWS"] == "1"
    private let debugWindowFiltering = ProcessInfo.processInfo.environment["GINMI_DEBUG_WINDOWS_VERBOSE"] == "1"
    private let windowCacheTTL: TimeInterval = 0.75
    private let cacheLock = NSLock()
    private let cacheRefreshQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Ginmi.WindowCacheRefresh"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let axTitleCacheTTL: TimeInterval = 15
    private let axTitleCacheLock = NSLock()
    private var cachedWindows: [WindowInfo]?
    private var cacheDate: Date?
    private var cacheRefreshInFlight = false
    private var trackedFrontmostWindowID: Int?
    private var trackedFrontmostPID: pid_t?
    private var axTitleCandidateCache: [String: AXTitleCacheEntry] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func fetchAllWindows() -> [WindowInfo] {
        let total = PerfLogger.start("window_manager.fetch_all_windows")
        if let cached = cachedWindowSnapshot(requiringFreshness: true) {
            PerfLogger.end("window_manager.fetch_all_windows", from: total, details: "source=fresh_cache count=\(cached.count)")
            return cached
        }

        if let cached = cachedWindowSnapshot(requiringFreshness: false) {
            scheduleWindowCacheRefresh()
            PerfLogger.end("window_manager.fetch_all_windows", from: total, details: "source=stale_cache count=\(cached.count)")
            return cached
        }

        let fresh = PerfLogger.measure("window_manager.compute_all_windows_sync") {
            computeAllWindows()
        }
        storeWindowCache(fresh)
        PerfLogger.end("window_manager.fetch_all_windows", from: total, details: "source=sync_compute count=\(fresh.count)")
        return fresh
    }

    func fetchCachedWindows() -> [WindowInfo] {
        PerfLogger.measure("window_manager.fetch_cached_windows") {
            let cached = cachedWindowSnapshot(requiringFreshness: false) ?? []
            PerfLogger.log("cached_windows_count=\(cached.count)")
            return cached
        }
    }

    func predictedFrontmostWindowID() -> Int? {
        let total = PerfLogger.start("window_manager.predicted_frontmost_window_id")
        let windows = fetchCachedWindows()
        guard !windows.isEmpty else {
            PerfLogger.end("window_manager.predicted_frontmost_window_id", from: total, details: "source=no_cached_windows")
            return nil
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let trackedWindowID: Int?
        let trackedPID: pid_t?
        cacheLock.lock()
        trackedWindowID = trackedFrontmostWindowID
        trackedPID = trackedFrontmostPID
        cacheLock.unlock()

        if let trackedWindowID,
           let tracked = windows.first(where: {
               $0.id == trackedWindowID && (frontmostPID == nil || $0.ownerPID == frontmostPID)
           })
        {
            PerfLogger.end("window_manager.predicted_frontmost_window_id", from: total, details: "source=tracked_window id=\(tracked.id)")
            return tracked.id
        }

        if let frontmostPID,
           let predicted = bestPredictedWindow(from: windows.filter { $0.ownerPID == frontmostPID })
        {
            PerfLogger.end("window_manager.predicted_frontmost_window_id", from: total, details: "source=frontmost_pid id=\(predicted.id)")
            return predicted.id
        }

        if let trackedPID,
           let predicted = bestPredictedWindow(from: windows.filter { $0.ownerPID == trackedPID })
        {
            PerfLogger.end("window_manager.predicted_frontmost_window_id", from: total, details: "source=tracked_pid id=\(predicted.id)")
            return predicted.id
        }

        let predicted = bestPredictedWindow(from: windows)?.id
        PerfLogger.end("window_manager.predicted_frontmost_window_id", from: total, details: "source=fallback id=\(predicted.map(String.init) ?? "nil")")
        return predicted
    }

    func prewarmWindowCache() {
        PerfLogger.log("window_manager.prewarm_window_cache")
        scheduleWindowCacheRefresh(force: true)
    }

    func invalidateWindowCache() {
        cacheLock.lock()
        cacheDate = nil
        cacheLock.unlock()
    }

    private func computeAllWindows() -> [WindowInfo] {
        let total = PerfLogger.start("window_manager.compute_all_windows")
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            PerfLogger.end("window_manager.compute_all_windows", from: total, details: "result=no_info_list")
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
            let workspaceID = (info[CGWindowDictionaryKey.workspace] as? NSNumber)?.intValue
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
                let candidates: [String]
                if shouldAttemptAXTitleLookup(cgTitle: cgTitle, bounds: bounds, app: app) {
                    candidates = fetchAXTitleCandidates(pid: pid, windowID: windowID, bounds: bounds)
                } else {
                    candidates = []
                }
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
                workspaceID: workspaceID,
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

        PerfLogger.end("window_manager.compute_all_windows", from: total, details: "count=\(dedupedWindows.count) raw_count=\(infoList.count)")
        return dedupedWindows
    }

    func icon(for window: WindowInfo) -> NSImage {
        let start = PerfLogger.start("window_manager.icon", details: "app=\(window.ownerName)")
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else {
            PerfLogger.end("window_manager.icon", from: start, details: "app=\(window.ownerName) source=empty")
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        let icon = app.icon ?? NSImage(size: NSSize(width: 16, height: 16))
        PerfLogger.logIfSlow(stage: "window_manager.icon", from: start, thresholdMs: 1.5, details: "app=\(window.ownerName)")
        return icon
    }

    func currentFrontmostWindowID() -> Int? {
        let total = PerfLogger.start("window_manager.current_frontmost_window_id")
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            let fallback = fallbackFrontmostWindowID()
            PerfLogger.end("window_manager.current_frontmost_window_id", from: total, details: "source=no_frontmost_app id=\(fallback.map(String.init) ?? "nil")")
            return fallback
        }

        let pid = frontmostApp.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            let fallback = fallbackFrontmostWindowID()
            PerfLogger.end("window_manager.current_frontmost_window_id", from: total, details: "source=own_process_fallback id=\(fallback.map(String.init) ?? "nil")")
            return fallback
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
            trackFrontmostWindow(windowID: matched, pid: pid)
            PerfLogger.end("window_manager.current_frontmost_window_id", from: total, details: "source=ax_match id=\(matched)")
            return matched
        }

        let fallback = fallbackFrontmostWindowID(preferredPID: pid)
        trackFrontmostWindow(windowID: fallback, pid: pid)
        PerfLogger.end("window_manager.current_frontmost_window_id", from: total, details: "source=fallback id=\(fallback.map(String.init) ?? "nil")")
        return fallback
    }

    @discardableResult
    func activate(window: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return false }
        app.activate(options: [.activateAllWindows])
        trackFrontmostWindow(windowID: window.id, pid: window.ownerPID)

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
        let start = PerfLogger.start("window_manager.fetch_ax_title_candidates", details: "pid=\(pid) window_id=\(windowID)")
        let cacheKey = "\(pid)|\(boundsSignature(from: bounds))"
        if let cached = cachedAXTitleCandidates(for: cacheKey) {
            PerfLogger.end(
                "window_manager.fetch_ax_title_candidates",
                from: start,
                details: "result=cache_hit count=\(cached.count)"
            )
            return cached
        }

        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = copyAXWindows(for: appElement) else {
            storeAXTitleCandidates([], for: cacheKey)
            PerfLogger.end("window_manager.fetch_ax_title_candidates", from: start, details: "result=no_windows")
            return []
        }

        var boundsMatchTitles: [String] = []
        for window in windows {
            if let axWindowID = copyAXInt(attribute: "AXWindowNumber", element: window), axWindowID == windowID {
                if let title = copyAXString(attribute: kAXTitleAttribute as CFString, element: window), !title.isEmpty {
                    storeAXTitleCandidates([title], for: cacheKey)
                    PerfLogger.end("window_manager.fetch_ax_title_candidates", from: start, details: "result=exact_window_id count=1")
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
        storeAXTitleCandidates(boundsMatchTitles, for: cacheKey)
        PerfLogger.logIfSlow(
            stage: "window_manager.fetch_ax_title_candidates",
            from: start,
            thresholdMs: 2.0,
            details: "pid=\(pid) window_id=\(windowID) count=\(boundsMatchTitles.count)"
        )
        return boundsMatchTitles
    }

    private func cachedAXTitleCandidates(for key: String) -> [String]? {
        axTitleCacheLock.lock()
        defer { axTitleCacheLock.unlock() }

        guard let entry = axTitleCandidateCache[key] else { return nil }
        guard Date().timeIntervalSince(entry.date) < axTitleCacheTTL else {
            axTitleCandidateCache.removeValue(forKey: key)
            return nil
        }
        return entry.titles
    }

    private func storeAXTitleCandidates(_ titles: [String], for key: String) {
        axTitleCacheLock.lock()
        axTitleCandidateCache[key] = AXTitleCacheEntry(titles: titles, date: Date())
        axTitleCacheLock.unlock()
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

    private func cachedWindowSnapshot(requiringFreshness: Bool) -> [WindowInfo]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cachedWindows else { return nil }
        if requiringFreshness {
            guard let cacheDate, Date().timeIntervalSince(cacheDate) < windowCacheTTL else {
                return nil
            }
        }
        return cachedWindows
    }

    private func storeWindowCache(_ windows: [WindowInfo]) {
        cacheLock.lock()
        cachedWindows = windows
        cacheDate = Date()
        cacheRefreshInFlight = false
        cacheLock.unlock()
    }

    private func scheduleWindowCacheRefresh(force: Bool = false) {
        cacheLock.lock()
        let isFresh = cacheDate.map { Date().timeIntervalSince($0) < windowCacheTTL } ?? false
        if cacheRefreshInFlight || (!force && isFresh) {
            cacheLock.unlock()
            return
        }
        cacheRefreshInFlight = true
        cacheLock.unlock()

        cacheRefreshQueue.addOperation { [weak self] in
            guard let self else { return }
            let windows = self.computeAllWindows()
            self.storeWindowCache(windows)
        }
    }

    private func trackFrontmostWindow(windowID: Int?, pid: pid_t?) {
        cacheLock.lock()
        trackedFrontmostWindowID = windowID
        trackedFrontmostPID = pid
        cacheLock.unlock()
    }

    private func bestPredictedWindow(from windows: [WindowInfo]) -> WindowInfo? {
        windows.max { lhs, rhs in
            if lhs.isOnScreen != rhs.isOnScreen {
                return !lhs.isOnScreen && rhs.isOnScreen
            }

            if lhs.alpha != rhs.alpha {
                return lhs.alpha < rhs.alpha
            }

            let lhsArea = lhs.bounds.size.width * lhs.bounds.size.height
            let rhsArea = rhs.bounds.size.width * rhs.bounds.size.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }

            return lhs.id < rhs.id
        }
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

    func shouldKeepWindow(_ window: WindowInfo) -> Bool {
        let normalizedTitle = window.displayTitle.lowercased()
        let ownerName = window.ownerName.lowercased()
        let bundleID = window.ownerBundleID.lowercased()
        let keywords = excludedTitleKeywords()
        let isExcludedByKeyword = keywords.contains { keyword in
            normalizedTitle.contains(keyword) || ownerName.contains(keyword) || bundleID.contains(keyword)
        }
        if isExcludedByKeyword {
            return false
        }

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

    func shouldAttemptAXTitleLookup(cgTitle: String, bounds: CGRect, app: NSRunningApplication?) -> Bool {
        if !cgTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if app?.activationPolicy == .accessory {
            return false
        }

        let width = bounds.size.width
        let height = bounds.size.height

        // Title-bar strips and menu-like bars are almost never real candidate windows.
        if height <= 60, width >= 600 {
            return false
        }

        // Tiny floating surfaces are almost always helper artifacts.
        if width <= 120 || height <= 120 {
            return false
        }

        return true
    }

    private func excludedTitleKeywords() -> [String] {
        let configured = defaults.string(forKey: DefaultsKey.excludedWindowTitleKeywords) ?? ""
        let parsed = configured
            .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        if parsed.isEmpty {
            return ["autofill"]
        }
        return parsed
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
