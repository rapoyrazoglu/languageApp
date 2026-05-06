import Foundation

/// Map an ISO 639 language code to a flag emoji. Flags are not languages —
/// English isn't "British" — but as a UI affordance they're the most legible
/// at-a-glance signal a learner has. We pick the most common political
/// region per language for the demo; community packs can ship with any code
/// and we fall back to a globe glyph if there's no entry.
enum LanguageFlag {
    static func emoji(for languageCode: String) -> String {
        let normalised = languageCode.lowercased()
        if let exact = mapping[normalised] {
            return regionalIndicator(exact)
        }
        // Strip a region suffix like "zh-Hans" → "zh"
        if let dashIdx = normalised.firstIndex(of: "-") {
            let base = String(normalised[..<dashIdx])
            if let exact = mapping[base] {
                return regionalIndicator(exact)
            }
        }
        return "🌐"
    }

    /// "For X speakers" label localised through the catalog. The %@ slot
    /// receives the language's display name in the *user's* current locale
    /// (so a Turkish UI sees "Türkçe konuşanlar için", an English UI sees
    /// "For Turkish speakers").
    static func speakerLabel(for uiLanguageCode: String) -> String {
        let format = NSLocalizedString("forXSpeakers", comment: "Section header for packs targeting native speakers of a language")
        return String(format: format, displayName(for: uiLanguageCode))
    }

    /// Display name of a language in the *user's* current locale. Falls back
    /// to a hand-curated English table for codes Apple doesn't ship a name
    /// for (e.g. zh-Hans / zh-Hant), and ultimately to the raw code.
    static func displayName(for languageCode: String) -> String {
        let lower = languageCode.lowercased()
        if let exact = Locale.current.localizedString(forLanguageCode: lower) {
            return exact
        }
        if let fallback = Self.displayNames[lower] {
            return fallback
        }
        return languageCode
    }

    // MARK: - Internals

    private static func regionalIndicator(_ countryCode: String) -> String {
        let base = UInt32(0x1F1E6) - UInt32(Character("A").asciiValue!)
        var s = ""
        for ch in countryCode.uppercased().unicodeScalars {
            guard ch.isASCII, ch.value >= 65, ch.value <= 90 else { continue }
            if let scalar = Unicode.Scalar(base + ch.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s.isEmpty ? "🌐" : s
    }

    /// Best-effort language-code → ISO 3166 country code. Edit freely; not
    /// authoritative — there's no canonical "language flag".
    private static let mapping: [String: String] = [
        "en": "US",
        "tr": "TR",
        "de": "DE",
        "es": "ES",
        "fr": "FR",
        "it": "IT",
        "pt": "PT",
        "ru": "RU",
        "nl": "NL",
        "ja": "JP",
        "ko": "KR",
        "zh": "CN",
        "zh-hans": "CN",
        "zh-hant": "TW",
        "ar": "SA",
        "he": "IL",
        "hi": "IN",
        "vi": "VN",
        "th": "TH",
        "id": "ID",
        "pl": "PL",
        "sv": "SE",
        "no": "NO",
        "fi": "FI",
        "da": "DK",
        "el": "GR",
        "cs": "CZ",
        "hu": "HU",
        "uk": "UA",
        "ro": "RO",
    ]

    private static let displayNames: [String: String] = [
        "en": "English",
        "tr": "Turkish",
        "de": "German",
        "es": "Spanish",
        "fr": "French",
        "it": "Italian",
        "pt": "Portuguese",
        "ru": "Russian",
        "nl": "Dutch",
        "ja": "Japanese",
        "ko": "Korean",
        "zh": "Chinese",
        "zh-hans": "Chinese (Simplified)",
        "zh-hant": "Chinese (Traditional)",
    ]
}
