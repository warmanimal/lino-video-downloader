import SwiftUI
import PDFKit

/// A SwiftUI wrapper around PDFKit's PDFView for displaying PDF documents.
struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = false
        view.backgroundColor = NSColor(Color(.windowBackgroundColor))
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
    }
}
