import SwiftUI
import AppKit

// MARK: - Add / Edit Shortcut Sheet

struct AddShortcutSheet: View {
    let roomId: Int64
    let roomRepo: RoomRepository
    var editingShortcut: RoomShortcut? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var urlString = ""
    @State private var notes = ""
    @State private var iconData: Data? = nil
    @State private var customSymbol: String? = nil
    @State private var symbolColor: String = "accent"
    @State private var isFetchingIcon = false
    @State private var showIconPicker = false
    @State private var fetchTask: Task<Void, Never>? = nil

    private var isEditing: Bool { editingShortcut != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Link" : "Add Link")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isEditing ? "Save" : "Add") { commitSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding()

            Divider()

            VStack(spacing: 0) {
                // Icon + URL/Title fields
                HStack(alignment: .top, spacing: 16) {
                    iconPreviewButton
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 12) {
                        labeledField("Title", placeholder: "e.g. Google Calendar", text: $title)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("https://", text: $urlString)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: urlString) { _, newVal in
                                    scheduleIconFetch(for: newVal)
                                }
                        }
                    }
                }
                .padding(20)

                Divider()

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Notes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Optional")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    Text("Login credentials, API keys, or anything useful to remember.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 72, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .padding(20)
            }
        }
        .frame(width: 420)
        .onAppear { loadForEditing() }
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(
                currentSymbol: customSymbol,
                currentColor: symbolColor,
                onSelect: { sym, color in
                    customSymbol = sym
                    symbolColor = color
                    if sym != nil { iconData = nil } // symbol overrides favicon
                }
            )
        }
    }

    // MARK: - Icon preview button

    @ViewBuilder
    private var iconPreviewButton: some View {
        Button { showIconPicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 68, height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                if isFetchingIcon {
                    ProgressView().scaleEffect(0.75)
                } else if let sym = customSymbol {
                    Image(systemName: sym)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.shortcutColor(symbolColor))
                } else if let data = iconData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(Color(.windowBackgroundColor)).padding(2))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .help("Click to change icon")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func scheduleIconFetch(for urlStr: String) {
        fetchTask?.cancel()
        guard customSymbol == nil else { return }
        let trimmed = urlStr.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 4 else { return }

        fetchTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000) // 0.7 s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run { isFetchingIcon = true }
            let data = await FaviconService.shared.fetchFavicon(for: trimmed)
            await MainActor.run {
                isFetchingIcon = false
                if let data { iconData = data }
            }
        }
    }

    private func loadForEditing() {
        guard let s = editingShortcut else { return }
        title = s.title
        urlString = s.url
        notes = s.notes ?? ""
        iconData = s.iconData
        customSymbol = s.customSymbol
        symbolColor = s.symbolColor ?? "accent"
    }

    private func commitSave() {
        fetchTask?.cancel()

        var normalized = urlString.trimmingCharacters(in: .whitespaces)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var shortcut = RoomShortcut(
            id: editingShortcut?.id,
            roomId: roomId,
            title: title.trimmingCharacters(in: .whitespaces),
            url: normalized,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            iconData: customSymbol != nil ? nil : iconData,
            customSymbol: customSymbol,
            symbolColor: customSymbol != nil ? symbolColor : nil,
            sortOrder: editingShortcut?.sortOrder ?? 0
        )

        if isEditing {
            try? roomRepo.updateShortcut(shortcut)
        } else {
            let count = (try? roomRepo.fetchShortcuts(roomId: roomId))?.count ?? 0
            shortcut.sortOrder = count
            try? roomRepo.insertShortcut(shortcut)
        }
        dismiss()
    }
}

// MARK: - Icon Picker Sheet

