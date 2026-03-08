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
                viewModel = MenuBarViewModel(downloadService: appState.downloadService)
            }
        }
    }
}

private struct MenuBarPopoverContent: View {
    @Bindable var viewModel: MenuBarViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 12) {
            // Header
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

            Divider()

            // URL input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("URL")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if let platform = viewModel.detectedPlatform {
                        HStack(spacing: 4) {
                            PlatformBadgeView(platform: platform, size: 10)
                            Text(platform.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Paste video URL...", text: $viewModel.urlText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.urlText) { _, _ in
                            viewModel.validateURL()
                        }
                        .onSubmit {
                            if viewModel.isValidURL {
                                Task { await viewModel.submit() }
                            }
                        }

                    Button {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            viewModel.urlText = clipboard
                            viewModel.validateURL()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Paste from clipboard")
                }
            }

            // Tags
            VStack(alignment: .leading, spacing: 6) {
                Text("Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TagInputView(tags: $viewModel.tags)
            }

            // Status messages
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let success = viewModel.successMessage {
                Label(success, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            // Download button
            Button {
                Task { await viewModel.submit() }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isSubmitting ? "Fetching..." : "Download")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isValidURL || viewModel.isSubmitting)
            .keyboardShortcut(.return, modifiers: .command)

            // Active downloads
            if !viewModel.activeDownloads.isEmpty {
                Divider()
                DownloadProgressView(downloads: Array(viewModel.activeDownloads.values))
            }

            Spacer()
        }
        .padding()
    }
}
