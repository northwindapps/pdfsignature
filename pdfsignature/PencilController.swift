import UIKit
import PDFKit
import Vision
import PencilKit
import MessageUI

class PencilController: UIViewController, PKCanvasViewDelegate,PKToolPickerObserver , UIGestureRecognizerDelegate, UITextViewDelegate,MFMailComposeViewControllerDelegate{

    var canvasView: CustomCanvasView!
    var toolPicker: PKToolPicker!
    var scrollView: UIScrollView!
    var timer: Timer?
    var id = ""
    var imageView: UIImageView!
    var strokeHistoryView: UIImageView!
    var saveButton: UIButton!
    var inputBtn:UIButton!
    var inputMode = false
    var activityIndicator = UIActivityIndicatorView(style: .medium)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupActivityIndicator()
        activityIndicator.startAnimating()
        let topMargin: CGFloat = 60

        // Create UIScrollView with margin
        scrollView = UIScrollView(frame: CGRect(x: 0, y: topMargin, width: view.bounds.width, height: view.bounds.height - topMargin))
        scrollView.contentSize = CGSize(width: view.bounds.width * 2, height: view.bounds.height * 2)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        
        // Create ImageView
        if let firstImage = DocumentManager.shared.document {
            imageView = UIImageView(image: firstImage)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.addSubview(imageView)
            imageView.contentMode = .scaleAspectFit
            //initialize
            strokeHistoryView =  UIImageView(image: firstImage)
            strokeHistoryView.image = UIImage()
        }

        if DocumentManager.shared.documentURL == nil {
            return
        }
        
        if DocumentManager.shared.document == nil {
            return
        }

        // Create PKCanvasView
        canvasView = CustomCanvasView(frame: CGRect(x: 0, y: 0, width: imageView.frame.width, height: imageView.frame.height))
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        scrollView.delegate = self
        scrollView.addSubview(canvasView)
        scrollView.isScrollEnabled = false
        
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
            scrollView.addGestureRecognizer(pinchGestureRecognizer)
        
        canvasView.delegate = self
        canvasView.drawingPolicy = .anyInput
        canvasView.isUserInteractionEnabled = true

      

