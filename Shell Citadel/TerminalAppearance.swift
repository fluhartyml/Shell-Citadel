//
//  TerminalAppearance.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "I also want the terminal fontsize and color, background, user
//  configurable with mine given first launch as example."
//
//  THE DEFAULTS ARE LITERALLY HIS. Read out of his Terminal.app profile "Clear Dark" on
//  2026-08-29 rather than guessed: text 0.1055 0.9274 0.1650, the green in every photo he
//  has sent of that window. A customer who never opens these settings gets his setup,
//  which is a working example rather than a beige default nobody chose.
//
import Combine
import SwiftUI

@MainActor
final class TerminalAppearance: ObservableObject {
    static let shared = TerminalAppearance()

    /// His Terminal.app text color, measured from the profile, not eyeballed.
    static let michaelGreen = RGB(r: 0.1055125362, g: 0.9273828125, b: 0.1650446741)
    /// MEASURED off his external monitor on 2026-08-29, not guessed: rgb(32, 37, 49), the
    /// dominant background of the terminal window in the photo he sent. Near-black was my
    /// invention and it was wrong — his is a dark navy.
    static let michaelNavy = RGB(r: 0.1255, g: 0.1451, b: 0.1922)

    struct RGB: Codable, Equatable {
        var r: Double, g: Double, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    // HIS SIZE, NOT A SAFE SMALL ONE. Michael, 2026-08-29: "the font is a quarter of the
    // size on my terminal." His Terminal.app profile is 36pt, so that is the default —
    // the whole point of seeding from his setup is that it arrives looking like his.
    /// Bumped when the seeded defaults change, so an install that already stored the old
    /// ones gets them replaced ONCE rather than being stuck with a 13pt near-black screen
    /// he never chose. Michael, 2026-08-29: "can you overide for first launch to be like
    /// the photo i just sent you?"
    @AppStorage("term.seedVersion") private var seedVersion = 0
    private static let currentSeed = 2

    @AppStorage("term.fontSize") var fontSize: Double = 36

    // ── GEOMETRY. Michael, 2026-08-29: "i think old terminals were 80x24 characters x
    // lines" — he is right, that is the VT100 and it is still what a remote shell assumes
    // unless told otherwise. "User configures characters x lines."
    //
    // ⚠️ ON A FIXED SCREEN YOU CANNOT SET BOTH FONT SIZE AND COLUMNS. One determines the
    // other, which is why a desktop terminal resizes its WINDOW rather than its font. So:
    // when `fitToColumns` is on, the column count is authoritative and the point size is
    // derived from the available width. Turn it off and the slider wins, and the column
    // count becomes whatever actually fits — reported back so it is never a mystery.
    // 85, his number, given 2026-08-30 09:05: "85x20 green nerd font". The previous 84
    // was measured off his Terminal.app title bar on the 29th; he has since said 85, and
    // his number wins over my measurement of his window.
    @AppStorage("term.cols") var cols: Int = 85
    @AppStorage("term.rows") var rows: Int = 20
    @AppStorage("term.fitToColumns") var fitToColumns: Bool = true
    @AppStorage("term.text") private var textData = Data()
    @AppStorage("term.bg") private var bgData = Data()

