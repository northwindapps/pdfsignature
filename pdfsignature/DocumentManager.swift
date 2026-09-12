import Foundation
import UIKit
import PDFKit

class DocumentManager {
    static let shared = DocumentManager()
    var documentURL: URL?
    var document: UIImage?
    /// Live, in-memory PDF for the current session. Kept around (rather than
    /// re-opening `documentURL` each time) so form-field edits and the
    /// ink/sticker annotation overlay both survive into the exported file.
    var pdfDocument: PDFDocument?
    private init() {}
}
