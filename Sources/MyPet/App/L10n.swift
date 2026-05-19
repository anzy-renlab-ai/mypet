import Foundation

/// Lightweight locale switch. Returns the Chinese string when the user's
/// preferred language is Chinese (zh-Hans / zh-Hant / zh-*), English
/// otherwise. We deliberately ship without `.strings` files for now —
/// mypet only has ~15 UI labels and full Localizable.strings machinery
/// would be heavier than the benefit.
enum L10n {
    static var prefersChinese: Bool {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    }

    static func t(_ en: String, _ zh: String) -> String {
        prefersChinese ? zh : en
    }
}
