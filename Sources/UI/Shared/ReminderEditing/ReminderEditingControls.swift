import SwiftUI

struct ReminderDateEditorField: View {
    let title: String
    @Binding var date: Date?

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.inter(size: 11, weight: .medium))
                .foregroundColor(t.muted)
                .frame(width: 44, alignment: .leading)

            if date != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date ?? Calendar.current.startOfDay(for: Date()) },
                        set: { date = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(minWidth: 120)
                .fixedSize()

                Spacer(minLength: 0)

                Button("Clear") { date = nil }
                    .buttonStyle(.plain)
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(t.muted)
            } else {
                Button {
                    date = Calendar.current.startOfDay(for: Date())
                } label: {
                    Text("No date")
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundColor(t.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .helpyCard(t, fill: t.fieldFill, border: t.fieldBorder, cornerRadius: 9)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
    }
}

struct ReminderTimeEditorField: View {
    let title: String
    let associatedDate: Date?
    @Binding var time: DateComponents?

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var isEnabled: Bool { associatedDate != nil }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.inter(size: 11, weight: .medium))
                .foregroundColor(t.muted)
                .frame(width: 44, alignment: .leading)

            if isEnabled, time != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { displayDate },
                        set: { newValue in
                            time = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(minWidth: 90)
                .fixedSize()

                Spacer(minLength: 0)

                Button("Clear") { time = nil }
                    .buttonStyle(.plain)
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(t.muted)
            } else {
                Button {
                    guard isEnabled else { return }
                    time = Calendar.current.dateComponents([.hour, .minute], from: Date())
                } label: {
                    Text(isEnabled ? "No time" : "Date first")
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundColor(t.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .helpyCard(t, fill: t.fieldFill, border: t.fieldBorder, cornerRadius: 9)
                        .opacity(isEnabled ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)

                Spacer(minLength: 0)
            }
        }
    }

    private var displayDate: Date {
        let baseDate = associatedDate ?? Calendar.current.startOfDay(for: Date())
        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = time?.hour ?? Calendar.current.component(.hour, from: Date())
        components.minute = time?.minute ?? Calendar.current.component(.minute, from: Date())
        return Calendar.current.date(from: components) ?? Date()
    }
}

struct ReminderPriorityChips: View {
    @Binding var selectedPriority: Int

    @Environment(\.colorScheme) private var colorScheme
    private var t: HelpyPalette { .forScheme(colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            priorityChip(title: "None", priority: 0, foreground: t.chipText, background: t.chipFill)
            priorityChip(title: "Low", priority: 9, foreground: t.accent, background: t.accent.opacity(0.14))
            priorityChip(title: "Medium", priority: 5, foreground: t.warm, background: t.warm.opacity(0.16))
            priorityChip(title: "High", priority: 1, foreground: t.hot, background: t.chipHotFill)
        }
    }

    private func priorityChip(title: String, priority: Int, foreground: Color, background: Color) -> some View {
        let isSelected = selectedPriority == priority
        return Button {
            selectedPriority = priority
        } label: {
            Text(title)
                .font(.inter(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundColor(foreground.opacity(isSelected ? 1 : 0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(background.opacity(isSelected ? 1 : 0.55)))
                .overlay(
                    Capsule().stroke(isSelected ? foreground.opacity(0.75) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
