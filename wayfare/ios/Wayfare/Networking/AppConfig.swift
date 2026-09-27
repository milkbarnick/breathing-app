import Foundation

/// Build-time and debug configuration.
enum AppConfig {
    /// Used when the Info.plist value is missing or still a placeholder.
    static let fallbackBaseURL = "https://wayfare-api.example.workers.dev"

    /// UserDefaults key for the DEBUG-only server override (Settings → Developer).
    static let debugOverrideKey = "debug.apiBaseURLOverride"

    /// `APIBaseURL` from Info.plist (`$(API_BASE_URL)` in Config.xcconfig), without a trailing slash.
    static var defaultBaseURLString: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(API_BASE_URL)" or a URL cut by an xcconfig "//" comment ("https:") is useless.
        guard trimmed.hasPrefix("http"), trimmed.contains("://"), URL(string: trimmed) != nil else {
            return fallbackBaseURL
        }
        return stripTrailingSlash(trimmed)
    }

    /// The URL requests go to. In DEBUG builds a Settings override wins.
    static var apiBaseURLString: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: debugOverrideKey),
           !override.isEmpty, URL(string: override) != nil {
            return stripTrailingSlash(override)
        }
        #endif
        return defaultBaseURLString
    }

    static var appVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        return "\(version) (\(build))"
    }

    static let privacyPolicyURL = URL(string: "https://wayfare.app/privacy")
    static let termsURL = URL(string: "https://wayfare.app/terms")
    static let supportEmailURL = URL(string: "mailto:support@wayfare.app")

    /// "sandbox" in DEBUG builds, "production" otherwise (TestFlight and App Store use production APNs).
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static func stripTrailingSlash(_ text: String) -> String {
        var result = text
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
