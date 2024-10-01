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
//import GoogleAPIClientForREST
//import GoogleSignIn


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
        
        if url.absoluteString.contains(".pdf"){
            DocumentManager.shared.documentURL = url
        }
        
        if let pdfURL = DocumentManager.shared.documentURL {
            if let pngImages = convertPDFToPNG(pdfURL: pdfURL) {
                if let firstImage = pngImages.first {
                    DocumentManager.shared.document = firstImage
                }
            }
            
            DocumentManager.shared.pdfDocument = PDFDocument(url: pdfURL)
        }
        
        let targetViewController = self.storyboard!.instantiateViewController( withIdentifier: "initialview" ) as! ViewController//Landscape
        targetViewController.modalPresentationStyle = .fullScreen
        DispatchQueue.main.async {
            self.present(targetViewController, animated: true, completion: nil)
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
    
    func convertPDFToPNG(pdfURL: URL) -> [UIImage]? {
        guard let pdfDocument = PDFDocument(url: pdfURL) else { return nil }
        
        var pngImages: [UIImage] = []
        
        // Loop through each page in the PDF
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let pdfPage = pdfDocument.page(at: pageIndex) else { continue }
            
            // Get the PDF page's size and create a UIImage
            let pageRect = pdfPage.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            
            let image = renderer.image { ctx in
                // Draw the page into the context
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                
                pdfPage.draw(with: .mediaBox, to: ctx.cgContext)
            }
            
            pngImages.append(image)
        }
        
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
    
    
 
