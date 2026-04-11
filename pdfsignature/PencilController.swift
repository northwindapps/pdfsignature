import UIKit
import PDFKit
import Vision
import PencilKit
import MessageUI

class PencilController: UIViewController, UIImagePickerControllerDelegate,PKCanvasViewDelegate,PKToolPickerObserver , UIGestureRecognizerDelegate, UITextViewDelegate,MFMailComposeViewControllerDelegate, UINavigationControllerDelegate{

    var canvasView = CustomCanvasView()
    var stickerContainerView: UIView!
    var toolPicker: PKToolPicker!
    var scrollView: UIScrollView!
    var timer: Timer?
    var id = ""
    var imageView = UIImageView()
    var overlayImageView = UIImageView()
    var strokeHistoryView = UIImageView()
    var saveButton = UIButton()
    var pageBtn = UIButton()
    var inputMode = false
    var activityIndicator = UIActivityIndicatorView(style: .medium)
    
    
    private var pdfPageImages: [UIImage] = []
    private var pageDrawings: [PKDrawing] = []
    private var pageStrokeOverlays: [UIImage?] = []
    
    /// Use center + bounds size + transform. `frame` is undefined when `transform != .identity`, which caused wrong sizes after save/reload.
    private struct StickerSnapshot {
        let image: UIImage
        let center: CGPoint
        let boundsSize: CGSize
        let transform: CGAffineTransform
    }
    private var pageStickers: [[StickerSnapshot]] = []
    private var currentPageIndex: Int = 0
    
    private let bottomBarHeight: CGFloat = 64
    private var bottomBar: UIView!
    private var pageNumberScrollView: UIScrollView!
    private var pageNumberStackView: UIStackView!
    private var pageButtons: [UIButton] = []
    private var prevPageButton: UIButton!
    private var nextPageButton: UIButton!
    private var pageStatusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupActivityIndicator()
        activityIndicator.startAnimating()
        let topMargin: CGFloat = 60

        // Create UIScrollView with margin
        scrollView = UIScrollView(frame: CGRect(x: 0, y: topMargin, width: view.bounds.width, height: view.bounds.height - topMargin - bottomBarHeight))
        scrollView.contentSize = CGSize(width: view.bounds.width * 2, height: view.bounds.height * 2)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        
        // Load PDF pages (multi-page) or fallback to single image.
        if let pdfURL = DocumentManager.shared.documentURL, let images = convertPDFToPNG(pdfURL: pdfURL), !images.isEmpty {
            pdfPageImages = images
        } else if let singleImage = DocumentManager.shared.document {
            pdfPageImages = [singleImage]
        }
        
        if pdfPageImages.isEmpty {
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            return
        }
        
        pageDrawings = Array(repeating: PKDrawing(), count: pdfPageImages.count)
        pageStrokeOverlays = Array(repeating: nil, count: pdfPageImages.count)
        pageStickers = Array(repeating: [], count: pdfPageImages.count)
        currentPageIndex = 0
        
        // Create ImageView (base PDF page)
        imageView = UIImageView(frame: scrollView.bounds)
        imageView.image = pdfPageImages[currentPageIndex]
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        imageView.contentMode = .scaleAspectFit
        
        // Overlay view for committed strokes (saved marks)
        overlayImageView = UIImageView(frame: scrollView.bounds)
        overlayImageView.backgroundColor = .clear
        overlayImageView.isOpaque = false
        overlayImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayImageView.contentMode = .scaleAspectFit
        scrollView.addSubview(overlayImageView)
        
        // Scratch view used only to accumulate overlay screenshots
        strokeHistoryView = UIImageView(frame: scrollView.bounds)
        strokeHistoryView.backgroundColor = .clear
        strokeHistoryView.isOpaque = false
        strokeHistoryView.image = nil

        // Create PKCanvasView
        canvasView = CustomCanvasView(frame: scrollView.bounds)
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

      

        setupPageSelectorBar()
        updatePageUI(animated: false)
        
