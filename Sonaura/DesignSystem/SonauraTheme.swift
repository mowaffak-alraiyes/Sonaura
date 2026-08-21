//
//  SonauraTheme.swift
//  Sonaura
//
//  The visual identity for the v2 reframe (see PRD.md and
//  docs/design-system.md): an instrument, not a diagnosis. Dark is the
//  designed-for primary mode — a hi-fi faceplate, not an inverted afterthought
//  — with light mode carrying the same language in a warm paper register.
//
//  Replaces: the stock `LinearGradient(colors: [.blue, .purple])` that was
//  defined independently in two places in ContentView.swift, and the literal
//  `Color.red`/`Color.green` response buttons that read as a pass/fail
//  instrument's stoplights rather than as a calm, repeatable check-in.
//
import SwiftUI

/// The "Embers" palette: indigo → plum → rose → coral on dark navy.
///
/// `41436A` · `984063` · `F64668` · `FE9677`
///
/// Chosen for a structural reason, not only an aesthetic one: **Embers
/// contains no green.** A green/red pair is the pass/fail vocabulary of a
/// clinical instrument, and the v2 reframe exists to retire exactly that
/// framing (PRD.md §3.1, §3.4). Because every color here sits on one
/// warm-to-cool ramp, a result's color reads as *position on a scale* rather
/// than as correct/incorrect — which is precisely the distinction between
/// "your response is a little softer this month" and "you failed."
///
/// Dark is the designed-for primary mode. Light mode carries the same ramp
/// with the saturated tones darkened for contrast on a pale ground.
enum SonauraColor {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The panel itself — the deep navy the Embers ramp sits on.
    static let background = dynamic(light: hex(0xF6F4F6), dark: hex(0x212A3B))

    /// Cards, the meter face.
    static let surface = dynamic(light: hex(0xFFFFFF), dark: hex(0x2B3648))

    /// A slightly-elevated panel, one step up from `surface`.
    static let surfaceElevated = dynamic(light: hex(0xEFEDF2), dark: hex(0x35415A))

    static let text = dynamic(light: hex(0x232A3B), dark: hex(0xEDEFF5))

    static let muted = dynamic(light: hex(0x6C7488), dark: hex(0x949DB4))

    static let border = dynamic(light: hex(0xDDE1EA), dark: hex(0x3B4659))

    /// The needle — Embers rose. The one place full saturation is spent, so
    /// it never competes with anything else on screen.
    static let accent = dynamic(light: hex(0xD62E51), dark: hex(0xF64668))

    /// Accent-colored text needing more contrast than `accent` gives on its
    /// own surface. Reaches for the warmer coral end of the ramp.
    static let accentInk = dynamic(light: hex(0xA8324B), dark: hex(0xFE9677))

    /// A result in the range you'd expect — Embers indigo. It recedes toward
    /// the background family on purpose: "nothing to see here" should look
    /// like nothing to see.
    static let steady = dynamic(light: hex(0x41436A), dark: hex(0x8B90CE))

    static let steadySoft = dynamic(light: hex(0xE7E8F1), dark: hex(0x2E3457))

    /// A real, worth-attention change — Embers coral. Warm and bright enough
    /// to draw the eye, nowhere near alarm red. Serious content stays serious
    /// in its *words* (PRD §6); the color never escalates to a siren.
    static let worthALook = dynamic(light: hex(0xC2543C), dark: hex(0xFE9677))

    static let worthALookSoft = dynamic(light: hex(0xFBE7DF), dark: hex(0x4A2E2A))

    /// Embers plum — the ramp's midpoint. For chart gradients and soft fills
    /// that need to sit between indigo and rose.
    static let ember = dynamic(light: hex(0x984063), dark: hex(0x984063))
}

enum SonauraFont {
    /// A reading being announced — a result headline, a section title.
    /// Stands in for Instrument Serif (see docs/design-system.md §5) until a
    /// bundled font pass; `.serif` + italic gets most of the character today
    /// with zero bundling risk.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }

    /// Everything else. System default, matching Dynamic Type.
    static func body(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default).weight(weight)
    }

    /// A reading: dB values, frequencies, dates — anywhere a number should
    /// feel like it came off a meter. Stands in for Martian Mono.
    static func readout(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

/// One reusable card surface, replacing ad-hoc `RoundedRectangle` + shadow
/// combinations scattered per-screen.
struct SonauraCard<Content: View>: View {
    var elevated: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(elevated ? SonauraColor.surfaceElevated : SonauraColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(SonauraColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The vocabulary a result is described in — "Steady," not "pass"/"fail."
/// Deliberately three states, not a spectrum of five: the point of the
/// reframe is a description, not a graded score.
enum SonauraResultTone {
    case steady
    case attention

    var color: Color {
        switch self {
        case .steady: return SonauraColor.steady
        case .attention: return SonauraColor.worthALook
        }
    }

    var softColor: Color {
        switch self {
        case .steady: return SonauraColor.steadySoft
        case .attention: return SonauraColor.worthALookSoft
        }
    }
}

/// A quiet label — "steady," "worth a look" — never a colored bar chart or a
/// pass/fail badge. Used wherever the app used to show a raw dB band.
struct SonauraResultPill: View {
    let text: String
    let tone: SonauraResultTone

    var body: some View {
        Text(text)
            .font(SonauraFont.readout(.caption2))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.softColor)
            .clipShape(Capsule())
    }
}
