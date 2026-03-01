import Foundation
import OSLog

@Observable
final class L10n: @unchecked Sendable {
    static let shared = L10n()

    var locale: String {
        didSet {
            if locale != oldValue {
                loadStrings()
                UserDefaults.standard.set(locale, forKey: "app.locale")
                NotificationCenter.default.post(name: .localeDidChange, object: nil)
            }
        }
    }

    private var strings: [String: String] = [:]

    private init() {
        locale = UserDefaults.standard.string(forKey: "app.locale") ?? "system"
        loadStrings()
    }

    /// Locale identifier suitable for `Locale(identifier:)` and `DateFormatter`.
    var resolvedLocaleIdentifier: String {
        switch resolveLocale() {
        case "zh-Hans": "zh_Hans"
        default: "en_US"
        }
    }

    // MARK: - Lookup

    func t(_ key: String, _ args: String...) -> String {
        var result = strings[key] ?? key
        for (index, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: arg)
        }
        return result
    }

    subscript(_ key: String) -> String {
        t(key)
    }

    // MARK: - Private

    private func resolveLocale() -> String {
        if locale != "system" {
            return locale
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en"
    }

    private func loadStrings() {
        let resolved = resolveLocale()

        guard let url = Bundle.main.url(
            forResource: resolved,
            withExtension: "json",
            subdirectory: "Resources/Locales",
        ) else {
            // Fallback: try without subdirectory (flat bundle)
            if let fallbackURL = Bundle.main.url(forResource: resolved, withExtension: "json") {
                loadFromURL(fallbackURL)
            }
            return
        }
        loadFromURL(url)
    }

    private func loadFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                strings = dict
            }
        } catch {
            let path = url.path
            let desc = error.localizedDescription
            Log.app.error("[L10n] loadStrings failed from \(path, privacy: .public) — \(desc, privacy: .public)")
        }
    }
}

extension Notification.Name {
    static let localeDidChange = Notification.Name("io.github.ender-wang.EdgeMark.localeDidChange")
}