    var text: RGB {
        get { (try? JSONDecoder().decode(RGB.self, from: textData)) ?? Self.michaelGreen }
        set { textData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }

    var background: RGB {
        get { (try? JSONDecoder().decode(RGB.self, from: bgData)) ?? Self.michaelNavy }
        set { bgData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }

    var font: Font { .custom(TerminalFont.regular, size: fontSize) }

    // ── TWO TONES OFF ONE COLOUR ────────────────────────────────────────────────
    // Michael, 2026-08-30 07:12: "i need the text from me to be a darker shade than the
    // text from you", refined at 09:06: "i want the gren from me to be darker and text
    // from you to be lighter".
    //
    // ⚠️ BOTH ARE DERIVED FROM `text`, NEVER HARD-CODED. He sets the terminal color
    // himself, so "darker" has to mean darker THAN WHATEVER HE CHOSE — a fixed pair of
    // greens would fight his palette and would be wrong the moment he changed it.
    //
    // Done in HSB so hue and saturation are untouched and only brightness moves: the two
    // lines stay recognizably the same color, which is the point. Two different hues
    // would read as two different meanings rather than two speakers.

    /// ⚠️ ONE CONSTANT, APPLIED ZERO ONE OR TWO TIMES. Michael, 2026-08-30 09:18:
    /// "you and peercentages is opening a can of worms" — and he is right, a table of four
    /// hand-tuned percentages is four things to be wrong about and nothing to reason from.
    ///
    /// So there is a single dim step. Whichever line should recede gets it once more than
    /// the other, and a light background gets it once more again because his green is a
    /// bright color and bright is unreadable on white.
    ///
    ///                     Claude      Michael
    ///   dark background   base        base·d
    ///   light background  base·d      base·d²
    ///
    /// His rule is preserved in both — his own lines are always the dimmer of the pair —
    /// and there is exactly ONE number to change if it is wrong.
    static let dim = 0.6

    /// His own lines. Always one step dimmer than Claude's, so scrolling back, his words
    /// recede and the answers stand out.
    func mineColor(dark: Bool) -> Color {
        Self.shift(text.color, brightness: dark ? Self.dim : Self.dim * Self.dim)
    }

    /// Claude's lines. Full strength on a dark background; stepped down once on a light
    /// one, because the green he chose was chosen against near-black.
    func theirsColor(dark: Bool) -> Color {
        Self.shift(text.color, brightness: dark ? 1 : Self.dim)
    }

    /// Multiply brightness in HSB, clamped, so hue and saturation are untouched and the
    /// two lines stay recognizably one color. Two hues would read as two meanings rather
    /// than two speakers. Returns the color unchanged if it cannot be read as RGB at all,
    /// which is safer than returning something invented.
    private static func shift(_ color: Color, brightness factor: Double) -> Color {
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getHue(&h, saturation: &sat, brightness: &b, alpha: &a) else {
            return color
        }
        return Color(hue: h, saturation: sat, brightness: min(1, max(0, b * factor)), opacity: a)
    }

    /// Meslo is monospaced, so one glyph's advance is the whole story. Measured once from
    /// the real font rather than assumed, because a wrong ratio silently misreports the
    /// geometry to the far end and `top` or `nano` then draws off the edge.
    static func advanceWidth(at size: Double) -> Double {
        let f = UIFont(name: TerminalFont.regular, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: f]).width
    }

    /// The point size at which `cols` characters exactly fill `width`.
    static func sizeToFit(columns: Int, width: Double) -> Double {
        guard columns > 0, width > 0 else { return 13 }
        let unit = advanceWidth(at: 100)          // linear in point size
        return max(6, min(60, (width / Double(columns)) / (unit / 100)))
    }

    /// How many whole characters fit at the current size.
    static func columnsThatFit(width: Double, at size: Double) -> Int {
        max(1, Int(width / advanceWidth(at: size)))
    }

    /// Called once at launch. Replaces stored appearance with the current seed if this
    /// install predates it, then never touches his choices again.
    func applySeedIfOutdated() {
        guard seedVersion < Self.currentSeed else { return }
        reset()
        seedVersion = Self.currentSeed
    }

    func reset() {
        text = Self.michaelGreen
        background = Self.michaelNavy
        fontSize = 36
        cols = 84
        rows = 20
        fitToColumns = true
    }
}

/// Font size, ink and paper. Deliberately three settings and not a theme engine — the
/// three things he actually named.
struct AppearanceSettingsView: View {
    @ObservedObject var appearance = TerminalAppearance.shared

    var body: some View {
        Section {
            // ⚠️ THE LABEL HAS TO NAME THE CONSEQUENCE, NOT THE MECHANISM.
            // Michael, 2026-08-30 11:49: "The lable of the toggle was not obvious so i
            // saw it resize with the slider." He had already asked, minutes earlier,
            // whether the dead slider had a snap — "Fit to columns" told him what the
            // feature is called and nothing about what it DOES to the control right
            // below it. A user reading a greyed-out slider should not have to infer the
            // cause from a two-word label above it.
            Toggle(isOn: $appearance.fitToColumns) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fit to columns")
                    Text("Columns set the text size. Turn off to use the slider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $appearance.cols, in: 20...200, step: 1) {
                LabeledContent("Columns") { Text("\(appearance.cols)") }
            }
            Stepper(value: $appearance.rows, in: 10...100, step: 1) {
                LabeledContent("Lines") { Text("\(appearance.rows)") }
            }
            VStack(alignment: .leading, spacing: 6) {
                // Greyed WITH the slider, so the row reads as off together. A live-looking
                // label above a dead control is what made this ambiguous.
                LabeledContent("Size") {
                    Text(appearance.fitToColumns ? "from columns" : "\(Int(appearance.fontSize)) pt")
                }
                .foregroundStyle(appearance.fitToColumns ? .secondary : .primary)
                Slider(value: $appearance.fontSize, in: 6...60, step: 1)
                    .disabled(appearance.fitToColumns)
            }
            ColorPicker("Text", selection: Binding(
                get: { appearance.text.color },
                set: { appearance.text = rgb(from: $0) ?? appearance.text }))
            ColorPicker("Background", selection: Binding(
                get: { appearance.background.color },
                set: { appearance.background = rgb(from: $0) ?? appearance.background }))
            Button("Use Michael's Terminal look") { appearance.reset() }
        } header: {
            Text("Terminal appearance")
        } footer: {
            Text("Starts as the profile from his Mac's Terminal — Meslo, green on his dark navy. 85 by 20 is his own Terminal window; 80 by 24 is the classic VT100, and the column count is what gets reported to the far end so full-screen programs draw correctly. With Fit to columns on, the columns set the text size and the slider is switched off — on a fixed screen one determines the other. Change any of it; it applies to every tab.")
        }
        .previewSample(appearance: appearance)
    }

    private func rgb(from color: Color) -> TerminalAppearance.RGB? {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return .init(r: Double(r), g: Double(g), b: Double(b))
    }
}

private extension View {
    /// A live sample, because a color picker without one is a guess.
    func previewSample(appearance: TerminalAppearance) -> some View {
        self.listRowBackground(Color(.secondarySystemGroupedBackground))
    }
}
