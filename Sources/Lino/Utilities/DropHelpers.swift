import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    /// Resolves a drag provider to a local file URL.
    ///
    /// - Finder / Files drags: returns the file URL directly.
    /// - Photos / image drags: asks the system to export to a temp file,
    ///   copies it (since the temp file is only valid inside the callback),
    ///   and returns the copy's URL.
    func loadLocalFileURL() async -> URL? {
        // 1. Direct file URL (Finder, Files app, etc.)
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let result: URL? = await withCheckedContinuation { cont in
                loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       url.isFileURL {
                        cont.resume(returning: url)
                    } else if let url = item as? URL, url.isFileURL {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            if let result { return result }
        }

        // 2. PDF files — use loadFileRepresentation as a robust fallback.
        //    macOS 14/15 sometimes exposes PDFs under com.adobe.pdf rather than fileURL,
        //    and loadItem may return an unexpected object type for PDF providers.
        if hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            let result: URL? = await withCheckedContinuation { cont in
                loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { tempURL, _ in
                    guard let tempURL else { cont.resume(returning: nil); return }
                    let copyURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".pdf")
                    if (try? FileManager.default.copyItem(at: tempURL, to: copyURL)) != nil {
                        cont.resume(returning: copyURL)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            if let result { return result }
        }

        // 3. Photos / pasteboard images — ask system to export to a temp file.
        //    We must copy the file before the closure returns (it gets cleaned up after).
        let imageUTIs = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
            UTType.heif.identifier,
            UTType.image.identifier,
        ]
        for uti in imageUTIs {
            guard hasItemConformingToTypeIdentifier(uti) else { continue }
            let result: URL? = await withCheckedContinuation { cont in
                loadFileRepresentation(forTypeIdentifier: uti) { tempURL, _ in
                    guard let tempURL else { cont.resume(returning: nil); return }
                    let ext = tempURL.pathExtension.isEmpty ? "jpg" : tempURL.pathExtension
                    let copyURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "." + ext)
                    if (try? FileManager.default.copyItem(at: tempURL, to: copyURL)) != nil {
                        cont.resume(returning: copyURL)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            if let result { return result }
        }

        return nil
    }

    /// Returns a web URL (http/https) if this provider carries one, else nil.
    func loadWebURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { cont in
            loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                let isWeb = url?.scheme == "https" || url?.scheme == "http"
                cont.resume(returning: isWeb ? url : nil)
            }
        }
    }
}