struct IconPickerSheet: View {
    let currentSymbol: String?
    let currentColor: String
    let onSelect: (String?, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSymbol: String?
    @State private var selectedColor: String

    private let symbolGroups: [(String, [(sym: String, name: String)])] = [
        ("Web & Apps", [
            ("link", "Link"), ("globe", "Web"), ("safari", "Browser"),
            ("app.badge", "App"), ("network", "Network"),
        ]),
        ("Productivity", [
            ("calendar", "Calendar"), ("envelope.fill", "Email"),
            ("checkmark.square.fill", "Tasks"), ("doc.text.fill", "Document"),
            ("tray.full.fill", "Inbox"), ("clock.fill", "Schedule"),
            ("bell.fill", "Reminder"), ("list.bullet", "List"),
        ]),
        ("Work & Team", [
            ("person.2.fill", "Team"), ("chart.bar.fill", "Analytics"),
            ("folder.fill", "Project"), ("rectangle.3.group.fill", "Board"),
            ("bubble.left.and.bubble.right.fill", "Chat"), ("video.fill", "Video Call"),
            ("briefcase.fill", "Work"),
        ]),
        ("Dev & Tech", [
            ("terminal.fill", "Terminal"), ("cpu", "Code"),
            ("server.rack", "Server"), ("cloud.fill", "Cloud"),
            ("gearshape.fill", "Settings"), ("hammer.fill", "Build"),
            ("wrench.and.screwdriver.fill", "Tools"), ("curlybraces", "API"),
        ]),
        ("Security & Finance", [
            ("lock.fill", "Password"), ("key.fill", "Key"),
            ("shield.fill", "Security"), ("creditcard.fill", "Payment"),
            ("cart.fill", "Shop"), ("house.fill", "Home"),
        ]),
        ("Media & Other", [
            ("star.fill", "Favorite"), ("bookmark.fill", "Bookmark"),
            ("photo.fill", "Photos"), ("music.note", "Music"),
            ("play.circle.fill", "Video"), ("map.fill", "Map"),
            ("bolt.fill", "Quick"), ("wand.and.stars", "Magic"),
        ]),
    ]

    init(currentSymbol: String?, currentColor: String, onSelect: @escaping (String?, String) -> Void) {
        self.currentSymbol = currentSymbol
        self.currentColor = currentColor
        self.onSelect = onSelect
        _selectedSymbol = State(initialValue: currentSymbol)
        _selectedColor = State(initialValue: currentColor)
    }

    private var resolvedColor: Color {
        Color.shortcutColor(selectedColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Icon")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Done") {
                    onSelect(selectedSymbol, selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // Preview + color picker side by side
                    HStack(alignment: .top, spacing: 20) {
                        // Live preview
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.controlBackgroundColor))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                                )
                            if let sym = selectedSymbol {
                                Image(systemName: sym)
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(resolvedColor)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
                                ForEach(Color.shortcutColorOptions, id: \.name) { opt in
                                    colorDot(name: opt.name, color: opt.color)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Use auto-fetched favicon
                    Button {
                        onSelect(nil, selectedColor)
                        dismiss()
                    } label: {
                        Label("Use website favicon", systemImage: "globe")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)

                    Divider()

                    // Symbol groups
                    ForEach(symbolGroups, id: \.0) { groupName, symbols in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(groupName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 46), spacing: 6)],
                                spacing: 6
                            ) {
                                ForEach(symbols, id: \.sym) { item in
                                    symbolButton(sym: item.sym, name: item.name)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 380, height: 500)
    }

    @ViewBuilder
    private func colorDot(name: String, color: Color) -> some View {
        Button { selectedColor = name } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .shadow(color: color.opacity(0.45), radius: 2, y: 1)
                if selectedColor == name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: selectedColor)
    }

    @ViewBuilder
    private func symbolButton(sym: String, name: String) -> some View {
        let isSelected = selectedSymbol == sym
        Button { selectedSymbol = sym } label: {
            Image(systemName: sym)
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? resolvedColor : Color.primary.opacity(0.65))
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? resolvedColor.opacity(0.12) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? resolvedColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .help(name)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
