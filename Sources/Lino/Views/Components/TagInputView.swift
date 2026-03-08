import SwiftUI

struct TagInputView: View {
    @Binding var tags: [String]
    @Environment(\.appState) private var appState
    @State private var inputText = ""
    @State private var suggestions: [Tag] = []
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tag chips
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(name: tag, isRemovable: true) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Input field
            ZStack(alignment: .topLeading) {
                TextField("Add tags...", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .onSubmit {
                        addTag(inputText)
                    }
                    .onChange(of: inputText) { _, newValue in
                        updateSuggestions(for: newValue)
                    }

                if showSuggestions && !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { tag in
                            Button {
                                addTag(tag.name)
                            } label: {
                                Text(tag.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .background(Color(.controlBackgroundColor))
                        }
                    }
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(6)
                    .shadow(radius: 4)
                    .offset(y: 34)
                    .zIndex(10)
                }
            }
        }
    }

    private func addTag(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.lowercased() == trimmed.lowercased() }) else {
            inputText = ""
            showSuggestions = false
            return
        }
        tags.append(trimmed)
        inputText = ""
        showSuggestions = false
    }

    private func updateSuggestions(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            showSuggestions = false
            return
        }

        do {
            suggestions = try appState.tagRepo.fetchMatching(prefix: trimmed)
                .filter { tag in !tags.contains(where: { $0.lowercased() == tag.name.lowercased() }) }
            showSuggestions = !suggestions.isEmpty
        } catch {
            suggestions = []
            showSuggestions = false
        }
    }
}

/// Simple flow layout for tag chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
