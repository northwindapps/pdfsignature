import Foundation
import PDFKit
import UIKit

class DocumentManager {
    static let shared = DocumentManager()
    var documentURL: URL?
    var document: UIImage?
    var pdfDocument: PDFDocument? 
    private init() {}
}
