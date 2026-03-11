import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @State private var storagePath = Constants.storageDir.path
    @State private var showFilePicker = false

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            YtDlpSettingsView()
                .environment(appState)
                .tabItem {
                    Label("yt-dlp", systemImage: "arrow.down.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.appState) private var appState
    @State private var storagePath = Constants.storageDir.path

    var body: some View {
        Form {
            Section("Storage") {
                HStack {
                    TextField("Download Directory", text: $storagePath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Choose...") {
                        chooseDirectory()
                    }
                }
                Text("Videos will be saved to this directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                Stepper(
                    "Max concurrent downloads: \(appState.downloadService.maxConcurrent)",
                    value: Binding(
                        get: { appState.downloadService.maxConcurrent },
                        set: { appState.downloadService.maxConcurrent = $0 }
                    ),
                    in: 1...5
                )
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Quick Add URL")
                    Spacer()
                    Text("Cmd + Shift + L")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                        .font(.caption)
                        .monospaced()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            storagePath = url.path
        }
    }
}

private struct YtDlpSettingsView: View {
    @Environment(\.appState) private var appState
    @State private var showFilePicker = false

    var body: some View {
        Form {
            Section("yt-dlp Binary") {
                HStack {
                    Text("Path")
                    Spacer()
                    Text(Constants.ytdlpPath.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    if let version = appState.ytdlpUpdateService.currentVersion {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Button("Check for Update") {
                        Task {
                            await appState.ytdlpUpdateService.checkForUpdate()
                        }
                    }
                    .disabled(appState.ytdlpUpdateService.isUpdating)

                    if appState.ytdlpUpdateService.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button("Install from File...") {
                        installFromFile()
                    }
                }

                if let error = appState.ytdlpUpdateService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("About yt-dlp") {
                Text("yt-dlp is the engine that downloads videos from YouTube, TikTok, Instagram, X, Pinterest, Suno, and many other sites. Keeping it updated ensures compatibility with the latest site changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func installFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the yt-dlp binary"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await appState.ytdlpUpdateService.installFromFile(url)
                } catch {
                    print("Failed to install yt-dlp: \(error)")
                }
            }
        }
    }
}
