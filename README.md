# Ginmi

Ginmi is a lightweight macOS window switcher focused on the Contexts-style fuzzy search flow: hit a hotkey, type 2-4 chars, jump directly to the exact window.

## Features

- Global hotkey panel (`Control + Space` by default, configurable)
- Fuzzy search over app name + window title (Fuse-based ranking)
- Learned shortcuts: query -> preferred window persistence in `UserDefaults`
- Fast Search mode: hold a modifier (Fn by default), type, release to switch
- Accessibility-backed window focusing for per-window activation

## Requirements

- macOS 15.0+
- Xcode 16+ (Swift 6)

## Build and run

```bash
swift build
swift run Ginmi
```

To open in Xcode:

```bash
open Package.swift
```

## Permissions

Ginmi requires **Accessibility** permission to enumerate and raise windows.

On first run, Ginmi prompts for access. You can also enable manually:

1. Open System Settings
2. Privacy & Security -> Accessibility
3. Enable Ginmi

## Configuration

Open the app settings and configure:

- Main global hotkey
- Fast Search hold modifier
- Recency weighting toggle
- Reset learned shortcuts

## Architecture

- `Sources/Ginmi/GinmiApp.swift`: app lifecycle and service wiring
- `Sources/Ginmi/Services/WindowManager.swift`: CGWindow + AX window discovery and activation
- `Sources/Ginmi/Services/FuzzySearcher.swift`: Fuse-driven ranking and boosting
- `Sources/Ginmi/UI/SearchPanelView.swift`: floating panel UI
- `Sources/Ginmi/UI/SearchPanelController.swift`: panel lifecycle and key navigation
- `Sources/Ginmi/UI/SettingsView.swift`: hotkeys and behavior settings

## Notes

- Fast Search with Fn depends on hardware/keyboard behavior for `flagsChanged` events.
- AX window matching uses title fallback where direct IDs are unavailable.

## License

MIT. See `LICENSE`.
