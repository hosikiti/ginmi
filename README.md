# Ginmi

Ginmi is a lightweight macOS window switcher focused on the Contexts-style fuzzy search flow: hit a hotkey, type 2-4 chars, jump directly to the exact window.

## Features

- Global hotkey panel (`Control + Space` by default, configurable)
- `Cmd + Tab` replacement flow for window switching
- Fuzzy search over app name + window title (Fuse-based ranking)
- Learned shortcuts: query -> preferred window persistence in `UserDefaults`
- Optional installed-app results appended after matching running windows
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

## Build a DMG

```bash
bash scripts/build-dmg.sh
```

Outputs:

- `dist/Ginmi.app`
- `dist/Ginmi-0.1.0.dmg`

Optional overrides:

```bash
VERSION=0.1.1 BUNDLE_ID=com.example.ginmi bash scripts/build-dmg.sh
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
- Recency weighting toggle
- Include installed apps in search results
- Reset learned shortcuts

## Architecture

- `Sources/Ginmi/GinmiApp.swift`: app lifecycle and service wiring
- `Sources/Ginmi/Services/WindowManager.swift`: CGWindow + AX window discovery and activation
- `Sources/Ginmi/Services/FuzzySearcher.swift`: Fuse-driven ranking and boosting
- `Sources/Ginmi/UI/SearchPanelView.swift`: floating panel UI
- `Sources/Ginmi/UI/SearchPanelController.swift`: panel lifecycle and key navigation
- `Sources/Ginmi/UI/SettingsView.swift`: hotkeys and behavior settings

## Notes

- AX window matching uses title fallback where direct IDs are unavailable.

## License

MIT. See `LICENSE`.
