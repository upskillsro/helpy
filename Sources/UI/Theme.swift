import SwiftUI
import AppKit
import CoreText

// MARK: - Hex

extension Color {
    /// 0xRRGGBB literal, optional alpha. Keeps the palette below readable as
    /// the same hex values that were signed off in the design mockups.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Palette

/// Helpy has ONE design. It ships in two appearances that follow the system:
/// "Sky" (light) and "Midnight" (dark). There is no user-facing theme picker
/// and no translucency — every surface is an opaque, explicit color.
///
/// Views never branch on appearance themselves; they read a token:
///     @Environment(\.colorScheme) private var colorScheme
///     private var t: HelpyPalette { .forScheme(colorScheme) }
struct HelpyPalette {
    // Canvas & surfaces
    let canvas: Color
    let surface: Color
    let surfaceHover: Color
    var surfaceActive: Color
    var surfaceActiveBorder: Color
    let line: Color

    // Type
    let ink: Color
    let ink2: Color
    let muted: Color
    let muted2: Color

    // Brand
    var accent: Color
    /// The header block. Flat on purpose: a single opaque colour is easier to
    /// keep legible than a sweep (one contrast number instead of a range), and
    /// it matches the no-glass, no-translucency rule the rest of the theme follows.
    var header: Color
    let onAccent: Color

    // Progress rails
    let railTrack: Color
    var rail: Color

    // Status
    let warm: Color        // break + overtime
    let hot: Color         // time's up
    let success: Color

    // Chips
    let chipFill: Color
    let chipText: Color
    let chipHotFill: Color
    let chipHotText: Color

    // Controls & fields
    let checkBorder: Color
    let fieldFill: Color
    let fieldBorder: Color
    let placeholder: Color
    let controlIcon: Color
    let controlHoverFill: Color
    let dangerHoverFill: Color
    let dangerHoverIcon: Color
    let goHoverFill: Color
    let goHoverIcon: Color

    // Floating pill & detached panels
    let pillFill: Color
    let pillBorder: Color
    let panelFill: Color
    let panelBorder: Color

    static let light = HelpyPalette(
        canvas: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xF8FAFE),
        surfaceHover: Color(hex: 0xF1F6FE),
        surfaceActive: Color(hex: 0xF2F7FF),
        surfaceActiveBorder: Color(hex: 0xD9E6FF),
        line: Color(hex: 0xE4EBF7),

        ink: Color(hex: 0x0B1424),
        ink2: Color(hex: 0x14203A),
        muted: Color(hex: 0x7387A8),
        muted2: Color(hex: 0x94A3BC),

        accent: Color(hex: 0x0B33FF),
        header: Color(hex: 0x0086E8),
        onAccent: Color.white,

        railTrack: Color(hex: 0xEDF2FA),
        rail: Color(hex: 0x0086E8),

        warm: Color(hex: 0xE8760F),
        hot: Color(hex: 0xE04422),
        success: Color(hex: 0x1E8E5A),

        chipFill: Color(hex: 0xEAF1FD),
        chipText: Color(hex: 0x7387A8),
        chipHotFill: Color(hex: 0xFFEEE7),
        chipHotText: Color(hex: 0xD9542B),

        checkBorder: Color(hex: 0xC1D0E8),
        fieldFill: Color(hex: 0xF8FAFE),
        fieldBorder: Color(hex: 0xE4EBF7),
        placeholder: Color(hex: 0x94A3BC),
        controlIcon: Color(hex: 0x5A6D8C),
        controlHoverFill: Color(hex: 0xEFF4FC),
        dangerHoverFill: Color(hex: 0xFFEDE7),
        dangerHoverIcon: Color(hex: 0xE04422),
        goHoverFill: Color(hex: 0xE7F6EE),
        goHoverIcon: Color(hex: 0x1E8E5A),

        pillFill: Color(hex: 0xFFFFFF),
        pillBorder: Color(hex: 0x102246, opacity: 0.09),
        panelFill: Color(hex: 0xFFFFFF),
        panelBorder: Color(hex: 0xE4EBF7)
    )

