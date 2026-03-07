You are an expert macOS Swift developer specializing in accessibility APIs and performant UI. Build a complete, open-source macOS app called **Ginmi** (inspired by Japanese 吟味 = careful consideration / discernment) that replicates the core window-switching experience of the discontinued Contexts app (contexts.co), focusing precisely on its signature fuzzy search behavior.

Target: macOS 15.0+ (Sequoia and later), sandbox-compatible, notarization-ready, lightweight (<10 MB installed).

Tech stack (strictly use these):

- Swift 6 + SwiftUI (for views) + AppKit (for window management, events, hotkeys)
- Swift Package Manager only
- Dependency: https://github.com/sindresorhus/KeyboardShortcuts (for user-configurable global hotkeys)
- Fuzzy search: Use https://github.com/krisk/fuse-swift (lightweight, zero deps, supports scoring with position bonuses, acronym-like via word starts) — or fallback to https://github.com/ukushu/Ifrit if needed. Do NOT implement fuzzy from scratch unless the libs fail basic needs.
- Accessibility APIs: AXUIElement + CGWindowListCopyWindowInfo for window enumeration, titles, app icons, bundle IDs, activation.
- Persistence: Use @AppStorage or UserDefaults for search shortcuts (query → preferred window ID mapping)

Core mission: Enable switching to any individual window (not just apps) with 2–4 keystrokes via smart fuzzy search on app name + window title. Prioritize minimal friction and learning behavior.

Must-have features (implement in this exact priority — MVP = 1–2 first):

1. **Main Search Panel (MVP — must feel identical to Contexts search)**
   - Global hotkey trigger (default: ⌃ Space / Control+Space, fully user-customizable in settings via KeyboardShortcuts)
   - On trigger: Show small, centered floating NSPanel (SwiftUI hosted) on the active/current screen:
     - Auto-focused single-line TextField
     - Real-time results list below: each row = app icon (16×16 or 32×32) + window title (truncate long ones) + app name in smaller gray if helpful
   - Fetch ALL open windows (including minimized, hidden, fullscreen, across Spaces/displays) using CGWindowListCopyWindowInfo + Accessibility for accurate/current titles/icons.
   - Filter out invalid/irrelevant windows (e.g. ignore desktop, menu bar, dock, your own app windows).
   - Request Accessibility permissions on first launch with a clear onboarding sheet explaining why.
   - Fuzzy matching MUST match Contexts exactly as described:
     - Non-consecutive chars anywhere in app name OR window title (combine both into one searchable string per window, e.g. "Safari – My Tab Title")
     - Strong priority for acronym matches: higher score for matches at start of app name and start of words in title (use fuse options like includeScore + shouldSort + tokenize + location/threshold tuning to favor word starts / camelCase)
     - When query empty: show recent/frequent windows sorted by recency + usage count
   - Navigation: Arrow up/down to select, Return to switch + hide panel, Esc to cancel
   - On selection: Use Accessibility or NSWorkspace to activate/bring front the exact window (AXRaise + AXFocusedWindow tricks if needed)

2. **Search Shortcuts (learning / persistence)**
   - When user selects a window for a given query (even partial like "s"), remember that query → that specific window (store window number or persistent identifier if possible, fallback to title+app bundle).
   - Next time same/very similar query typed → boost that window to #1 result (even if newer windows match).
   - Store in UserDefaults as [String: String] (query lowercase trimmed → window identifier string)
   - Clear old entries periodically or allow reset in settings

3. **Fast Search mode (Contexts' killer feature for ultra-speed)**
   - Configurable hold-modifier hotkey (default: Fn key if possible, or user chooses e.g. ⌥ Option, ⇧ Shift, ⌘ etc.)
   - While modifier held: show search panel immediately (even if no chars typed yet)
   - As user types 1–few chars (while holding): real-time fuzzy filter
   - On release of modifier: automatically switch to the currently selected (top) result and hide panel — no need to press Return
   - If no results or Esc pressed while holding → cancel, no switch
   - Combine with search shortcuts: e.g. hold Fn + "s" → instantly switch to learned Safari window on release
   - Use NSEvent monitoring or modifierFlags check to detect hold/release

4. **Polish & extras (after core works)**
   - Settings window: change main hotkey, Fast Search modifier, toggle recency weighting, reset shortcuts, launch at login
   - Menu bar icon (optional, toggleable) for quick access/settings
   - Dark mode / vibrant blur background on panel
   - Snappy performance: debounce search input ~100ms, cache window list briefly
   - Handle multi-monitor: panel on screen with mouse or active app

Project structure requirements:

- SPM package + Xcode project structure
- Clean files: GinmiApp.swift, SearchPanelView.swift, WindowManager.swift, FuzzySearcher.swift, SettingsView.swift, etc.
- Include MIT LICENSE, detailed README.md (build/run instructions, permissions needed, screenshots placeholders, how to customize)
- .gitignore standard for macOS/Swift

Output format:

1. Full proposed file/directory structure
2. Every file one by one with complete code in ```swift blocks (title each with path like Sources/Ginmi/WindowManager.swift)
3. Final section: exact Terminal commands to create folder, init SPM/git, add dependencies (e.g. swift package init --type executable, then edit Package.swift), build/run in Xcode

Make Ginmi feel lightweight, instant, and deeply respectful of the Contexts magic: fast fuzzy + learning + modifier-hold instant-switch. Prioritize correctness of fuzzy scoring and Fast Search flow above all.

Begin generating the full project now.
