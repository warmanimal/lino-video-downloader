# Lino — Video Downloader for macOS

## Project Overview

Native macOS menu bar app for downloading and managing videos from social media (YouTube, TikTok, Instagram, X/Twitter, Pinterest). Built with Swift 6, SwiftUI, SPM (no Xcode project), yt-dlp, GRDB/SQLite.

## Project Structure

```
Lino/                          # SPM package root
├── Package.swift              # Swift 6, macOS 14+, GRDB + HotKey deps
├── Sources/Lino/
│   ├── LinoApp.swift          # @main, AppState, WindowGroup + MenuBarExtra
│   ├── Models/                # Video, Tag, VideoTag, VideoInfo, DownloadTask
│   ├── Persistence/           # AppDatabase, VideoRepository, TagRepository
│   ├── Services/              # DownloadService, MetadataService, VideoRemuxer, etc.
│   ├── ViewModels/            # LibraryViewModel, VideoDetailViewModel
│   ├── Views/                 # SwiftUI views (Library, Detail, MenuBar, Components)
│   └── Utilities/             # Constants, PlatformDetector, DateFormatters
├── Tests/LinoTests/
├── build-and-install.sh       # Build + install to /Applications
└── .build/                    # SPM build output
```

## Build & Run

```bash
# Build only
cd Lino && swift build

# Build, install to /Applications, and launch
./Lino/build-and-install.sh

# Run tests
cd Lino && swift test
```

The app bundle is at `Lino/.build/arm64-apple-macosx/debug/Lino.app`.

## Key Architecture Decisions

- **No Xcode project** — pure SPM. The .app bundle is pre-created at the build output path with Info.plist and icons.
- **yt-dlp** — standalone binary managed in `~/Library/Application Support/Lino/bin/`. Falls back to Homebrew `/opt/homebrew/bin/yt-dlp`.
- **ffmpeg** — required for stream merging and remuxing. System ffmpeg may be broken (dylib issues); `Constants.ffmpegPath` probes multiple Homebrew Cellar paths and smoke-tests each binary. Working binary: `/opt/homebrew/Cellar/ffmpeg-full/8.0.1_3/bin/ffmpeg`.
- **Post-download processing** — `VideoRemuxer.ensurePlayable()` runs immediately after every download in `DownloadService`. Handles container remuxing (MPEG-TS → MP4) and codec transcoding (VP9 → H.264 via VideoToolbox). Never deferred to the UI layer.
- **Storage** — videos in `~/Movies/Lino/`, thumbnails in `~/Movies/Lino/.thumbnails/`, database at `~/Library/Application Support/Lino/lino.sqlite`.
- **Soft-delete** — trash with 7-day expiry, purged on app launch.

## Important Patterns

- `@Observable` + `@MainActor` for all view models and `AppState`
- `DownloadService` uses `Task.detached` + `DispatchQueue.global()` for blocking subprocess calls (yt-dlp, ffmpeg, ffprobe) to avoid blocking the cooperative thread pool
- `--ffmpeg-location` is always passed to yt-dlp so it can merge multi-stream downloads
- Format sort: `-S "vcodec:h264,ext:mp4:m4a"` to prefer AVPlayer-compatible codecs
- Grid items use `Button` (not `onTapGesture`) for reliable click handling on macOS
- Thumbnail images use `.aspectRatio(contentMode: .fill)` — the containing ZStack must have `.frame(height:).clipped()` to constrain layout bounds

## Things to Avoid

- **Never call `VideoRemuxer.isPlayable()` or `videoCodec()` on the main thread** — these run ffprobe synchronously via `Process()` and will freeze the UI
- **Never use `AVAssetExportSession`** for remuxing — it silently fails on MPEG-TS input
- **Don't trust system ffmpeg** (`/opt/homebrew/bin/ffmpeg`) — it may have broken dylib links. Always use `Constants.ffmpegPath` which smoke-tests candidates