    static let dark = HelpyPalette(
        canvas: Color(hex: 0x0A0E17),
        surface: Color(hex: 0x111826),
        surfaceHover: Color(hex: 0x151E2F),
        surfaceActive: Color(hex: 0x121A29),
        surfaceActiveBorder: Color(hex: 0x212C40),
        line: Color(hex: 0xFFFFFF, opacity: 0.11),

        ink: Color(hex: 0xE9EFFA),
        ink2: Color(hex: 0xDDE5F3),
        muted: Color(hex: 0x8A99B4),
        muted2: Color(hex: 0x5D6B87),

        accent: Color(hex: 0x4E9BFF),
        header: Color(hex: 0x0086E8),
        onAccent: Color.white,

        railTrack: Color(hex: 0x202A3D),
        rail: Color(hex: 0x0086E8),

        warm: Color(hex: 0xFFA84D),
        hot: Color(hex: 0xFF8A6B),
        success: Color(hex: 0x5FD3A0),

        chipFill: Color(hex: 0x1A2334),
        chipText: Color(hex: 0x7C8CA8),
        chipHotFill: Color(hex: 0x33211C),
        chipHotText: Color(hex: 0xF08A5F),

        checkBorder: Color(hex: 0x39465E),
        fieldFill: Color(hex: 0x101724),
        fieldBorder: Color(hex: 0x1E2839),
        placeholder: Color(hex: 0x68758F),
        controlIcon: Color(hex: 0x8A99B4),
        controlHoverFill: Color(hex: 0xFFFFFF, opacity: 0.09),
        dangerHoverFill: Color(hex: 0xFF6E50, opacity: 0.18),
        dangerHoverIcon: Color(hex: 0xFF8A6B),
        goHoverFill: Color(hex: 0x3CC88C, opacity: 0.16),
        goHoverIcon: Color(hex: 0x5FD3A0),

        pillFill: Color(hex: 0x141B29),
        pillBorder: Color(hex: 0xFFFFFF, opacity: 0.09),
        panelFill: Color(hex: 0x141B29),
        panelBorder: Color(hex: 0xFFFFFF, opacity: 0.08)
    )

    static func forScheme(_ scheme: ColorScheme) -> HelpyPalette {
        (scheme == .dark ? dark : light).tinted(HelpyAccent.current, isDark: scheme == .dark)
    }

    /// Swaps the brand tokens for the user's accent. Everything else — inks,
    /// surfaces, status colours — is left alone: those are legibility
    /// decisions, not brand ones, and rederiving them from an arbitrary hue is
    /// how themable apps end up with unreadable text.
    private func tinted(_ color: Color, isDark: Bool) -> HelpyPalette {
        var copy = self
        copy.accent = color
        copy.header = color
        copy.rail = color
        copy.surfaceActive = color.opacity(isDark ? 0.11 : 0.06)
        copy.surfaceActiveBorder = color.opacity(isDark ? 0.34 : 0.30)
        return copy
    }
}

/// The one colour the user gets to choose.
///
/// Read through a static rather than an environment key on purpose: every view
/// in Helpy already reaches its palette through `HelpyPalette.forScheme`, and
/// threading a new environment value through all of them would touch far more
/// code than this feature is worth. `SettingsStore` owns the stored value and
/// keeps this in step; the main window carries `.id(accentHex)` so a change
/// actually repaints rather than waiting for the next redraw.
enum HelpyAccent {
    /// Sky — the blue the rest of the palette was designed around.
    static let defaultHex: UInt32 = 0x0086E8
    static let key = "accentHex"

    struct Preset: Identifiable {
        let name: String
        let hex: UInt32
        var id: UInt32 { hex }
        var color: Color { Color(hex: hex) }
    }

    static let presets: [Preset] = [
        Preset(name: "Sky", hex: 0x0086E8),
        Preset(name: "Indigo", hex: 0x4F46E5),
        Preset(name: "Violet", hex: 0x8B5CF6),
        Preset(name: "Magenta", hex: 0xD6357F),
        Preset(name: "Coral", hex: 0xEE5B36),
        Preset(name: "Amber", hex: 0xD98A00),
        Preset(name: "Green", hex: 0x1E9E62),
        Preset(name: "Graphite", hex: 0x50607A)
    ]

    static var currentHex: UInt32 = defaultHex
    static var current: Color { Color(hex: currentHex) }

    /// Called before the first view is built, so nothing renders in the wrong
    /// colour for a frame.
    static func loadFromDefaults(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: key) != nil else { return }
        let stored = defaults.integer(forKey: key)
        guard (0...0xFFFFFF).contains(stored) else { return }
        currentHex = UInt32(stored)
    }
}

