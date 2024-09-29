import Foundation
import UIKit

class DocumentManager {
    static let shared = DocumentManager()
    var documentURL: URL?
    var document: UIImage?
    private init() {}
}
