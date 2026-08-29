//
//  TerminalFont.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "i would like the same nerd font im using in my terminal be the
//  standard font in my apps that have to work like my desktop terminal."
//
//  His Terminal.app profile "Clear Dark" uses PostScript name MesloLGMNF-Regular — Meslo
//  LG M, a Menlo derivative, patched with Nerd Font glyphs. We bundle the MONO variant
//  (MesloLGMNFM-*): the Nerd Font patch adds powerline and icon glyphs that are wider than
//  a cell, and only the Mono build forces them back to a single advance width. In a
//  terminal, columns lining up IS the typeface's job.
//
//  REGISTERED AT RUNTIME, NOT VIA UIAppFonts. The target uses GENERATE_INFOPLIST_FILE, so
//  there is no Info.plist to add an array to. CTFontManagerRegisterGraphicsFont needs no
//  plist entry and fails loudly, which is better than a silent fallback to the system font.
//
import CoreText
import SwiftUI

enum TerminalFont {
    /// PostScript names, not filenames — `Font.custom` wants these.
    static let regular = "MesloLGMNFM-Regular"
    static let bold = "MesloLGMNFM-Bold"

    private static var registered = false

    /// Idempotent. Call before the first view renders.
    static func register() {
        guard !registered else { return }
        registered = true
        for name in ["MesloLGMNerdFontMono-Regular",
                     "MesloLGMNerdFontMono-Bold",
                     "MesloLGMNerdFontMono-Italic",
                     "MesloLGMNerdFontMono-BoldItalic"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf"),
                  let data = NSData(contentsOf: url),
                  let provider = CGDataProvider(data: data),
                  let font = CGFont(provider) else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            // Already-registered is not a failure — a preview or a second scene can call this.
            if !CTFontManagerRegisterGraphicsFont(font, &error) {
                let code = CFErrorGetCode(error?.takeUnretainedValue())
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    assertionFailure("Could not register \(name): \(String(describing: error))")
                }
            }
        }
    }

    /// Scales with Dynamic Type instead of pinning a point size — he reads this on a phone
    /// in bed and on a 13-inch iPad, and a fixed size cannot serve both.
    static func mono(_ style: Font.TextStyle = .callout) -> Font {
        .custom(regular, size: UIFont.preferredFont(forTextStyle: uiStyle(style)).pointSize)
    }

    private static func uiStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle: return .largeTitle
        case .title:      return .title1
        case .title2:     return .title2
        case .title3:     return .title3
        case .headline:   return .headline
        case .subheadline:return .subheadline
        case .body:       return .body
        case .callout:    return .callout
        case .footnote:   return .footnote
        case .caption:    return .caption1
        case .caption2:   return .caption2
        @unknown default: return .callout
        }
    }
}
