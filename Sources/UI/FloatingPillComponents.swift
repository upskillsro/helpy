import SwiftUI

// Optimization: Equatable wrapper to stop redraws from TimerService updates
struct PillTitleView: View, Equatable {
    let title: String

    var body: some View {
        Text(title)
            .font(.body)
            .fontWeight(.medium)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    static func == (lhs: PillTitleView, rhs: PillTitleView) -> Bool {
        lhs.title == rhs.title
    }
}

struct ControlButton: View {
    let color: Color
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear.frame(width: 24, height: 24)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black.opacity(0.6))
                    )
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct IconButton: View {
    let icon: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear.frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct PillTimerDisplay: View {
    @ObservedObject var ticker: TimeTicker
    @ObservedObject var service: TimerService
    @AppStorage("appTheme") private var appTheme: AppTheme = .glass

    var body: some View {
        Text(service.formattedTime())
            .font(.title2).fontWeight(.bold).monospacedDigit()
            .foregroundColor(timerColor)
            .contentTransition(.numericText(countsDown: !service.isStopwatch && !service.isOvertime))
            .animation(.snappy, value: service.formattedTime())
            .fixedSize()
    }

    private var timerColor: Color {
        if service.isOvertime { return .orange }
        if appTheme == .white { return Color.black.opacity(0.9) }
        if appTheme == .dark { return .white }
        return .primary
    }
}
