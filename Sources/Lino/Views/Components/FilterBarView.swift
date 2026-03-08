import SwiftUI

struct FilterBarView: View {
    @Binding var searchText: String
    @Binding var selectedPlatform: Video.Platform?
    @Binding var selectedTagIds: [Int64]
    @Binding var sortBy: SortField

    @Environment(\.appState) private var appState
    @State private var allTags: [Tag] = []

    var body: some View {
        HStack(spacing: 8) {
            // Platform filter
            Menu {
                Button("All Platforms") {
                    selectedPlatform = nil
                }
                Divider()
                ForEach(Video.Platform.allCases, id: \.self) { platform in
                    Button {
                        selectedPlatform = platform
                    } label: {
                        Label(platform.displayName, systemImage: platform.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedPlatform?.systemImage ?? "line.3.horizontal.decrease.circle")
                    Text(selectedPlatform?.displayName ?? "Platform")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Tag filter
            Menu {
                Button("Clear Tags") {
                    selectedTagIds = []
                }
                Divider()
                ForEach(allTags) { tag in
                    Button {
                        if let tagId = tag.id {
                            if selectedTagIds.contains(tagId) {
                                selectedTagIds.removeAll { $0 == tagId }
                            } else {
                                selectedTagIds.append(tagId)
                            }
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            if let tagId = tag.id, selectedTagIds.contains(tagId) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text(selectedTagIds.isEmpty ? "Tags" : "\(selectedTagIds.count) tag(s)")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Sort
            Menu {
                ForEach(SortField.allCases, id: \.self) { field in
                    Button {
                        sortBy = field
                    } label: {
                        HStack {
                            Text(field.rawValue)
                            if sortBy == field {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortBy.rawValue)
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .onAppear {
            loadTags()
        }
    }

    private func loadTags() {
        allTags = (try? appState.tagRepo.fetchAll()) ?? []
    }
}