        // Add reset strokes button
        let resetStrokeButton = UIButton(type: .system)
        resetStrokeButton.setTitle("Adjust", for: .normal)
        resetStrokeButton.addTarget(self, action: #selector(scaleDown), for: .touchUpInside)
        view.addSubview(resetStrokeButton)
        resetStrokeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resetStrokeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resetStrokeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        
        // Add reset strokes button
        saveButton = UIButton(type: .system)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(.red, for: .normal)
        saveButton.addTarget(self, action: #selector(saveStroke), for: .touchUpInside)
        view.addSubview(saveButton)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            saveButton.trailingAnchor.constraint(equalTo: resetStrokeButton.leadingAnchor, constant: -20),
            saveButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        saveButton.isHidden = true
        
        
        // Add reset strokes button
        let resetStrokeButton3 = UIButton(type: .system)
        resetStrokeButton3.setTitle("Export", for: .normal)
        resetStrokeButton3.addTarget(self, action: #selector(exportPDF), for: .touchUpInside)
        view.addSubview(resetStrokeButton3)
        resetStrokeButton3.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resetStrokeButton3.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -20),
            resetStrokeButton3.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        
        // Add reset strokes button
        let importButton = UIButton(type: .system)
        importButton.setTitle("Import", for: .normal)
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)
        view.addSubview(importButton)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            importButton.trailingAnchor.constraint(equalTo: resetStrokeButton3.leadingAnchor, constant: -20),
            importButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
        
        // Add reset strokes button
        inputBtn = UIButton(type: .system)
        inputBtn.setTitle("Mode:w", for: .normal)
        inputBtn.addTarget(self, action: #selector(switchInput), for: .touchUpInside)
        view.addSubview(inputBtn)
        inputBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inputBtn.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -20),
            inputBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])

        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotification), name: Notification.Name("notification"), object: nil)
        
    }
    
    private func setupActivityIndicator() {
        // Set the center and color of the activity indicator
        activityIndicator.center = view.center
        activityIndicator.color = .gray
        
        // Add it to the view hierarchy
        view.addSubview(activityIndicator)
    }
    
    //sendEmail
    @objc func pdfEmail(data: Data) {
        if MFMailComposeViewController.canSendMail() {
            let today: Date = Date()
            let dateFormatter: DateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM-dd-yyyy HH:mm"
            let date = dateFormatter.string(from: today)

            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self

            // Set the subject
            mail.setSubject("Here's your PDF")

            // Attach PDF file (Update MIME type to "application/pdf")
            mail.addAttachmentData(data, mimeType: "application/pdf", fileName: "document-\(date).pdf")

            // Present the mail composer
            present(mail, animated: true, completion: nil)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true, completion: nil)
    }

    
    @objc func handleNotification() {
        print("Notification received in ViewController!")
        saveButton.isHidden = false
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(self)
        //configureCanvas()
        canvasView.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        self.view.bringSubviewToFront(canvasView)
        activityIndicator.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(self)
        //configureCanvas()
        canvasView.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        self.view.bringSubviewToFront(canvasView)
        activityIndicator.isHidden = true
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func startTimer() {
            // Invalidate any existing timer
            timer?.invalidate()
            
            // Schedule a new timer to fire after 2 seconds
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                // This block of code will be executed when the timer fires
                self.timerFired()
            }
        }
        
    func timerFired() {
        // Do something when the timer fires
        print("Timer fired after 2 seconds!")
        scrollView.isScrollEnabled = false
    }
    
    @objc func handlePinchGesture(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view else { return }
        toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(self)
        //configureCanvas()
        canvasView.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        self.view.bringSubviewToFront(canvasView)
        activityIndicator.isHidden = true
        
    }
    

    deinit {
        // Unregister notification when view controller is deallocated
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("notification"), object: nil)
        
    }
    
    
    @objc func scaleDown() {
        //canvasView.drawing = PKDrawing()
        //scrollView.setZoomScale(scrollView.maximumZoomScale, animated: true)
        canvasView.shrinkStrokes(by: 1.3)
    }
    
    
    
    @objc func saveStroke() {
        //canvasView.drawing = PKDrawing()
        //scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        let penTool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.tool = penTool
        if let screenshot = takeScreenshot(of: imageView, with: canvasView) {
            imageView.image = screenshot
            canvasView.drawing = PKDrawing()
            saveButton.isHidden = true
        }
        
        //save on SHV
        if strokeHistoryView != nil, let screenshot = takeScreenshot(of: strokeHistoryView, with: canvasView) {
            strokeHistoryView.image = screenshot
            strokeHistoryView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            strokeHistoryView.contentMode = .scaleAspectFit
        }
    }
    
    @objc func exportPDF() {
        let penTool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.tool = penTool
        if let screenshot = takeScreenshot(of: imageView, with: canvasView) {
            
            if let pdfData = saveStrokeToPDF() {
                //pdfEmail(data: pdfData)
                pdfEmail(data: pdfData)
            }
            
            canvasView.drawing = PKDrawing()
            saveButton.isHidden = true
        }
    }
    
    // Function to convert a UIImage to PDF
    func convertImageToPDF(image: UIImage) -> Data? {
        let pdfPageBounds = CGRect(origin: .zero, size: image.size)
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pdfPageBounds, nil)
        UIGraphicsBeginPDFPage()
        
        guard let pdfContext = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw the image in the PDF context
        image.draw(in: pdfPageBounds)
        
        UIGraphicsEndPDFContext()
        
        return pdfData as Data
    }

    // Function to save PDF data to the file system
    func savePDF(data: Data) {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let pdfPath = documentsPath?.appendingPathComponent("screenshot.pdf")
        
        do {
            try data.write(to: pdfPath!)
            print("PDF saved to: \(pdfPath!)")
        } catch {
            print("Failed to save PDF: \(error)")
        }
    }

    
    @objc func switchInput() {
        scrollView.isScrollEnabled = !scrollView.isScrollEnabled
        if scrollView.isScrollEnabled{
            inputBtn.setTitle("Mode:s", for: .normal)
        }
        
        if !scrollView.isScrollEnabled{
            inputBtn.setTitle("Mode:w", for: .normal)
        }
    }
    
    @objc func importPDF() {
        if let target = storyboard?.instantiateViewController(withIdentifier: "icloud") as? iCloudController {
            target.modalPresentationStyle = .fullScreen
            present(target, animated: true, completion: nil)
        }
    }
    
    func takeScreenshot(of imageView: UIImageView, with canvasView: UIView) -> UIImage? {
        let imageViewSize = imageView.bounds.size
        let scale: CGFloat = 3.0 // 4x resolution for higher quality

        // Create a renderer with the scaled size for high resolution
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageViewSize.width * scale, height: imageViewSize.height * scale))

        let image = renderer.image { context in
            // Apply scaling to the context
            context.cgContext.scaleBy(x: scale, y: scale)

            if imageView.image != nil {
                // Save the current content offset and frame of imageView
                let savedFrame = imageView.frame
                
                // Adjust the imageView frame to match its bounds size
                imageView.frame = CGRect(origin: .zero, size: imageViewSize)
                
                // Render the entire content of the imageView
                imageView.layer.render(in: context.cgContext)
                
                // Restore the original frame
                imageView.frame = savedFrame
            }

            // Render the canvasView on top of the imageView content
            let canvasOriginInImageView = canvasView.convert(canvasView.bounds.origin, to: imageView)
            context.cgContext.translateBy(x: canvasOriginInImageView.x * scale, y: canvasOriginInImageView.y * scale)
            canvasView.layer.render(in: context.cgContext)
        }

        return image
    }

    func saveStrokeToPDF() -> Data? {
        guard let existingPDF = DocumentManager.shared.document,
              let pdfDocument = PDFDocument(url: DocumentManager.shared.documentURL!) else {
            print("No existing PDF document found.")
            return nil
        }

        // Create a renderer to capture the canvas view
        let renderer = UIGraphicsImageRenderer(size: strokeHistoryView.bounds.size)

        // Get the first page of the PDF
        if let pdfPage = pdfDocument.page(at: 0) {
            let pdfPageBounds = pdfPage.bounds(for: .mediaBox)

            // Resize the canvas image to match the PDF page size
            if let resizedCanvasImage = resizeImage(image: strokeHistoryView.image!, targetSize: pdfPageBounds.size) {
                // Create a new annotation
                let imageBounds = CGRect(x: 0, y: 0, width: pdfPageBounds.width, height: pdfPageBounds.height)
                let annotation = PDFImageAnnotation(resizedCanvasImage, bounds: imageBounds, properties: nil)

                // Add the annotation to the page
                pdfPage.addAnnotation(annotation)
            }
        }

        // Return the modified PDF as Data
        return pdfDocument.dataRepresentation()
    }
    

    // Helper function to resize the image to match the PDF page size
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resizedImage
    }
    
    func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) {
            // This method is called when the selected tool in the tool picker changes
            let selectedTool = toolPicker.selectedTool
            
            // Perform actions based on the selected tool
            print("Selected tool changed to:", selectedTool)
            // Perform actions based on the active tool
            canvasView.tool = selectedTool
            switch selectedTool {
            case is PKInkingTool:
                // The active tool is an inking tool (pen)
                print("Using pen tool")
            case is PKEraserTool:
                // The active tool is an eraser
                print("Using eraser tool")
            case is PKLassoTool:
                // The active tool is a lasso (selection) tool
                print("Using lasso tool")
            default:
                // Default case if no specific tool is identified
                print("Using default tool")
            }
        
        
        }
    

    
    func configureCanvas() {
        let penTool = PKInkingTool(.pen, color: .black, width: 1) // Adjust width as needed
        canvasView.tool = penTool
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        
        // Set other canvas configurations
        if #available(iOS 14.0, *) {
            canvasView.drawingPolicy = .anyInput
        }
        canvasView.allowsFingerDrawing = true
        
        // You can also set initial tool and observe changes like this:
        canvasView.addObserver(self, forKeyPath: "tool", options: .new, context: nil)
    }
           
    

    override func viewDidLayoutSubviews() {
           super.viewDidLayoutSubviews()

        if (canvasView != nil){
            // Update the canvasView frame to match the scrollView contentSize
            canvasView.frame = CGRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
        }
       }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "tool" {
                // Handle tool change
                if let newTool = change?[.newKey] as? PKTool {
                    print("Tool changed to:", newTool)
                    // Do something with the new tool
                }
            }
        }
    
    
    private func loadDataFromUserDefaults() -> (languageIdxArray: [Int]?, textArray: [String]?) {
        let defaults = UserDefaults.standard
        
        // Retrieve language index array
        let languageIdxArray = defaults.array(forKey: "language") as? [Int]
        
        // Retrieve text array
        let textArray = defaults.array(forKey: "quote") as? [String]
        
        return (languageIdxArray, textArray)
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
    
}
extension UIView {
    func screenshot() -> UIImage? {
        // Begin the graphics context
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
        
        // Render the view hierarchy to the current context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        layer.render(in: context)
        
        // Get the image from the current context
        let screenshot = UIGraphicsGetImageFromCurrentImageContext()
        
        // End the graphics context
        UIGraphicsEndImageContext()
        
        return screenshot
    }
}


