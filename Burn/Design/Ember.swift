import SwiftUI

/// Ember: warm surface, amber accent. Amber means money, the text ramp means labels.
/// Every token resolves per appearance, so no component ever picks a light or dark value itself.
enum Ember {
    static let width: CGFloat = 344

    private static let ink = EmberToken.hex(0x1A1710)

    static let surface = EmberToken.dynamic(dark: .hex(0x16150F), light: .hex(0xFBFAF8))
    static let utility = EmberToken.dynamic(
        dark: EmberToken.hex(0x000000, alpha: 0.25),
        light: EmberToken.hex(0xD97706, alpha: 0.04)
    )

    /// Light shifts amber down to #D97706 to hold contrast on a cream surface; a straight
    /// invert would fail on the hero number and every bar fill.
    static let accent = EmberToken.dynamic(dark: .hex(0xFFB340), light: .hex(0xD97706))
    static let accentDeep = EmberToken.dynamic(dark: .hex(0xFF7A3D), light: .hex(0xB45309))
    static let hairline = EmberToken.dynamic(
        dark: EmberToken.hex(0xFFB340, alpha: 0.14),
        light: EmberToken.hex(0xD97706, alpha: 0.14)
    )

    /// The whole text ramp, one call. White on dark, near-black on light, same opacities.
    static func text(_ opacity: Double) -> Color { textRamp[step(opacity)] ?? textColor(opacity) }

    /// Backgrounds and empty track fills, which read as a wash rather than as text.
    static func fill(_ opacity: Double) -> Color { fillRamp[step(opacity)] ?? fillColor(opacity) }

    /// Built once. A fresh dynamic NSColor per call would make two identical greys unequal, which
    /// costs SwiftUI its diffing and makes the colours untestable.
    private static let textRamp = ramp(textColor)
    private static let fillRamp = ramp(fillColor)

    private static func ramp(_ make: (Double) -> Color) -> [Int: Color] {
        Dictionary(uniqueKeysWithValues: (0...100).map { ($0, make(Double($0) / 100)) })
    }

    private static func step(_ opacity: Double) -> Int {
        Int((min(max(opacity, 0), 1) * 100).rounded())
    }

    private static func textColor(_ opacity: Double) -> Color {
        EmberToken.dynamic(
            dark: EmberToken.hex(0xFFFFFF, alpha: opacity),
            light: EmberToken.hex(0x1A1710, alpha: min(1, opacity * 1.12))
        )
    }

    private static func fillColor(_ opacity: Double) -> Color {
        EmberToken.dynamic(
            dark: EmberToken.hex(0xFFFFFF, alpha: opacity),
            light: EmberToken.hex(0x1A1710, alpha: opacity * 0.9)
        )
    }

    /// Inset wells, mostly text fields. Black carves into a dark surface; on cream it has to be
    /// the ink at low alpha, since black at the same strength reads as a hole.
    static func recess(_ opacity: Double) -> Color {
        EmberToken.dynamic(
            dark: EmberToken.hex(0x000000, alpha: opacity),
            light: EmberToken.hex(0x1A1710, alpha: opacity * 0.12)
        )
    }

    /// Connection health, which is a yes/no rather than a quantity, so it sits outside the ramp.
    /// Darkened on light: #32D74B lands near 1.8:1 on cream, well under the 3:1 a dot needs.
    static let healthy = EmberToken.dynamic(dark: .hex(0x32D74B), light: .hex(0x1E9E36))

    /// The one place amber gives way: destructive actions and error states.
    static let danger = EmberToken.dynamic(dark: .hex(0xFF6961), light: .hex(0xD62E27))
    static let dangerBright = EmberToken.dynamic(dark: .hex(0xFF8A83), light: .hex(0xB3261E))

    /// Text sitting on an amber fill. Near-black beats white against both accents.
    static let onAccent = Color(nsColor: ink)

    /// Text on a red fill, which flips: the red lightens on dark and darkens on light.
    static let onDanger = EmberToken.dynamic(dark: .hex(0x1A1710), light: .hex(0xFFFFFF))

    static var label: Color { text(0.45) }
    static var caption: Color { text(0.5) }
    static var strong: Color { text(0.72) }

    /// Full-strength body text. Named because `.white` is only correct in one appearance.
    static var primary: Color { text(1) }

    static let heroSize: CGFloat = 46
    static let heroCentsSize: CGFloat = 26
}

extension NSColor {
    static func hex(_ value: UInt32) -> NSColor { EmberToken.hex(value) }
}

// MARK: - Chrome

/// Tab glyphs come from a bundled asset, an SF Symbol, or fall back to the extension name.
enum TabGlyph {
    case asset
    case symbol(String)
    case text(String)
}