        // Create a horizontal stack for all top buttons
        let topButtonStack = UIStackView()
        topButtonStack.axis = .horizontal
        topButtonStack.spacing = 12
        topButtonStack.alignment = .center
        topButtonStack.distribution = .equalSpacing
        view.addSubview(topButtonStack)
        topButtonStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topButtonStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            topButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])

        // Create buttons
        let penModeButton = UIButton(type: .system)
        penModeButton.setTitle("Pen", for: .normal)
        penModeButton.addTarget(self, action: #selector(switchToPenModeButtonTapped), for: .touchUpInside)

        let adjustButton = UIButton(type: .system)
        adjustButton.setTitle("Adjust", for: .normal)
        adjustButton.addTarget(self, action: #selector(scaleDown), for: .touchUpInside)

        saveButton = UIButton(type: .system)
        saveButton.setTitle("Save", for: .normal)
        saveButton.setTitleColor(.red, for: .normal)
        saveButton.addTarget(self, action: #selector(saveStroke), for: .touchUpInside)
        saveButton.isHidden = true

        let exportButton = UIButton(type: .system)
        exportButton.setTitle("Export", for: .normal)
        exportButton.addTarget(self, action: #selector(exportPDF), for: .touchUpInside)

        let importButton = UIButton(type: .system)
        importButton.setTitle("Import", for: .normal)
        importButton.addTarget(self, action: #selector(importPDF), for: .touchUpInside)

        pageBtn = UIButton(type: .system)
        pageBtn.setTitle("Pages", for: .normal)
        pageBtn.addTarget(self, action: #selector(goToNextPage), for: .touchUpInside)

        let imageButton = UIButton(type: .system)
        imageButton.setTitle("Images", for: .normal)
        imageButton.addTarget(self, action: #selector(openImagePicker), for: .touchUpInside)

        // Add all buttons to the stack
        [topButtonStack.addArrangedSubview(penModeButton),
         topButtonStack.addArrangedSubview(adjustButton),
         topButtonStack.addArrangedSubview(saveButton),
         topButtonStack.addArrangedSubview(exportButton),
         topButtonStack.addArrangedSubview(importButton),
         topButtonStack.addArrangedSubview(pageBtn),
         topButtonStack.addArrangedSubview(imageButton)]
        

        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotification), name: Notification.Name("notification"), object: nil)
        
        //
        stickerContainerView = UIView(frame: scrollView.bounds)
        stickerContainerView.backgroundColor = .clear
        stickerContainerView.isUserInteractionEnabled = true
        stickerContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        scrollView.addSubview(stickerContainerView)
        loadStickers(for: currentPageIndex)
        
//        canvasView.layer.borderWidth = 0.5
//        canvasView.layer.borderColor = UIColor.black.cgColor
//        
//        overlayImageView.layer.borderWidth = 0.5
//        overlayImageView.layer.borderColor = UIColor.black.cgColor
        
        self.view.backgroundColor = .lightGray
        switchToPenMode()
        
        
    }
    
    @objc func switchToPenModeButtonTapped() {
        switchToPenMode()
    }
    
    private func setupActivityIndicator() {
        // Set the center and color of the activity indicator
        activityIndicator.center = view.center
        activityIndicator.color = .gray
        
        // Add it to the view hierarchy
        view.addSubview(activityIndicator)
    }
    
    @objc func openImagePicker() {
        // Switch to image mode first
        switchToImageMode()
            
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage else { return }

        addSticker(image: image)
    }
    
    func addSticker(image: UIImage) {
        let sticker = UIImageView(image: image)
        
        sticker.frame = CGRect(x: 100, y: 100, width: 150, height: 150)
        sticker.isUserInteractionEnabled = true
        sticker.contentMode = .scaleAspectFit
        
        // Gestures
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        
        sticker.addGestureRecognizer(pan)
        sticker.addGestureRecognizer(pinch)
        sticker.addGestureRecognizer(rotation)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleStickerDoubleTapToDelete(_:)))
        doubleTap.numberOfTapsRequired = 2

        sticker.addGestureRecognizer(doubleTap)
        
        stickerContainerView.addSubview(sticker)
        snapshotCurrentStickers()
    }
    
    @objc func handleStickerDoubleTapToDelete(_ gesture: UITapGestureRecognizer) {
        guard let sticker = gesture.view else { return }
        
        // Optional: add a confirmation alert
        let alert = UIAlertController(
            title: "Delete Sticker?",
            message: "Do you want to remove this sticker?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            sticker.removeFromSuperview()
        }))
        
        present(alert, animated: true)
    }
    
    func switchToPenMode() {
        // Enable drawing
        canvasView.isUserInteractionEnabled = true
        canvasView.becomeFirstResponder()
        
        // Disable sticker movement (optional but recommended)
        stickerContainerView.isUserInteractionEnabled = false
        
        // Set pen tool
        let penTool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.tool = penTool
        
        showToast("Pen mode enabled ✏️")
    }
    
    func switchToImageMode() {
        scrollView.isScrollEnabled = true
//        inputBtn.setTitle("Mode: Image", for: .normal)
        canvasView.isUserInteractionEnabled = false
        
        stickerContainerView.isUserInteractionEnabled = true
        showToast("Image mode enabled 🖼️")
    }
    
    func showToast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textColor = .white
        label.textAlignment = .center
        label.alpha = 0
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 250)
        ])
        
        UIView.animate(withDuration: 0.3) {
            label.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.5) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let translation = gesture.translation(in: stickerContainerView)
        
        view.center = CGPoint(
            x: view.center.x + translation.x,
            y: view.center.y + translation.y
        )
        
        gesture.setTranslation(.zero, in: stickerContainerView)
    }
    
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let view = gesture.view else { return }
        
        view.transform = view.transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1
    }
    
    @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard let view = gesture.view else { return }
        
        view.transform = view.transform.rotated(by: gesture.rotation)
        gesture.rotation = 0
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
        restackScrollSubviewsForHitTesting()
        activityIndicator.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(self)
        //configureCanvas()
        canvasView.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        restackScrollSubviewsForHitTesting()
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
        restackScrollSubviewsForHitTesting()
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
        canvasView.shrinkDrawingCompletely(by: 1.3)
    }
    

    
    
    /// Merges live canvas ink into `pageStrokeOverlays` for the current page. Returns `false` if there was nothing to commit or capture failed.
    @discardableResult
    private func commitCurrentPageStrokesIfNeeded() -> Bool {
        guard !canvasView.drawing.strokes.isEmpty else { return false }
        
        let penTool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.tool = penTool
        
        guard let overlay = takeScreenshotCorrect(forPageIndex: currentPageIndex) else { return false }
        
        pageStrokeOverlays[currentPageIndex] = overlay
        overlayImageView.image = overlay
        pageDrawings[currentPageIndex] = PKDrawing()
        canvasView.drawing = PKDrawing()
        saveButton.isHidden = true
        return true
    }
    
    @objc func saveStroke() {
        if canvasView.drawing.strokes.isEmpty {
            saveButton.isHidden = true
            return
        }
        _ = commitCurrentPageStrokesIfNeeded()
    }
    
    @objc func exportPDF() {
        let penTool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.tool = penTool
        
        // If there are uncommitted strokes on the current page, commit them before exporting.
        if !canvasView.drawing.strokes.isEmpty {
            _ = commitCurrentPageStrokesIfNeeded()
        }
        
        // Persist current sticker positions before exporting.
        snapshotCurrentStickers()
        
        if let pdfData = saveStrokeToPDF() {
            pdfEmail(data: pdfData)
        }
        
        canvasView.drawing = PKDrawing()
        saveButton.isHidden = true
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
        let imageToExport = renderPageForExport()
        
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: imageToExport.size))
        
        let data = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            imageToExport.draw(at: .zero)
        }
        
        do{
            try data.write(to: pdfPath!)
            print("PDF saved to: \(pdfPath!)")
        }catch{
            print("Failed to save PDF: \(error)")
        }
    }

    
