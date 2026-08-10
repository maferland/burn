import SwiftUI

/// One place for the timings, so a popover this small never has two speeds for the same gesture.
enum EmberMotion {
    static let pill = Animation.easeInOut(duration: 0.18)
    static let crossfade = Animation.easeInOut(duration: 0.12)
    static let hover = Animation.easeOut(duration: 0.1)
    static let number = Animation.snappy(duration: 0.2)
    static let track = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let spin = Animation.easeInOut(duration: 0.5)

    /// Bars reveal left to right rather than all at once, which reads as a list being counted.
    static let rowStagger: Double = 0.04

    static let pulse = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)

    static let hoverWash = Color(red: 1.0, green: 0.702, blue: 0.251).opacity(0.05)
    static let iconHoverWash = Ember.fill(0.06)

    /// A full turn says "that changed something", a 15° nudge says "asked, nothing new".
    static func refreshRotation(before: String, after: String) -> Double {
        before == after ? 15 : 360
    }

    static func revealDelay(row: Int) -> Double {
        Double(max(row, 0)) * rowStagger
    }
}

/// Rows light up and nothing else: no scale, no shadow, no height change that could shift the list.
struct EmberHoverRow: ViewModifier {
    var wash: Color = EmberMotion.hoverWash
    var cornerRadius: CGFloat = 8

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovering ? wash : .clear,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .onHover { hovering in
                withAnimation(EmberMotion.hover) { isHovering = hovering }
            }
    }
}

extension View {
    func emberHoverRow(wash: Color = EmberMotion.hoverWash, cornerRadius: CGFloat = 8) -> some View {
        modifier(EmberHoverRow(wash: wash, cornerRadius: cornerRadius))
    }
}

/// Standard macOS toolbar feel for the footer icons: a wash on hover, a small press, spring back.
struct EmberIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    /// A nested View, because `@State` on the style itself has no identity to hang onto.
    private struct HoverBody: View {
        let configuration: Configuration

        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    isHovering ? EmberMotion.iconHoverWash : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { hovering in
                    withAnimation(EmberMotion.hover) { isHovering = hovering }
                }
        }
    }
}

extension AnyTransition {
    /// The one moment an empty tab graduates to live, so it gets a beat instead of popping.
    static var emberRise: AnyTransition {
        .modifier(active: EmberRise(offset: 8, opacity: 0), identity: EmberRise(offset: 0, opacity: 1))
    }
}

struct EmberRise: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(y: offset).opacity(opacity)
    }
}
