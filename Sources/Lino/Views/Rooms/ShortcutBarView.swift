import SwiftUI
import AppKit

// MARK: - Shortcut Bar

struct ShortcutBarView: View {
    let shortcuts: [RoomShortcut]
    let onAdd: () -> Void
    let onEdit: (RoomShortcut) -> Void
    let onDelete: (RoomShortcut) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    ShortcutChipView(
                        shortcut: shortcut,
                        onEdit: { onEdit(shortcut) },
                        onDelete: { onDelete(shortcut) }
                    )
                }
                AddShortcutChipButton(action: onAdd)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chip

struct ShortcutChipView: View {
    let shortcut: RoomShortcut
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: shortcut.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 7) {
                ShortcutIconView(shortcut: shortcut)
                    .frame(width: 18, height: 18)

                Text(shortcut.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.13 : 0.06),
                        radius: isHovered ? 7 : 3,
                        y: isHovered ? 2 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.13 : 0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .help(shortcut.notes.map { $0.isEmpty ? shortcut.url : $0 } ?? shortcut.url)
        .contextMenu {
            Button("Open") {
                if let url = URL(string: shortcut.url) { NSWorkspace.shared.open(url) }
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shortcut.url, forType: .string)
            }
            if let notes = shortcut.notes, !notes.isEmpty {
                Button("Copy Notes") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes, forType: .string)
                }
            }
            Divider()
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Icon view (reused in chip + sheet)

struct ShortcutIconView: View {
    let shortcut: RoomShortcut

    var body: some View {
        Group {
            if let sym = shortcut.customSymbol {
                Image(systemName: sym)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.shortcutColor(shortcut.symbolColor ?? "accent"))
            } else if let data = shortcut.iconData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - "Add Link" dashed chip

struct AddShortcutChipButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add Link")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.primary.opacity(isHovered ? 0.22 : 0.13),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Color helper

extension Color {
    static func shortcutColor(_ name: String) -> Color {
        switch name {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "teal":   return .teal
        case "blue":   return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink":   return .pink
        default:       return .accentColor
        }
    }

    static let shortcutColorOptions: [(name: String, color: Color)] = [
        ("accent", .accentColor), ("blue", .blue), ("purple", .purple),
        ("pink", .pink), ("red", .red), ("orange", .orange),
        ("yellow", .yellow), ("green", .green), ("teal", .teal), ("indigo", .indigo),
    ]
}
