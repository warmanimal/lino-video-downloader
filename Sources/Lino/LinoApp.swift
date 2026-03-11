import SwiftUI
import AppKit

@main
struct LinoApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(\.appState, appState)
                .frame(minWidth: 700, minHeight: 450)
                .onAppear {
                    appState.hotkeyService.register {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        // Open a new window if none exist
                        if NSApplication.shared.windows.filter({ $0.isVisible && !$0.className.contains("StatusBar") }).isEmpty {
                            NSApplication.shared.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
                        }
                    }
                }
        }
        .defaultSize(width: 960, height: 640)

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(\.appState, appState)
                .frame(width: 360, height: 500)
        } label: {
            Label("Lino", systemImage: "heart.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(\.appState, appState)
        }
    }
}

@Observable
@MainActor
final class AppState {
    let database: AppDatabase
    let videoRepo: VideoRepository
    let tagRepo: TagRepository
    let roomRepo: RoomRepository
    let metadataService: MetadataService
    let thumbnailService: ThumbnailService
    let downloadService: DownloadService
    let fileImportService: FileImportService
    let ytdlpUpdateService: YtDlpUpdateService
    let hotkeyService: HotkeyService

    init() {
        let db: AppDatabase
        do {
            db = try AppDatabase.makeShared()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }

        self.database = db
        self.videoRepo = VideoRepository(db: db)
        self.tagRepo = TagRepository(db: db)
        self.roomRepo = RoomRepository(db: db)
        self.metadataService = MetadataService()
        self.thumbnailService = ThumbnailService()
        self.downloadService = DownloadService(
            videoRepo: VideoRepository(db: db),
            metadataService: MetadataService(),
            thumbnailService: ThumbnailService(),
            roomRepo: RoomRepository(db: db)
        )
        self.fileImportService = FileImportService(videoRepo: VideoRepository(db: db))
        self.ytdlpUpdateService = YtDlpUpdateService()
        self.hotkeyService = HotkeyService()

        // Ensure yt-dlp is available (async to avoid blocking main thread during init)
        let service = ytdlpUpdateService
        Task {
            await service.ensureAvailable()
        }
    }
}

private struct AppStateKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
