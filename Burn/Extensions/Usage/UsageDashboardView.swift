import AppKit
import SwiftUI
import ClaudeUsageKit

enum DetailScope: Equatable {
    case day(String)
    case week
    case month
}

struct UsageDashboardView: View {
    let service: UsageService
    let settings: SettingsStore

    @Environment(\.openBurnSettings) private var openSettings

    @State private var weekOffset = 0
    @State private var selectedDayId: String?
    @State private var openScope: DetailScope? = UsageDashboardView.initialOpenScope()
    @State private var hasAppearedOnce = false

    private static func initialOpenScope() -> DetailScope? {
        switch ProcessInfo.processInfo.environment["BURN_DETAIL"] {
        case "day":   return .day("")
        case "week":  return .week
        case "month": return .month
        default:      return nil
        }
    }

    private var displayData: UsageData {
        weekOffset == 0 ? service.usageData : service.usageData(weekOffset: weekOffset)
    }

    private var tokens: TokenAggregates {
        TokenAggregates.compute(response: service.lastResponse, weekEnd: displayData.weekEnd)
    }

    private var selectedDay: DailyUsage? {
        let days = displayData.last7Days
        if let id = selectedDayId, let day = days.first(where: { $0.id == id }) {
            return day
        }
        return days.last
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let scope = openScope {
                BreakdownDetailView(
                    data: breakdownData(for: scope),
                    onBack: { toggleDetail(scope) },
                    onSettings: openSettings
                )
                .transition(slideTransition(.trailing))
            } else {
                mainContent
                    .transition(slideTransition(.leading))
            }
        }
        .clipped()
        .onAppear {
            if hasAppearedOnce {
                resetToDefault()
            } else {
                hasAppearedOnce = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard hasAppearedOnce, let window = note.object as? NSWindow else { return }
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") || className.contains("Popover") || className.contains("StatusBar") {
                resetToDefault()
            }
        }
    }

    private func slideTransition(_ edge: Edge) -> AnyTransition {
        .asymmetric(insertion: .move(edge: edge), removal: .move(edge: edge))
    }

    private func resetToDefault() {
        openScope = nil
        weekOffset = 0
        selectedDayId = nil
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            errorBanner
            heroSection
            Divider()
            chartSection
            Divider()
            monthSection
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(nsImage: MenuBarLabel.loadMenuBarIcon())
                .resizable()
                .frame(width: 20, height: 20)
            Text("Burn").font(.headline)
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var heroSection: some View {
        VStack(spacing: 4) {
            heroPrimary
            heroSecondary
            Text(heroDateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var heroPrimary: some View {
        let day = selectedDay
        let cost = day?.totalCost ?? 0
        let totalIO = (day?.inputTokens ?? 0) + (day?.outputTokens ?? 0)
        let text: String = {
            switch settings.displayMode {
            case .cost, .both: return Formatters.cost(cost)
            case .tokens:      return Formatters.tokensCompact(totalIO)
            }
        }()
        Text(text)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var heroSecondary: some View {
        if let day = selectedDay {
            Button { toggleDetail(.day(day.id)) } label: {
                HStack(spacing: 6) {
                    if settings.displayMode != .cost {
                        let cache = day.cacheCreationTokens + day.cacheReadTokens
                        Text(Formatters.tokenLine(input: day.inputTokens, output: day.outputTokens, cache: cache))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Show breakdown")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }

    private var heroDateLabel: String {
        guard let day = selectedDay else { return "Today" }
        return Formatters.dayLabel(day.date)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = service.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chartSection: some View {
        let data = displayData
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                weekNavButton(
                    direction: .previous,
                    enabled: data.canGoBack,
                    icon: "chevron.left",
                    shortcut: .leftArrow
                )

                if data.isCurrentWeek {
                    Spacer()
                } else {
                    Button {
                        weekOffset = 0
                        selectedDayId = nil
                        withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
                    } label: {
                        Text("This Week")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut("0", modifiers: .command)
                    .pointingHandCursor()
                }

                weekNavButton(
                    direction: .next,
                    enabled: weekOffset < 0,
                    icon: "chevron.right",
                    shortcut: .rightArrow
                )
            }
            .padding(.horizontal, 14)

            if data.last7Days.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                BarChartView(days: data.last7Days, selectedDayId: $selectedDayId)
                    .frame(height: 80)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private enum WeekNavDirection { case previous, next }

    private func weekNavButton(
        direction: WeekNavDirection,
        enabled: Bool,
        icon: String,
        shortcut: KeyEquivalent
    ) -> some View {
        Button {
            weekOffset += (direction == .previous ? -1 : 1)
            selectedDayId = nil
            withAnimation(.easeInOut(duration: 0.15)) { openScope = nil }
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? .secondary : .quaternary)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(shortcut, modifiers: .command)
        .pointingHandCursor()
    }

    private var monthSection: some View {
        let data = displayData
        return HStack(spacing: 0) {
            monthSectionColumn(
                label: data.isCurrentWeek ? "This Week" : Formatters.weekRange(data),
                primary: Formatters.formatPrimary(
                    cost: data.weekTotal,
                    tokens: tokens.weekInput + tokens.weekOutput,
                    mode: settings.displayMode
                ),
                tokenSplit: settings.displayMode == .both
                    ? Formatters.tokenSplit(input: tokens.weekInput, output: tokens.weekOutput)
                    : nil,
                alignment: .leading,
                onTap: { toggleDetail(.week) }
            )

            monthSectionColumn(
                label: data.isCurrentWeek ? "This Month" : Formatters.monthName(data),
                primary: Formatters.formatPrimary(
                    cost: data.monthTotal,
                    tokens: tokens.monthInput + tokens.monthOutput,
                    mode: settings.displayMode
                ),
                tokenSplit: settings.displayMode == .both
                    ? Formatters.tokenSplit(input: tokens.monthInput, output: tokens.monthOutput)
                    : nil,
                alignment: .trailing,
                onTap: { toggleDetail(.month) }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func monthSectionColumn(
        label: String,
        primary: String,
        tokenSplit: String?,
        alignment: HorizontalAlignment,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: alignment, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(primary)
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(.primary)
                if let tokenSplit {
                    Text(tokenSplit).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: alignment == .leading ? .leading : .trailing
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - Detail wiring

    private func toggleDetail(_ scope: DetailScope) {
        withAnimation(.easeInOut(duration: 0.25)) {
            openScope = (openScope == scope) ? nil : scope
        }
    }

    private func breakdownData(for scope: DetailScope) -> BreakdownData {
        switch scope {
        case .day(let id):
            let day = displayData.last7Days.first(where: { $0.id == id })
                ?? selectedDay
                ?? displayData.last7Days.last
            guard let day else { return BreakdownData.empty(title: "Day", subtitle: "No data") }
            return BreakdownData.compute(
                title: Formatters.dayLabel(day.date),
                subtitle: Formatters.dayLabel(day.date),
                days: [day]
            )
        case .week:
            let title = displayData.isCurrentWeek ? "This Week" : "Week"
            return BreakdownData.compute(
                title: title,
                subtitle: Formatters.weekRange(displayData),
                days: displayData.last7Days
            )
        case .month:
            let monthPrefix = String(UsageData.dateString(from: displayData.weekEnd).prefix(7))
            let days = (service.lastResponse?.daily ?? []).filter { $0.date.hasPrefix(monthPrefix) }
            let title = displayData.isCurrentWeek ? "This Month" : Formatters.monthName(displayData)
            return BreakdownData.compute(
                title: title,
                subtitle: Formatters.monthName(displayData),
                days: days
            )
        }
    }
}
