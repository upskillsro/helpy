import AppKit
import EventKit
import SwiftUI

/// The "Create a new list" modal.
///
/// A sheet rather than the old inline rename-in-place cell: a list carries an
/// icon and a colour as well as a name, and three decisions do not fit in a
/// grid square. The icon is optional and applied after the list exists, since
/// icons are keyed by the calendar identifier the save hands back.
struct NewListSheet: View {
    let onCreate: (String, NSColor, NSImage?) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var color: ListColorOption = ListColorOption.options[0]
    @State private var icon: NSImage?
    @FocusState private var isTitleFocused: Bool

    private var t: HelpyPalette { .forScheme(colorScheme) }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            iconPicker
            colorPicker
            titleField
            actions
        }
        .frame(width: 420)
        .background(t.canvas)
        .onAppear { isTitleFocused = true }
    }

    // MARK: - Sections

    private var header: some View {
        ZStack {
            Text("Create a new list")
                .font(.inter(size: 16, weight: .bold))
                .foregroundStyle(t.ink)

            HStack {
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(t.muted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(t.fieldFill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var iconPicker: some View {
        VStack(spacing: 7) {
            Button(action: chooseIcon) {
                ZStack {
                    Circle().fill(color.color)

                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.14), value: color.id)

            Text(icon == nil ? "Upload an icon" : "Change icon")
                .font(.inter(size: 12, weight: .semibold))
                .foregroundStyle(t.ink)

            // Both states are given the same height: swapping a caption for a
            // button must not shuffle everything below it up and down.
            Group {
                if icon != nil {
                    Button("Remove") { icon = nil }
                        .buttonStyle(HelpyQuietButtonStyle(palette: t))
                } else {
                    Text("Optional (jpg, png, svg)")
                        .font(.inter(size: 11))
                        .foregroundStyle(t.muted2)
                }
            }
            .frame(height: 20)
        }
        .padding(.bottom, 20)
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a list color")
                .font(.inter(size: 12, weight: .semibold))
                .foregroundStyle(t.ink2)

            // A grid rather than one HStack: ten swatches plus their selection
            // rings come out wider than any comfortable sheet, and a row that
            // overflows drags the whole panel past its own edges.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 32, maximum: 40), spacing: 6)],
                spacing: 8
            ) {
                ForEach(ListColorOption.options) { option in
                    swatch(option)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func swatch(_ option: ListColorOption) -> some View {
        Button { color = option } label: {
            ZStack {
                Circle().fill(option.color)
                if option.id == color.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(option.needsDarkGlyph ? .black.opacity(0.7) : .white)
                }
            }
            .frame(width: 24, height: 24)
            .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
            .padding(3)
            .overlay(
                Circle().strokeBorder(option.id == color.id ? t.accent : .clear, lineWidth: 2)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.name)
    }

    private var titleField: some View {
        TextField("Enter your list title", text: $title)
            .textFieldStyle(.plain)
            .font(.inter(size: 13))
            .foregroundStyle(t.ink)
            .focused($isTitleFocused)
            .onSubmit { if canCreate { create() } }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .fill(t.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelpyMetrics.fieldCornerRadius, style: .continuous)
                    .strokeBorder(
                        isTitleFocused ? t.accent.opacity(0.8) : t.fieldBorder,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeOut(duration: 0.12), value: isTitleFocused)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .buttonStyle(HelpySecondaryButtonStyle(palette: t, cornerRadius: 18))
                .frame(maxWidth: .infinity, minHeight: 36)

            Button("Create", action: create)
                .buttonStyle(HelpyPrimaryButtonStyle(palette: t, cornerRadius: 18))
                .frame(maxWidth: .infinity, minHeight: 36)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    // MARK: - Actions

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, NSColor(color.color), icon)
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .svg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use as icon"
        panel.message = "Choose an image for this list"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        icon = NSImage(contentsOf: url)
    }
}

/// The colours a new list can take. Deliberately the Reminders palette rather
/// than an arbitrary one: the list shows up in Apple Reminders too, and a
/// colour it has no name for is a colour the user cannot pick again there.
struct ListColorOption: Identifiable, Equatable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }
    var color: Color { Color(hex: hex) }

    /// A checkmark on a pale swatch has to be dark to be seen at all.
    var needsDarkGlyph: Bool { hex == 0xF5C518 || hex == 0x5BE7C4 }

    static let options: [ListColorOption] = [
        ListColorOption(name: "Blue", hex: 0x0086E8),
        ListColorOption(name: "Indigo", hex: 0x5A5ACF),
        ListColorOption(name: "Purple", hex: 0xA25BD6),
        ListColorOption(name: "Pink", hex: 0xE0559B),
        ListColorOption(name: "Red", hex: 0xE0442F),
        ListColorOption(name: "Orange", hex: 0xEE8A20),
        ListColorOption(name: "Yellow", hex: 0xF5C518),
        ListColorOption(name: "Green", hex: 0x30B36B),
        ListColorOption(name: "Mint", hex: 0x5BE7C4),
        ListColorOption(name: "Graphite", hex: 0x5B6577)
    ]
}
