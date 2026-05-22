import Foundation
import OSLog

struct AvailableLocale: Hashable {
    /// Locale code matching the JSON filename (e.g. "en", "zh-Hans", "hi").
    let code: String
    /// Native-script display name (e.g. "English", "简体中文", "हिन्दी").
    let displayName: String
}

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
        resolveLocale().replacingOccurrences(of: "-", with: "_")
    }

    /// All locale JSON files present in the bundle, with their native-script display name.
    /// Discovered dynamically — drop a new `<code>.json` into `EdgeMark/Resources/Locales/` and
    /// it appears here automatically (Xcode 16 synchronized groups handle bundle inclusion).
    static let availableLocales: [AvailableLocale] = {
        var urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Resources/Locales") ?? []
        if urls.isEmpty {
            urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        }
        return urls
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { isLikelyLocaleCode($0) }
            .map { code in
                let id = code.replacingOccurrences(of: "-", with: "_")
                let locale = Locale(identifier: id)
                let name = locale.localizedString(forIdentifier: id)
                return AvailableLocale(code: code, displayName: name ?? code)
            }
            .sorted { $0.code < $1.code }
    }()

    private static func isLikelyLocaleCode(_ name: String) -> Bool {
        // Accept "en", "zh-Hans", "pt-BR" etc. Reject other JSON resources.
        let parts = name.split(separator: "-")
        guard let first = parts.first, (2 ... 3).contains(first.count),
              first.allSatisfy(\.isLetter) else { return false }
        return true
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
        let primary = preferred.split(separator: "-").first.map(String.init) ?? "en"
        // Match against discovered locales — exact match first, then language-prefix match.
        let codes = L10n.availableLocales.map(\.code)
        if codes.contains(preferred) { return preferred }
        if let match = codes.first(where: { $0.split(separator: "-").first.map(String.init) == primary }) {
            return match
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
