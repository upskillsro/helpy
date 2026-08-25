import SwiftUI

struct AssistantPanel: View {
    @ObservedObject var coordinator: AssistantCoordinator
    let onClose: () -> Void
    let availableHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var measuredPromptHeight: CGFloat = 44

    private let placeholderText = "Add tasks for today, reschedule something, or paste a transcript from Handy..."

    private var t: HelpyPalette { .forScheme(colorScheme) }
    private var helperTextColor: Color { t.muted }

    private var reviewActionCount: Int {
        groupedReviewActions.reduce(0) { $0 + $1.actions.count }
    }

    private var promptEditorHeight: CGFloat {
        min(max(measuredPromptHeight, 42), 120)
    }

    private var reviewListHeight: CGFloat {
        guard reviewActionCount > 0 else { return 0 }
        let estimated = CGFloat(reviewActionCount) * 58 + CGFloat(max(groupedReviewActions.count - 1, 0)) * 20
        let baseHeight = compactPanelHeight
        let maxReviewHeight = max((availableHeight * (2.0 / 3.0)) - baseHeight, 96)
        return min(max(estimated, 96), maxReviewHeight)
    }

    private var compactPanelHeight: CGFloat {
        max(availableHeight * 0.25, 180)
    }

    private var expandedPanelHeight: CGFloat {
        min(compactPanelHeight + reviewListHeight + 42, availableHeight * (2.0 / 3.0))
    }

    private var panelHeight: CGFloat {
        reviewActionCount > 0 ? expandedPanelHeight : compactPanelHeight
    }

    private var groupedReviewActions: [(kind: AssistantActionKind, actions: [AssistantActionDraft])] {
        guard case .review(let batch) = coordinator.state else { return [] }
        let orderedKinds = AssistantActionKind.allCases.filter { kind in
            batch.actions.contains(where: { $0.kind == kind })
        }
        return orderedKinds.map { kind in
            (kind, batch.actions.filter { $0.kind == kind })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            inputArea
            stateArea
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HelpyMetrics.panelCornerRadius, style: .continuous)
                .fill(t.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HelpyMetrics.panelCornerRadius, style: .continuous)
                .stroke(t.panelBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 20, x: 0, y: 8)
        .frame(height: panelHeight, alignment: .bottom)
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Assistant")
                    .font(.inter(size: 14, weight: .semibold))
                    .foregroundColor(t.ink)
                Spacer()
                if coordinator.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(t.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text("Describe what you want to add or change, then review the actions before applying.")
                .font(.inter(size: 11))
                .foregroundColor(helperTextColor)
        }
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(t.fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(t.fieldBorder, lineWidth: 1)
                    )

                AssistantPromptEditor(text: $coordinator.inputText, contentHeight: $measuredPromptHeight)
                    .frame(height: promptEditorHeight)
                    .disabled(coordinator.isBusy)

                if coordinator.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholderText)
                        .font(.inter(size: 13))
                        .foregroundColor(t.placeholder)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: promptEditorHeight)

            HStack {
                Text("Type directly here or paste a transcript from Handy.")
                    .font(.inter(size: 10))
                    .foregroundColor(helperTextColor)

                Spacer()

                Button("Generate") {
                    coordinator.submitTypedInput()
                }
                .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
                .disabled(coordinator.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isBusy)
            }

        }
    }

    @ViewBuilder
    private var stateArea: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .recording:
            Label("Voice input is currently disabled in Helpy.", systemImage: "mic.slash")
                .font(.inter(size: 11))
                .foregroundColor(helperTextColor)
        case .transcribing:
            Label("Voice input is currently disabled in Helpy.", systemImage: "mic.slash")
                .font(.inter(size: 11))
                .foregroundColor(helperTextColor)
        case .generating:
            Label("Generating reminder actions with Ollama…", systemImage: "sparkles")
                .font(.inter(size: 11))
                .foregroundColor(helperTextColor)
        case .error(let error):
            VStack(alignment: .leading, spacing: 8) {
                Text(error.localizedDescription)
                    .font(.inter(size: 11))
                    .foregroundColor(t.hot)
                HStack {
                    Button("Try Again") {
                        coordinator.retryLastInput()
                    }
                    .buttonStyle(HelpySecondaryButtonStyle(palette: t))
                    Button("Dismiss") {
                        coordinator.state = .idle
                    }
                    .buttonStyle(HelpyQuietButtonStyle(palette: t))
                }
            }
        case .review(let batch):
            VStack(alignment: .leading, spacing: 10) {
                Text("Review \(batch.actions.count) action\(batch.actions.count == 1 ? "" : "s")")
                    .font(.inter(size: 11, weight: .medium))
                    .foregroundColor(t.muted)

                if reviewListHeight > 0 {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(groupedReviewActions, id: \.kind) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(sectionTitle(for: section.kind, count: section.actions.count))
                                        .font(.inter(size: 11, weight: .semibold))
                                        .foregroundColor(helperTextColor)

                                    ForEach(section.actions) { action in
                                        AssistantDraftCard(
                                            action: action,
                                            onChange: { coordinator.updateAction($0) },
                                            onApply: { coordinator.applyAction($0) },
                                            onDiscard: { coordinator.discardAction(action) }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(height: reviewListHeight)
                }

                HStack {
                    Button("Discard All") {
                        coordinator.discardAllActions()
                    }
                    .buttonStyle(HelpyQuietButtonStyle(palette: t))

                    Button("Try Again") {
                        coordinator.retryLastInput()
                    }
                    .buttonStyle(HelpySecondaryButtonStyle(palette: t))

                    Spacer()

                    Button("Apply All") {
                        coordinator.applyAllActions()
                    }
                    .buttonStyle(HelpyPrimaryButtonStyle(palette: t))
                }
            }
        }
    }

    private func sectionTitle(for kind: AssistantActionKind, count: Int) -> String {
        let base: String
        switch kind {
        case .create: base = "Creates"
        case .update: base = "Updates"
        case .delete: base = "Deletes"
        case .complete: base = "Status Changes"
        case .reorder: base = "Reordering"
        }
        return "\(base) · \(count)"
    }
}
