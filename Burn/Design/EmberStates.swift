import SwiftUI

/// What a tab is currently able to say. Drives the header dot, and nothing else reads it.
enum ExtensionState: Equatable {
    case loading
    case live
    case dormant
    case failed(String)

    /// Amber means live money, grey means a closed day, red means the read broke.
    var dotColor: Color {
        switch self {
        case .live:               return Ember.accent
        case .loading, .dormant:  return Ember.text(0.15)
        case .failed:             return Ember.danger
        }
    }

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

/// Placeholder block. No shimmer: at a sub-second refresh it would only flicker.
struct EmberSkeleton: View {
    var width: CGFloat?
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(Ember.text(0.06))
            .frame(width: width, height: height)
    }
}

/// The loaded layout with the numbers taken out, so nothing shifts when data lands.
struct EmberLoadingBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmberSkeleton(width: 128, height: 36)
                .padding(.top, 16)
            EmberSkeleton(width: 172, height: 10)
                .padding(.top, 11)
            EmberSkeleton(height: 6)
                .padding(.top, 22)
            HStack {
                EmberSkeleton(width: 58, height: 9)
                Spacer(minLength: 8)
                EmberSkeleton(width: 86, height: 9)
            }
            .padding(.top, 8)
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 10) {
                        EmberSkeleton(width: 62, height: 8)
                        EmberSkeleton(height: 6)
                        EmberSkeleton(width: 38, height: 8)
                    }
                }
            }
            .padding(.top, 26)
            EmberSkeleton(height: 34)
                .padding(.top, 26)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }
}

/// The one card allowed to break the amber accent. Retry stays put instead of covering the message.
struct EmberErrorCard: View {
    let title: String
    let message: String
    let isRetrying: Bool
    let onSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Ember.danger)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Ember.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                action("Open settings", perform: onSettings)
                retry
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Ember.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Ember.danger.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var retry: some View {
        Button(action: onRetry) {
            Group {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                } else {
                    Text("Retry")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ember.onAccent)
                }
            }
            .frame(width: 52, height: 20)
            .background(Ember.dangerBright, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
        .pointingHandCursor()
    }

    private func action(_ label: String, perform: @escaping () -> Void) -> some View {
        Button(label, action: perform)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Ember.text(0.62))
            .pointingHandCursor()
    }
}

/// Stands in for the hero when there is nothing to count, carrying the last real number instead of a zero.
struct EmberEmptyHero: View {
    let title: String
    var footnote: String?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "flame")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(Ember.accent.opacity(0.35))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ember.text(0.82))
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(Ember.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

/// Day paging, shown once a closed day is on screen — the slot the live-rate dot will own for today.
struct EmberDayNav: View {
    let label: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            chevron("chevron.left", enabled: canGoBack, action: onBack)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ember.text(0.7))
                .monospacedDigit()
            chevron("chevron.right", enabled: canGoForward, action: onForward)
            Spacer(minLength: 8)
            Button("Today", action: onToday)
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Ember.accent)
                .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
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
}