//    @objc func switchInput() {
//        scrollView.isScrollEnabled = !scrollView.isScrollEnabled
//        if scrollView.isScrollEnabled{
//            inputBtn.setTitle("Mode:s", for: .normal)
//        }
//        
//        if !scrollView.isScrollEnabled{
//            inputBtn.setTitle("Mode:w", for: .normal)
//        }
//    }
    
    func renderPageForExport() -> UIImage {
        let pageSize = pdfPageImages[currentPageIndex].size

        UIGraphicsBeginImageContextWithOptions(pageSize, false, 0)
        defer { UIGraphicsEndImageContext() }

        // Draw base PDF page
        pdfPageImages[currentPageIndex].draw(in: CGRect(origin: .zero, size: pageSize))
        
        // Draw pen strokes
        let drawingImage = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
        drawingImage.draw(in: CGRect(origin: .zero, size: pageSize))

        // Draw all sticker images
        for sticker in stickerContainerView.subviews where sticker is UIImageView {
            guard let imageView = sticker as? UIImageView else { continue }
            imageView.image?.draw(in: imageView.frame)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? pdfPageImages[currentPageIndex]
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
        // If we have an original PDF, add overlay annotations to it.
        if let pdfURL = DocumentManager.shared.documentURL, let pdfDocument = PDFDocument(url: pdfURL) {
            // Add an overlay annotation per page (strokes + stickers).
            let pageCount = min(pdfDocument.pageCount, pageStrokeOverlays.count, pageStickers.count)
            for pageIndex in 0..<pageCount {
                guard let pdfPage = pdfDocument.page(at: pageIndex) else { continue }
                
                let pdfPageBounds = pdfPage.bounds(for: .mediaBox)
                
                // Build a transparent overlay image for this page.
                guard let composedOverlay = renderStickersOverlay(
                    for: pageIndex,
                    targetSize: pdfPageBounds.size
                ) else { continue }
                
                let imageBounds = CGRect(x: 0, y: 0, width: pdfPageBounds.width, height: pdfPageBounds.height)
                let annotation = PDFImageAnnotation(composedOverlay, bounds: imageBounds, properties: nil)
                pdfPage.addAnnotation(annotation)
            }
            
            return pdfDocument.dataRepresentation()
        }
        
        // Otherwise, generate a new PDF from the rendered pages (base + overlays).
        guard !pdfPageImages.isEmpty else { return nil }
        
        let output = NSMutableData()
        let firstSize = pdfPageImages[0].size
        UIGraphicsBeginPDFContextToData(output, CGRect(origin: .zero, size: firstSize), nil)
        for i in 0..<pdfPageImages.count {
            let base = pdfPageImages[i]
            let size = base.size
            UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
            
            // Draw base
            base.draw(in: CGRect(origin: .zero, size: size))
            
            // Draw stickers (no base)
            if let stickerOnly = renderStickersOverlay(for: i, targetSize: size, includeStrokes: false) {
                stickerOnly.draw(in: CGRect(origin: .zero, size: size))
            }
            
            // Draw committed strokes on top (aspect-fit if bitmap size ≠ page image size)
            if let overlay = pageStrokeOverlays[i] {
                let r = rectAspectFit(imageSize: overlay.size, in: CGRect(origin: .zero, size: size))
                overlay.draw(in: r)
            }
        }
        UIGraphicsEndPDFContext()
        return output as Data
    }
    
    func aspectFitFrame(for image: UIImage, in imageView: UIImageView) -> CGRect {
        let imageSize = image.size
        let viewSize = imageView.bounds.size
        
        let scale = min(viewSize.width / imageSize.width,
                        viewSize.height / imageSize.height)
        
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        
        let x = (viewSize.width - width) / 2
        let y = (viewSize.height - height) / 2
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    /// Rect that fits `imageSize` inside `container` without stretching (like `UIView.ContentMode.scaleAspectFit`).
    private func rectAspectFit(imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: container.midX - fitted.width / 2,
            y: container.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
    
    /// Renders a transparent image containing stickers (and optionally strokes) aligned to the PDF page.
    func renderStickersOverlay(for pageIndex: Int, targetSize: CGSize, includeStrokes: Bool = true) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        // Draw strokes overlay if requested (aspect-fit so PDF page size ≠ bitmap size won’t stretch ink)
        if includeStrokes, let overlay = pageStrokeOverlays.indices.contains(pageIndex) ? pageStrokeOverlays[pageIndex] : nil {
            let r = rectAspectFit(imageSize: overlay.size, in: CGRect(origin: .zero, size: targetSize))
            overlay.draw(in: r)
        }
        
        guard pdfPageImages.indices.contains(pageIndex) else {
            return UIGraphicsGetImageFromCurrentImageContext()
        }
        
        // Map from on-screen coordinates (stickerContainerView) to image coordinates using aspect-fit frame.
        let baseImage = pdfPageImages[pageIndex]
        let imageFrame = aspectFitFrame(for: baseImage, in: imageView)
        
        let scaleX = targetSize.width / imageFrame.width
        let scaleY = targetSize.height / imageFrame.height
        
        let stickers = pageStickers.indices.contains(pageIndex) ? pageStickers[pageIndex] : []
        for sticker in stickers {
            let rectInContainer = CGRect(
                x: sticker.center.x - sticker.boundsSize.width / 2,
                y: sticker.center.y - sticker.boundsSize.height / 2,
                width: sticker.boundsSize.width,
                height: sticker.boundsSize.height
            )
            
            // Convert bounds into imageFrame-relative coordinates
            let rectInImageFrame = CGRect(
                x: rectInContainer.origin.x - imageFrame.origin.x,
                y: rectInContainer.origin.y - imageFrame.origin.y,
                width: rectInContainer.size.width,
                height: rectInContainer.size.height
            )
            
            // Scale into target (PDF) coordinate space
            let rect = CGRect(
                x: rectInImageFrame.origin.x * scaleX,
                y: rectInImageFrame.origin.y * scaleY,
                width: rectInImageFrame.size.width * scaleX,
                height: rectInImageFrame.size.height * scaleY
            )
            
            // Apply view transform (scale/rotation) around sticker center; draw image aspect-fit in rect (matches UIImageView)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard let ctx = UIGraphicsGetCurrentContext() else { continue }
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.concatenate(sticker.transform)
            ctx.translateBy(x: -center.x, y: -center.y)
            let fitted = rectAspectFit(imageSize: sticker.image.size, in: rect)
            sticker.image.draw(in: fitted)
            ctx.restoreGState()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private func snapshotCurrentStickers() {
        guard pageStickers.indices.contains(currentPageIndex) else { return }
        let snapshots: [StickerSnapshot] = stickerContainerView.subviews.compactMap { view in
            guard let iv = view as? UIImageView, let img = iv.image else { return nil }
            return StickerSnapshot(image: img, center: iv.center, boundsSize: iv.bounds.size, transform: iv.transform)
        }
        pageStickers[currentPageIndex] = snapshots
    }
    
    private func loadStickers(for pageIndex: Int) {
        guard stickerContainerView != nil else { return }
        stickerContainerView.subviews.forEach { $0.removeFromSuperview() }
        guard pageStickers.indices.contains(pageIndex) else { return }
        
        for snapshot in pageStickers[pageIndex] {
            let sticker = UIImageView(image: snapshot.image)
            sticker.bounds = CGRect(origin: .zero, size: snapshot.boundsSize)
            sticker.center = snapshot.center
            sticker.transform = snapshot.transform
            sticker.isUserInteractionEnabled = true
            sticker.contentMode = .scaleAspectFit
            
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            sticker.addGestureRecognizer(pan)
            sticker.addGestureRecognizer(pinch)
            sticker.addGestureRecognizer(rotation)
            
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleStickerDoubleTapToDelete(_:)))
            doubleTap.numberOfTapsRequired = 2
            sticker.addGestureRecognizer(doubleTap)
            
            stickerContainerView.addSubview(sticker)
        }
    }
    
    /// Builds a transparent bitmap of committed ink in page space (same size as the page raster).
    /// Uses `pdfPageImages[pageIndex]` (not `imageView.image`) so commits never composite against the wrong page after a fast page change.
    func takeScreenshotCorrect(forPageIndex pageIndex: Int) -> UIImage? {
        guard pdfPageImages.indices.contains(pageIndex) else { return nil }
        let baseImage = pdfPageImages[pageIndex]
        
        let imageFrame = aspectFitFrame(for: baseImage, in: imageView)
        guard imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = baseImage.scale
        let renderer = UIGraphicsImageRenderer(size: baseImage.size, format: format)
        
        return renderer.image { ctx in
            let dest = CGRect(origin: .zero, size: baseImage.size)
            ctx.cgContext.clear(dest)
            
            // 1. Prior committed strokes for this page only (same pixel size as this page raster).
            if let previous = pageStrokeOverlays[pageIndex],
               previous.size.width > 0, previous.size.height > 0,
               abs(previous.size.width - baseImage.size.width) < 0.5,
               abs(previous.size.height - baseImage.size.height) < 0.5 {
                previous.draw(in: dest, blendMode: .normal, alpha: 1)
            }
            
            // 2. New ink from canvas, aligned to the aspect-fit page rect (only valid while this page is on-screen).
            let scaleX = baseImage.size.width / imageFrame.width
            let scaleY = baseImage.size.height / imageFrame.height
            
            ctx.cgContext.translateBy(x: -imageFrame.origin.x * scaleX,
                                      y: -imageFrame.origin.y * scaleY)
            ctx.cgContext.scaleBy(x: scaleX, y: scaleY)
            canvasView.layer.render(in: ctx.cgContext)
        }
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

        // Keep the scroll area above the bottom bar.
        let topMargin: CGFloat = 60
        scrollView.frame = CGRect(
            x: 0,
            y: topMargin,
            width: view.bounds.width,
            height: view.bounds.height - topMargin - bottomBarHeight - view.safeAreaInsets.bottom
        )
        scrollView.contentSize = scrollView.bounds.size
        
        if canvasView != nil {
            imageView.frame = scrollView.bounds
            overlayImageView.frame = scrollView.bounds
            canvasView.frame = scrollView.bounds
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
    
    // MARK: - Page selector bar (multi-page)
    private func setupPageSelectorBar() {
        bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.95)
        view.addSubview(bottomBar)
        
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: bottomBarHeight)
        ])
        
        prevPageButton = UIButton(type: .system)
        prevPageButton.setTitle("◀︎", for: .normal)
        prevPageButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        prevPageButton.addTarget(self, action: #selector(goToPreviousPage), for: .touchUpInside)
        prevPageButton.translatesAutoresizingMaskIntoConstraints = false
        
        nextPageButton = UIButton(type: .system)
        nextPageButton.setTitle("▶︎", for: .normal)
        nextPageButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        nextPageButton.addTarget(self, action: #selector(goToNextPage), for: .touchUpInside)
        nextPageButton.translatesAutoresizingMaskIntoConstraints = false
        
        pageStatusLabel = UILabel()
        pageStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        pageStatusLabel.textColor = .secondaryLabel
        pageStatusLabel.textAlignment = .center
        pageStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        pageNumberScrollView = UIScrollView()
        pageNumberScrollView.showsHorizontalScrollIndicator = false
        pageNumberScrollView.translatesAutoresizingMaskIntoConstraints = false
        
        pageNumberStackView = UIStackView()
        pageNumberStackView.axis = .horizontal
        pageNumberStackView.spacing = 8
        pageNumberStackView.alignment = .center
        pageNumberStackView.translatesAutoresizingMaskIntoConstraints = false
        pageNumberScrollView.addSubview(pageNumberStackView)
        
        bottomBar.addSubview(prevPageButton)
        bottomBar.addSubview(nextPageButton)
        bottomBar.addSubview(pageNumberScrollView)
        bottomBar.addSubview(pageStatusLabel)
        
        NSLayoutConstraint.activate([
            prevPageButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            prevPageButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            prevPageButton.widthAnchor.constraint(equalToConstant: 44),
            prevPageButton.heightAnchor.constraint(equalToConstant: 44),
            
            nextPageButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            nextPageButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            nextPageButton.widthAnchor.constraint(equalToConstant: 44),
            nextPageButton.heightAnchor.constraint(equalToConstant: 44),
            
            pageStatusLabel.leadingAnchor.constraint(equalTo: prevPageButton.trailingAnchor, constant: 8),
            pageStatusLabel.trailingAnchor.constraint(equalTo: nextPageButton.leadingAnchor, constant: -8),
            pageStatusLabel.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 6),
            pageStatusLabel.heightAnchor.constraint(equalToConstant: 16),
            
            pageNumberScrollView.leadingAnchor.constraint(equalTo: prevPageButton.trailingAnchor, constant: 8),
            pageNumberScrollView.trailingAnchor.constraint(equalTo: nextPageButton.leadingAnchor, constant: -8),
            pageNumberScrollView.topAnchor.constraint(equalTo: pageStatusLabel.bottomAnchor, constant: 6),
            pageNumberScrollView.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -6),
            
            pageNumberStackView.leadingAnchor.constraint(equalTo: pageNumberScrollView.contentLayoutGuide.leadingAnchor),
            pageNumberStackView.trailingAnchor.constraint(equalTo: pageNumberScrollView.contentLayoutGuide.trailingAnchor),
            pageNumberStackView.topAnchor.constraint(equalTo: pageNumberScrollView.contentLayoutGuide.topAnchor),
            pageNumberStackView.bottomAnchor.constraint(equalTo: pageNumberScrollView.contentLayoutGuide.bottomAnchor),
            pageNumberStackView.heightAnchor.constraint(equalTo: pageNumberScrollView.frameLayoutGuide.heightAnchor)
        ])
        
        rebuildPageButtons()
    }
    
    private func rebuildPageButtons() {
        pageButtons.forEach { $0.removeFromSuperview() }
        pageButtons.removeAll()
        
        guard !pdfPageImages.isEmpty else { return }
        for i in 0..<pdfPageImages.count {
            let button = UIButton(type: .system)
            button.setTitle("\(i + 1)", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            button.layer.cornerRadius = 10
            button.layer.borderWidth = 1
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            button.tag = i
            button.addTarget(self, action: #selector(selectPageFromButton(_:)), for: .touchUpInside)
            pageNumberStackView.addArrangedSubview(button)
            pageButtons.append(button)
        }
    }
    
    @objc private func selectPageFromButton(_ sender: UIButton) {
        goToPage(sender.tag, animated: true)
    }
    
    @objc private func goToPreviousPage() {
        goToPage(max(0, currentPageIndex - 1), animated: true)
    }
    
//    @objc private func goToNextPage() {
//        goToPage(min(pdfPageImages.count - 1, currentPageIndex + 1), animated: true)
//    }
    
    @objc private func goToNextPage() {
        guard !pdfPageImages.isEmpty else { return }
        
        let nextIndex: Int
        if currentPageIndex >= pdfPageImages.count - 1 {
            nextIndex = 0   // 🔁 loop back to first page
        } else {
            nextIndex = currentPageIndex + 1
        }
        
        goToPage(nextIndex, animated: true)
    }
    
    private func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pdfPageImages.count else { return }
        guard index != currentPageIndex else { return }
        
        snapshotCurrentStickers()
        
        pageDrawings[currentPageIndex] = PKDrawing()
        
        currentPageIndex = index
        updatePageUI(animated: animated)
    }
    
    
    
    /// Clears live editing views so the previous page’s ink/stickers never flash on the next page.
    private func resetLivePageLayers() {
        canvasView.drawing = PKDrawing()
        overlayImageView.image = nil
        stickerContainerView?.subviews.forEach { $0.removeFromSuperview() }
    }

    private func restackScrollSubviewsForHitTesting() {
        let views = [imageView, overlayImageView, canvasView, stickerContainerView].compactMap { $0 }
        views.forEach { view in
            if view.superview == scrollView {
                scrollView.bringSubviewToFront(view)
            }
        }
    }

    
    private func updatePageUI(animated: Bool) {
        guard !pdfPageImages.isEmpty else { return }
        
        resetLivePageLayers()
        
        imageView.image = pdfPageImages[currentPageIndex]
        overlayImageView.image = pageStrokeOverlays[currentPageIndex] ?? nil
        canvasView.drawing = pageDrawings[currentPageIndex]
        canvasView.layoutIfNeeded()
        loadStickers(for: currentPageIndex)
        restackScrollSubviewsForHitTesting()
        saveButton.isHidden = true
        
        let current = currentPageIndex + 1
        pageStatusLabel.text = "Page \(current) / \(pdfPageImages.count)"
        
        prevPageButton.isEnabled = currentPageIndex > 0
        nextPageButton.isEnabled = currentPageIndex < pdfPageImages.count - 1
        
        for (i, button) in pageButtons.enumerated() {
            let isSelected = i == currentPageIndex
            button.layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.tertiaryLabel).cgColor
            button.setTitleColor(isSelected ? .white : .label, for: .normal)
            button.backgroundColor = isSelected ? .systemBlue : .clear
        }
        
        // Ensure the selected page button is visible.
        if currentPageIndex < pageButtons.count {
            let selectedButton = pageButtons[currentPageIndex]
            let targetRect = selectedButton.convert(selectedButton.bounds, to: pageNumberScrollView)
            pageNumberScrollView.scrollRectToVisible(targetRect.insetBy(dx: -20, dy: 0), animated: animated)
        }
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
    
    func shrinkDrawingInPlace(by factor: CGFloat) {
        let drawing = self.drawing
        guard !drawing.strokes.isEmpty, factor > 0 else { return }

        let scale = 1.0 / factor
        let bounds = drawing.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // 1. 中心を基準にするための変形（移動 -> 縮小 -> 戻す）
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        // 2. 座標と長さを変形
        let transformedDrawing = drawing.transformed(using: transform)

        // 3. 線の「太さ」も個別に調整（ここをしないと線だけ太いままになる）
        let newStrokes = transformedDrawing.strokes.map { stroke -> PKStroke in
            let newPoints = stroke.path.map { point -> PKStrokePoint in
                let newSize = CGSize(width: point.size.width * scale,
                                    height: point.size.height * scale)
                return PKStrokePoint(location: point.location, timeOffset: point.timeOffset,
                                     size: newSize, opacity: point.opacity, force: point.force,
                                     azimuth: point.azimuth, altitude: point.altitude)
            }
            let newPath = PKStrokePath(controlPoints: newPoints, creationDate: stroke.path.creationDate)
            return PKStroke(ink: stroke.ink, path: newPath, transform: .identity, mask: stroke.mask)
        }

        self.drawing = PKDrawing(strokes: newStrokes)
    }

    
    func shrinkDrawingCompletely(by factor: CGFloat) {
        let drawing = self.drawing
        guard !drawing.strokes.isEmpty, factor > 0 else { return }

        let scale = 1.0 / factor
        let bounds = drawing.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        //Keep drawing in the center
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        let transformedDrawing = drawing.transformed(using: transform)

        self.drawing = transformedDrawing
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