struct EmberTabStrip: View {
    let extensions: [any BurnExtension]
    let activeId: String?
    let onSelect: (String) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 1) {
            ForEach(extensions, id: \.id) { ext in
                let isActive = ext.id == activeId
                Button { withAnimation(EmberMotion.pill) { onSelect(ext.id) } } label: {
                    glyph(ext.tabGlyph, isActive: isActive)
                        .frame(width: 24, height: 20)
                        .background {
                            // The pill slides between tabs rather than fading out and in somewhere else.
                            if isActive {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Ember.accent.opacity(0.24))
                                    .matchedGeometryEffect(id: "tab", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(ext.displayName)
                .pointingHandCursor()
            }
        }
        .padding(2)
        .background(Ember.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func glyph(_ glyph: TabGlyph, isActive: Bool) -> some View {
        switch glyph {
        case .asset:
            // The glyph is a template, so it has to be told to tint; left alone it draws flat black.
            Image(nsImage: MenuBarLabel.loadMenuBarIcon())
                .resizable()
                .renderingMode(.template)
                .frame(width: 12, height: 12)
                .foregroundStyle(isActive ? Ember.primary : Ember.label)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Ember.primary : Ember.label)
        case .text(let title):
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? Ember.primary : Ember.label)
        }
    }
}

/// Header line: a pulse dot, one sentence of state, then the tab strip.
struct EmberStatusHeader: View {
    let status: String?
    let state: ExtensionState
    let extensions: [any BurnExtension]
    let activeId: String?
    let onSelect: (String) -> Void

    /// Breathing while live. A static dot is how a closed day says so without a label.
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            if status != nil || state == .loading || state.failureMessage != nil {
                Circle()
                    .fill(state.dotColor)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(state.dotColor.opacity(0.18), lineWidth: 3))
                    .scaleEffect(isPulsing ? 1.08 : 1)
                    .opacity(isPulsing ? 1 : 0.7)
                    .animation(state == .live ? EmberMotion.pulse : .default, value: isPulsing)
                    .onAppear { isPulsing = state == .live }
                    .onChange(of: state) { _, new in isPulsing = new == .live }
            }
            Text(status ?? "")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Ember.strong)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(EmberMotion.number, value: status)
                .lineLimit(1)
            Spacer(minLength: 8)
            if extensions.count > 1 {
                EmberTabStrip(extensions: extensions, activeId: activeId, onSelect: onSelect)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
}

struct EmberUtilityBar: View {
    let updated: String
    let isLoading: Bool
    /// Changes only when the numbers do, which is what decides a full spin from a shrug.
    let signature: String
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @State private var rotation: Double = 0
    @State private var awaiting: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(updated)
                .font(.system(size: 10.5))
                .foregroundStyle(Ember.label)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(EmberMotion.number, value: updated)
            Spacer(minLength: 6)
            refresh
            action("gearshape", help: "Settings", perform: onSettings)
            action("heart", help: "Support") {
                NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/maferland")!)
            }
            action("power", help: "Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(Ember.utility)
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }

    /// A full turn only when the pull actually moved the numbers; otherwise a 15° shrug, so
    /// repeated manual refreshes on a quiet day don't pretend something happened.
    private var refresh: some View {
        Button {
            awaiting = signature
            onRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.text(0.55))
                .rotationEffect(.degrees(rotation))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmberIconButtonStyle())
        .help("Refresh")
        .pointingHandCursor()
        .onChange(of: isLoading) { _, loading in
            guard !loading, let previous = awaiting else { return }
            awaiting = nil
            withAnimation(EmberMotion.spin) {
                rotation += EmberMotion.refreshRotation(before: previous, after: signature)
            }
        }
    }

    private func action(_ symbol: String, help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.text(0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmberIconButtonStyle())
        .help(help)
        .pointingHandCursor()
    }
}

// MARK: - Content primitives

struct EmberHero: View {
    let primary: String
    let secondary: String?
    let caption: AnyView

    init(primary: String, secondary: String? = nil, @ViewBuilder caption: () -> some View) {
        self.primary = primary
        self.secondary = secondary
        self.caption = AnyView(caption())
    }