class CustomCanvasView: PKCanvasView {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            let location = touch.location(in: self)
            print("Touch began at: \(location)")
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let touch = touches.first {
            let location = touch.location(in: self)
            print("Touch moved to: \(location)")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let touch = touches.first {
            let location = touch.location(in: self)
            print("Touch ended at: \(location)")
            NotificationCenter.default.post(name: Notification.Name("notification"), object: nil)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if let touch = touches.first {
            let location = touch.location(in: self)
            print("Touch cancelled at: \(location)")
        }
    }
    
    func shrinkStrokes(by factor: CGFloat) {
        guard factor > 0 else { return }

        var newStrokes = [PKStroke]()

        for stroke in self.drawing.strokes {
            let originalLength = stroke.path.length()
            let newPath = stroke.path.resampled(to: originalLength / factor)
            let newStroke = PKStroke(ink: stroke.ink, path: newPath, transform: stroke.transform, mask: stroke.mask)
            newStrokes.append(newStroke)
        }

        // Set the new drawing with shrunken strokes
        self.drawing = PKDrawing(strokes: newStrokes)
    }
    
    func addStroke(at points: [CGPoint], with color: UIColor = .black, width: CGFloat = 5.0) {
            let newStroke = createStroke(at: points, with: color, width: width)
            var currentDrawing = self.drawing
            currentDrawing.strokes.append(newStroke)
            self.drawing = currentDrawing
    }
    
    func createStroke(at points: [CGPoint], with color: UIColor = .black, width: CGFloat = 5.0) -> PKStroke {
        let ink = PKInk(.pen, color: color)
        var controlPoints = [PKStrokePoint]()

        for point in points {
            let strokePoint = PKStrokePoint(location: point, timeOffset: 0, size: CGSize(width: width, height: width), opacity: 1.0, force: 1.0, azimuth: 0, altitude: 0)
            controlPoints.append(strokePoint)
        }

        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path, transform: .identity, mask: nil)

        return stroke
    }
    
}

