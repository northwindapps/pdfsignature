//
//  ViewController4.swift
//  dictionary
//
//  Created by 矢野悠人 on 2017/06/22.
//  Copyright © 2017年 yumiya. All rights reserved.
//

import UIKit
import Foundation
import PDFKit
import Alamofire
//import GoogleAPIClientForREST
//import GoogleSignIn

struct APIResponse: Codable {
    let body: String
    let headers: [String: String]?
}

class iCloudController: UIViewController,UIDocumentMenuDelegate,UIDocumentPickerDelegate,UINavigationControllerDelegate,FileManagerDelegate{
    
    func documentMenu(_ documentMenu: UIDocumentMenuViewController, didPickDocumentPicker documentPicker: UIDocumentPickerViewController) {
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }
    
    private func setupActivityIndicator() {
        // Set the center and color of the activity indicator
        activityIndicator.center = view.center
        activityIndicator.color = .gray
        
        // Add it to the view hierarchy
        view.addSubview(activityIndicator)
    }
    
    var excelName = ""
    
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    //var activityIndicator: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        let appd : AppDelegate = UIApplication.shared.delegate as! AppDelegate
        super.viewDidLoad()
        Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(self.timerUpdate), userInfo: nil, repeats: false)
        startLoading()
    }
    
    func startLoading() {
        setupActivityIndicator()
        activityIndicator.startAnimating()
        
        // Optionally, disable user interaction to prevent interaction during loading
        //view.isUserInteractionEnabled = false
    }
    
    func stopLoading() {
        
        self.activityIndicator.stopAnimating()
        // Re-enable user interaction
        view.isUserInteractionEnabled = true
    }
    
    
    //https://qiita.com/KikurageChan/items/5b33f95cbec9e0d8a05f
    @objc func timerUpdate() {
        print("update")
        
        let source = ["com.adobe.pdf"] // UTI for PDF files
        let documentPicker = UIDocumentPickerViewController(documentTypes: source, in: .import) // Import mode
        documentPicker.delegate = self
        self.present(documentPicker, animated: true, completion: nil)
        
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        print("this is url")
        print(url)
        print(url.absoluteString)
        //g.sheet 未対応
        //csvPath = url.absoluteString
        //http://stackoverflow.com/questions/28641325/using-uidocumentpickerviewcontroller-to-import-text-in-swift
        //http://qiita.com/nwatabou/items/898bc4395adbb2e05f8d
        //http://stackoverflow.com/questions/32263893/cast-nsstringcontentsofurl-to-string
        //http://qiita.com/nwatabou/items/898bc4395adbb2e05f8d
        //http://miyano-harikyu.jp/sola/devlog/2013/11/22/post-113/
        //https://developer.apple.com/reference/foundation/nsfilemanager
        //
        
        if url.absoluteString.hasSuffix(".pdf"){
            if let savedURL = moveToDocuments(originalURL: url) {
                DocumentManager.shared.documentURL = savedURL
            }
        }
        
        if let pdfURL = DocumentManager.shared.documentURL {
            // Show loading indicator
            let loadingAlert = UIAlertController(title: "Processing", message: "Converting PDF...", preferredStyle: .alert)
            present(loadingAlert, animated: true)
            
            Task {
                do {
                    print("Uploading PDF...")
                    let (imageData, contentType) = try await uploadPDFAndGetImage(pdfURL: pdfURL)
                    print("Received image: \(imageData.count) bytes, type: \(contentType)")
                    
                    // Create UIImage to verify it's valid
                    if let image = UIImage(data: imageData) {
                        print("Valid image created: \(image.size.width) x \(image.size.height)")
                        DocumentManager.shared.document = image
                    }
                    
                    // Also set the PDF document
                    DocumentManager.shared.pdfDocument = PDFDocument(url: pdfURL)
                    
                    // Dismiss loading and present view controller
                    await MainActor.run {
                        loadingAlert.dismiss(animated: true) {
                            let targetViewController = self.storyboard!.instantiateViewController(withIdentifier: "initialview") as! ViewController
                            targetViewController.modalPresentationStyle = .fullScreen
                            self.present(targetViewController, animated: true)
                        }
                    }
                    
                } catch {
                    print("Error: \(error)")
                    
                    // Dismiss loading and show error
                    await MainActor.run {
                        loadingAlert.dismiss(animated: true) {
                            let errorAlert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        }

        print("end iCloudController")
    }
    
  

    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        //dismiss(animated: true, completion: nil)
        let targetViewController = self.storyboard!.instantiateViewController( withIdentifier: "initialview" ) as! ViewController//Landscape
        targetViewController.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(targetViewController, animated: true, completion: nil)
        }
    }

    // Upload function
    func uploadPDFAndGetImage(pdfURL: URL) async throws -> (Data, String) {
        let apiURL = URL(string: "https://rzv9j9vrvd.execute-api.ap-northeast-1.amazonaws.com/dev/process-image")!
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let pdfData = try Data(contentsOf: pdfURL)
        let filename = pdfURL.lastPathComponent
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"pdf\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(pdfData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Status: \(httpResponse.statusCode)")
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        
        guard let imageData = Data(base64Encoded: apiResponse.body) else {
            throw NSError(domain: "DecodeError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image"])
        }
        
        let contentType = apiResponse.headers?["Content-Type"] ?? "image/png"
        
        return (imageData, contentType)
    }

    
    func moveToDocuments(originalURL: URL) -> URL? {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsURL.appendingPathComponent(originalURL.lastPathComponent)
        
        do {
            // Remove if it already exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: originalURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Failed to move file: \(error)")
            return nil
        }
    }


    
    func convertPDFToPNG(pdfURL: URL) -> [UIImage]? {
        guard let pdfDocument = PDFDocument(url: pdfURL) else { return nil }
        
        var pngImages: [UIImage] = []
        
        if let page = pdfDocument.page(at: 0) {
            let pageRect = page.bounds(for: .cropBox) // instead of .cropBox
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let img = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            pngImages.append(img)
        }
        
//        for pageIndex in 0..<pdfDocument.pageCount {
//            guard let pdfPage = pdfDocument.page(at: pageIndex) else { continue }
//            
//            let scale: CGFloat = 3.0  // Increase for higher resolution
//            let pageRect = pdfPage.bounds(for: .mediaBox)
//            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
//
//            let renderer = UIGraphicsImageRenderer(size: scaledSize)
//            let image = renderer.image { ctx in
//                let context = ctx.cgContext
//
//                // Optional: white background
//                UIColor.white.set()
//                ctx.fill(CGRect(origin: .zero, size: scaledSize))
//                
//                // Flip and scale
//                context.saveGState()
//                context.translateBy(x: 0, y: scaledSize.height)
//                context.scaleBy(x: scale, y: -scale)
//
//                // Now draw the PDF content
//                pdfPage.draw(with: .mediaBox, to: context)
//                context.restoreGState()
//            }
//            
//            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
//
//            
//            pngImages.append(image)
//        }
        
        return pngImages
    }

    
    
    
    
    //https://stackoverflow.com/questions/44160111/what-is-the-equivalent-of-string-encoding-utf8-rawvalue-in-objective-c
    func swiftDataToString(someData:Data) -> String? {
        return String(data: someData, encoding: .utf8)
    }
    
    func swiftStringToData(someStr:String) ->Data? {
        return someStr.data(using: .utf8)
    }
    
    
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    
    
    //Making the array with unique values
    func uniquing(src:[String]) -> [String]{
        var unique = [String]()
        
        for i in 0 ..< src.count {
            if unique.contains(src[i])
            {
                
            }else{
                unique.append(src[i])
            }
        }
        return unique
    }
    
    
    func getRootDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
}
    
    
 
