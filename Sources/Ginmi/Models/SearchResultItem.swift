import Foundation

struct SearchResultItem: Identifiable {
    enum Kind {
        case window(WindowInfo)
        case app(InstalledAppInfo)
    }

    let kind: Kind
    let score: Double

    var id: String {
        switch kind {
        case let .window(window):
            return "window-\(window.id)"
        case let .app(app):
            return "app-\(app.id)"
        }
    }

    var primaryText: String {
        switch kind {
        case let .window(window):
            return window.displayTitle
        case let .app(app):
            return app.name
        }
    }

    var secondaryText: String {
        switch kind {
        case let .window(window):
            return window.ownerName
        case .app:
            return ""
        }
    }

    var rowAppName: String {
        switch kind {
        case let .window(window):
            return window.ownerName
        case let .app(app):
            return app.name
        }
    }

    var rowTitle: String {
        switch kind {
        case let .window(window):
            return window.displayTitle
        case .app:
            return ""
        }
    }

    var rowTrailingLabel: String? {
        switch kind {
        case let .window(window):
            return window.desktopLabel
        case .app:
            return nil
        }
    }

    var searchableText: String {
        switch kind {
        case let .window(window):
            return window.searchableText
        case let .app(app):
            return app.name
        }
    }
}