class PDFImageAnnotation: PDFAnnotation {

    var image: UIImage?

    convenience init(_ image: UIImage?, bounds: CGRect, properties: [AnyHashable: Any]?) {
        self.init(bounds: bounds, forType: .ink, withProperties: properties)
        self.image = image
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        super.draw(with: box, in: context)

        // Drawing the image within the annotation's bounds.
        guard let cgImage = image?.cgImage else { return }
        context.draw(cgImage, in: bounds)
    }
}

extension PKStrokePath {
    func length() -> CGFloat {
        guard self.count > 1 else { return 0 }

        var totalLength: CGFloat = 0.0
        var previousPoint = self[0].location

        for i in 1..<self.count {
            let currentPoint = self[i].location
            let distance = hypot(currentPoint.x - previousPoint.x, currentPoint.y - previousPoint.y)
            totalLength += distance
            previousPoint = currentPoint
        }

        return totalLength
    }
    
    func resampled(to targetLength: CGFloat) -> PKStrokePath {
        let originalLength = self.length()
        guard originalLength > 0 else { return self }
        
        let scale = targetLength / originalLength
        var newPoints = [PKStrokePoint]()
        
        for i in 0..<self.count {
            let point = self[i]
            let newLocation = CGPoint(x: point.location.x * scale, y: point.location.y * scale)
            let newPoint = PKStrokePoint(location: newLocation, timeOffset: point.timeOffset, size: point.size, opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude)
            newPoints.append(newPoint)
        }
        
        return PKStrokePath(controlPoints: newPoints, creationDate: Date())
    }
}
