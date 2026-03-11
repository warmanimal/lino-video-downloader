import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.appState) private var appState
    @State private var viewModel: MenuBarViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MenuBarPopoverContent(viewModel: viewModel)
                    .environment(appState)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MenuBarViewModel(
                    downloadService: appState.downloadService,
                    roomRepo: appState.roomRepo,
                    videoRepo: appState.videoRepo
                )
            }
        }
    }
}

// MARK: - Content

private struct MenuBarPopoverContent: View {
    @Bindable var viewModel: MenuBarViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack {
                Label("Lino", systemImage: "film.stack")
                    .font(.headline)
                Spacer()
                Button("Open Library") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── Scrollable form ─────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // URL
                    urlSection

                    if viewModel.isDuplicate {
                        // ── Duplicate path ───────────────────────────────
                        duplicateCard

                        notesSection

                        if !viewModel.rooms.isEmpty {
                            destinationSection
                        }

                        duplicateActions

                    } else {
                        // ── Normal path ──────────────────────────────────
                        tagsSection

                        notesSection

                        if !viewModel.rooms.isEmpty {
                            destinationSection
                        }

                        if let error = viewModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        submitButtons
                    }

                    // Active downloads (both paths)
                    if !viewModel.fetchingTasks.isEmpty || !viewModel.activeDownloads.isEmpty {
                        Divider()
                        DownloadProgressView(
                            fetchingTasks: viewModel.fetchingTasks,
                            downloads: Array(viewModel.activeDownloads.values)
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - URL section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("URL")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if viewModel.isDuplicateChecking {
                    ProgressView()
                        .controlSize(.mini)
                } else if let platform = viewModel.detectedPlatform {
                    HStack(spacing: 4) {
                        PlatformBadgeView(platform: platform, size: 10)
                        Text(platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextField("Paste video URL...", text: $viewModel.urlText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.urlText) { _, _ in viewModel.validateURL() }
                .onSubmit { if viewModel.isValidURL && !viewModel.isDuplicate { viewModel.submit() } }
        }
    }

    // MARK: - Duplicate card

    private var duplicateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Already in your library", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)

            if let info = viewModel.existingVideo {
                let video = info.video
                HStack(alignment: .top, spacing: 10) {
                    // Thumbnail
                    Group {
                        if let thumbPath = video.absoluteThumbnailPath,
                           let img = NSImage(contentsOf: thumbPath) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if video.isTextOnly {
                            Rectangle()
                                .fill(Color(.controlBackgroundColor))
                                .overlay(alignment: .topLeading) {
                                    Text(video.description ?? video.title)
                                        .font(.system(size: 6))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .padding(3)
                                }
                        } else {
                            Rectangle()
                                .fill(Color(.separatorColor))
                                .overlay {
                                    Image(systemName: video.isPDF ? "doc.richtext" : (video.isImage ? "photo" : "film"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 64, height: 36)
                    .cornerRadius(4)
                    .clipped()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)

                        // Current memberships
                        if let m = viewModel.existingMemberships {
                            if m.isEmpty {
                                Text("In library — not assigned to any Room or Collection")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(m.directRooms, id: \.id) { room in
                                    Label(room.name, systemImage: "house")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(m.collections, id: \.collection.id) { item in
                                    Label("\(item.room.name) › \(item.collection.name)", systemImage: "folder")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.subheadline)
                .fontWeight(.medium)
            TagInputView(tags: $viewModel.tags)
        }
    }

    // MARK: - Notes (multi-line)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.notes)
                    .font(.body)
                    .frame(minHeight: 58, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(4)

                if viewModel.notes.isEmpty {
                    Text("Add a note…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Destination picker (room first, then collection)

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Save to")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Room picker
            HStack {
                Picker(selection: $viewModel.selectedRoomId) {
                    Text("All Items").tag(Int64?.none)
                    ForEach(viewModel.rooms) { room in
                        if let id = room.id {
                            Label(room.name, systemImage: "house")
                                .tag(Optional(id))
                        }
                    }
                } label: { EmptyView() }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: viewModel.selectedRoomId) { _, _ in
                    viewModel.selectedCollectionId = nil
                }
                Spacer()
            }

            // Collection picker — only when a room is selected and has collections
            if let roomId = viewModel.selectedRoomId {
                let cols = viewModel.collections(for: roomId)
                if !cols.isEmpty {
                    HStack {
                        Picker(selection: $viewModel.selectedCollectionId) {
                            Text("No collection").tag(Int64?.none)
                            ForEach(cols) { col in
                                if let id = col.id {
                                    Label(col.name, systemImage: "folder")
                                        .tag(Optional(id))
                                }
                            }
                        } label: { EmptyView() }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Action buttons

    private var submitButtons: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isValidURL)

            Button {
                viewModel.submit()
            } label: {
                Text("Download")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isValidURL)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var duplicateActions: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.updateExisting()
            } label: {
                Text("Update")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.destination == nil && viewModel.notes == (viewModel.existingVideo?.video.notes ?? ""))

            Button {
                viewModel.clear()
            } label: {
                Text("Clear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