extension Color {
    /// 0xRRGGBB for a colour that came back out of a `ColorPicker`. Anything
    /// that will not convert to sRGB keeps the previous accent rather than
    /// resolving to black.
    var helpyHex: UInt32? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let channel = { (value: CGFloat) in UInt32(max(0, min(255, (value * 255).rounded()))) }
        return channel(srgb.redComponent) << 16
            | channel(srgb.greenComponent) << 8
            | channel(srgb.blueComponent)
    }
}

// MARK: - Shape metrics

enum HelpyMetrics {
    /// Version "B" header: full-bleed gradient that sweeps into rounded
    /// BOTTOM corners. Used by the sidebar header and the menu bar dropdown.
    static let headerCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 14
    static let rowCornerRadius: CGFloat = 12
    static let fieldCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 14
    static let pillCornerRadius: CGFloat = 22
    static let panelCornerRadius: CGFloat = 18
}

/// A rectangle with only its bottom corners rounded — the header shape.
struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The header block: one flat colour swept into rounded bottom corners.
///
/// Previously a three-stop sweep with a soft white radial glow in the top-right.
/// Both are gone by choice — flat reads as deliberate rather than decorative,
/// and it holds white text at a single known contrast instead of a range that
/// got weakest exactly where the pale end of the sweep sat.
struct HelpyHeaderBackground: View {
    let palette: HelpyPalette
    var cornerRadius: CGFloat = HelpyMetrics.headerCornerRadius

    var body: some View {
        palette.header
            .clipShape(BottomRoundedRectangle(radius: cornerRadius))
            .allowsHitTesting(false)
    }
}

// MARK: - Inter

/// Inter ships inside the app bundle; register it once before the first view
/// is built. Registration is idempotent — a duplicate registration is not an
/// error worth surfacing, the font is simply already available.
enum HelpyFonts {
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true

        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                AppLogger.ui.error("Missing bundled font \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// PostScript name for a weight. Explicit faces rather than a weight axis:
    /// a family-name lookup silently falls back to the system font when the
    /// requested weight isn't a registered member, which reads as "Inter didn't
    /// apply" with nothing in the logs.
    static func psName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }
}

extension Font {
    /// Drop-in replacement for `.system(size:weight:)` — same call shape so the
    /// two never get mixed up at a call site.
    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(HelpyFonts.psName(for: weight), fixedSize: size)
    }
}

extension NSFont {
    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        NSFont(name: HelpyFonts.psName(for: weight), size: size)
            ?? .systemFont(ofSize: size)
    }
}

// MARK: - Shared chrome

extension View {
    /// Opaque card surface used by rows, the active-task card and popovers.
    func helpyCard(
        _ palette: HelpyPalette,
        fill: Color? = nil,
        border: Color? = nil,
        cornerRadius: CGFloat = HelpyMetrics.rowCornerRadius
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill ?? palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border ?? palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Buttons

/// Filled accent button — the single "commit" action on a surface.
struct HelpyPrimaryButtonStyle: ButtonStyle {
    let palette: HelpyPalette
    var cornerRadius: CGFloat = 10

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(size: 12, weight: .semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.rail)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet outlined button for secondary actions next to a primary one.
struct HelpySecondaryButtonStyle: ButtonStyle {
    let palette: HelpyPalette
    var cornerRadius: CGFloat = 10

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(size: 12, weight: .medium))
            .foregroundStyle(palette.ink2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? palette.controlHoverFill : palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.fieldBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Text-only button, used where a full chrome button would be too loud.
struct HelpyQuietButtonStyle: ButtonStyle {
    let palette: HelpyPalette

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? palette.ink2 : palette.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Brand mark

/// Helpy's cat, drawn from the bundled white PNG. It renders as a template so
/// a caller can ink it; the default is the white mark, which is what sits on
/// the blue headers and in the menu bar.
struct HelpyMark: View {
    var size: CGFloat = 24
    var color: Color = .white

    private static let image: Image? = {
        guard let url = Bundle.module.url(forResource: "HelpyMark", withExtension: "png"),
              let rep = NSImage(contentsOf: url) else {
            AppLogger.ui.error("HelpyMark.png missing from the bundle")
            return nil
        }
        return Image(nsImage: rep)
    }()

    var body: some View {
        if let image = Self.image {
            image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}