    /// Money hero: dollars at full size, cents dimmed.
    init(cost: Double, prefix: String = "", @ViewBuilder caption: () -> some View) {
        let parts = Formatters.costParts(cost)
        self.init(primary: prefix + parts.whole, secondary: parts.cents, caption: caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(primary)
                    .font(.system(size: Ember.heroSize, weight: .bold, design: .default))
                if let secondary {
                    Text(secondary)
                        .font(.system(size: Ember.heroCentsSize, weight: .bold))
                        .foregroundStyle(Ember.accent.opacity(0.45))
                }
            }
            .foregroundStyle(Ember.accent)
            .monospacedDigit()
            // Digits roll upward on refresh: the number is ticking up, not being replaced.
            .contentTransition(.numericText())
            .animation(EmberMotion.number, value: primary)
            .animation(EmberMotion.number, value: secondary)
            .kerning(-1.2)
            caption
                .font(.system(size: 12))
                .foregroundStyle(Ember.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

/// Progress track with an optional reference tick, used for pace and for quota windows.
struct EmberTrack: View {
    let fill: Double
    let tick: Double?
    let leading: String
    let trailing: String

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let clamped = min(max(fill, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Ember.fill(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Ember.accent, Ember.accentDeep],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(3, geo.size.width * clamped))
                    if let tick {
                        Rectangle()
                            .fill(Ember.fill(0.35))
                            .frame(width: 1, height: 12)
                            .offset(x: min(geo.size.width - 1, geo.size.width * min(max(tick, 0), 1)))
                    }
                }
                // The tick slides across the hour rather than jumping to the next position.
                .animation(EmberMotion.track, value: clamped)
                .animation(EmberMotion.track, value: tick)
            }
            .frame(height: 6)

            HStack {
                Text(leading).foregroundStyle(Ember.label)
                Spacer()
                Text(trailing).foregroundStyle(Ember.text(0.62))
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
    }
}

struct EmberSection<Content: View>: View {
    let title: String?
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(Ember.label)
                    }
                    Spacer(minLength: 4)
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Ember.label)
                            .monospacedDigit()
                    }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }
}

/// One labelled bar: model name, share of the leader, amount.
struct EmberBarRow: View {
    let label: String
    let fraction: Double
    let value: String
    let emphasis: Double
    /// Defaults to amber; the Limits tab passes each provider's own accent.
    var color: Color = Ember.accent
    /// Position in its group, which is all the stagger needs to know.
    var row: Int = 0

    /// Reveals once per appearance, so opening the popover animates but a background refresh doesn't.
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ember.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ember.fill(0.07))
                    Capsule()
                        .fill(color.opacity(emphasis))
                        .frame(width: revealed ? max(2, geo.size.width * min(max(fraction, 0), 1)) : 0)
                        .animation(EmberMotion.track, value: fraction)
                }
            }
            .frame(height: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ember.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(EmberMotion.number, value: value)
                .frame(width: 56, alignment: .trailing)
        }
        .onAppear {
            withAnimation(EmberMotion.track.delay(EmberMotion.revealDelay(row: row))) {
                revealed = true
            }
        }
    }
}

/// Seven-day strip demoted to context, with the period totals under it.
struct EmberContextStrip: View {
    let bars: [Bar]
    let selectedId: String?
    let leading: LabeledTotal
    let trailing: LabeledTotal
    let onSelect: (String) -> Void
    let onOpen: (Scope) -> Void
    var nav: Nav?

    /// Week paging lives inline with the totals so it doesn't cost a row of its own.
    struct Nav {
        let canGoBack: Bool
        let canGoForward: Bool
        let onBack: () -> Void
        let onForward: () -> Void
    }

    enum Scope { case week, month }

    struct Bar: Identifiable {
        let id: String
        let fraction: Double
    }

    struct LabeledTotal {
        let label: String
        let value: String
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars) { bar in
                    let isSelected = bar.id == selectedId
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Ember.accent : Ember.accent.opacity(0.22))
                        .frame(height: max(2, 34 * min(max(bar.fraction, 0), 1)))
                        .frame(maxWidth: .infinity, maxHeight: 34, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(bar.id) }
                        .pointingHandCursor()
                }
            }
            .frame(height: 34)

            HStack(alignment: .center, spacing: 6) {
                if let nav {
                    chevron("chevron.left", enabled: nav.canGoBack, action: nav.onBack)
                }
                total(leading) { onOpen(.week) }
                Spacer(minLength: 6)
                total(trailing) { onOpen(.month) }
                if let nav {
                    chevron("chevron.right", enabled: nav.canGoForward, action: nav.onForward)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .top) { Rectangle().fill(Ember.hairline).frame(height: 1) }
    }

    private func chevron(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? Ember.text(0.45) : Ember.text(0.14))
                .frame(width: 14, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .pointingHandCursor()
    }

    /// Dimmer than `Ember.primary` — the strip lost its chevrons, so the totals should read as
    /// inert numbers you can still tap open, not as a live nav control.
    private func total(_ item: LabeledTotal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(item.label).foregroundStyle(Ember.caption)
                Text(item.value).foregroundStyle(Ember.text(0.85)).fontWeight(.semibold)
            }
            .font(.system(size: 11.5))
            .monospacedDigit()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

struct EmberNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Ember.label)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmberEmptyState: View {
    let title: String
    let detail: String
    var action: (label: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Ember.primary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ember.accent)
                    .pointingHandCursor()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 34)
    }
}
