import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// One column of a list board.
///
/// Cards are `ReminderRowView` — the same component the side strip uses — so the
/// two can never drift into looking like different apps.
struct BoardColumnView: View {
    let bucket: TaskBucket
    let reminders: [EKReminder]
    let isDraggingAppWide: Bool
    let draggedId: String?
    let onDrop: (String) -> Void
    let onAdd: (String) -> Void
    /// Only Today carries it.
    let onFocus: (() -> Void)?

    @EnvironmentObject var estimateStore: EstimateStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isTargeted = false
    @State private var newTaskTitle = ""
    @FocusState private var isAddFieldFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var isToday: Bool { bucket == .today }

    private var estimateSummary: String? {
        let seconds = reminders.reduce(0.0) { total, reminder in
            total + (estimateStore.getMetadata(for: reminder.calendarItemIdentifier)?.estimatedDuration ?? 0)
        }
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                        ReminderRowView(
                            reminder: reminder,
                            isDraggingAppWide: isDraggingAppWide,
                            isBeingDragged: draggedId == reminder.calendarItemIdentifier
                        )
                        .onDrag {
                            NSItemProvider(object: reminder.calendarItemIdentifier as NSString)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 2)
            }
            .scrollBounceBehavior(.basedOnSize)

            addRow

            if let onFocus {
                Button(action: onFocus) {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Focus Today")
                            .font(.inter(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(t.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: HelpyMetrics.rowCornerRadius, style: .continuous)
                            .fill(t.rail)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
                .disabled(reminders.isEmpty)
                .opacity(reminders.isEmpty ? 0.45 : 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .fill(isToday ? t.surfaceActive : t.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.cardCornerRadius, style: .continuous)
                .stroke(
                    isTargeted ? t.rail : (isToday ? t.surfaceActiveBorder : t.line),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            accept(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(bucket.title.uppercased())
                .font(.inter(size: 9, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(t.muted2)
            Spacer()
            Text(countLabel)
                .font(.inter(size: 9))
                .foregroundStyle(t.muted2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private var countLabel: String {
        guard let estimateSummary else { return "\(reminders.count)" }
        return "\(reminders.count) · \(estimateSummary)"
    }

    private var addRow: some View {
        TextField("＋ Add task…", text: $newTaskTitle)
            .textFieldStyle(.plain)
            .font(.inter(size: 10.5))
            .foregroundStyle(t.ink)
            .focused($isAddFieldFocused)
            .onSubmit {
                let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                newTaskTitle = ""
                guard !title.isEmpty else { return }
                onAdd(title)
                isAddFieldFocused = true
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }

    private func accept(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? String else { return }
            Task { @MainActor in onDrop(identifier) }
        }
        return true
    }
}
