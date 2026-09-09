//
//  SceneDelegate.swift
//  pdfsignature
//
//  Created by yano on 2024/09/18.
//

import UIKit
import PDFKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }

        // Cold launch: another app opened a PDF with us.
        if let context = connectionOptions.urlContexts.first {
            // Just stash the URL. The root ViewController checks
            // DocumentManager.shared.documentURL in viewDidAppear and routes to the editor.
            loadPDF(from: context.url, presentEditor: false)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Warm launch: app was already running when another app opened a PDF with us.
        guard let context = URLContexts.first else { return }
        loadPDF(from: context.url, presentEditor: true)
    }

    /// Copies the incoming PDF into the app's Documents directory, renders the first
    /// page, and stores both in DocumentManager (mirroring iCloudController's flow).
    private func loadPDF(from incomingURL: URL, presentEditor: Bool) {
        let needsSecurityScope = incomingURL.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { incomingURL.stopAccessingSecurityScopedResource() } }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = documents.appendingPathComponent(incomingURL.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: incomingURL, to: destURL)
        } catch {
            print("Failed to copy incoming PDF: \(error)")
            return
        }

        DocumentManager.shared.documentURL = destURL
        if let firstImage = renderFirstPage(of: destURL) {
            DocumentManager.shared.document = firstImage
        }

        guard presentEditor else { return }

        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.rootViewController,
                  let editor = root.storyboard?.instantiateViewController(withIdentifier: "pencil") as? PencilController else { return }
            editor.modalPresentationStyle = .fullScreen
            let presenter = root.presentedViewController ?? root
            presenter.present(editor, animated: true, completion: nil)
        }
    }

    private func renderFirstPage(of pdfURL: URL) -> UIImage? {
        guard let pdfDocument = PDFDocument(url: pdfURL),
              let page = pdfDocument.page(at: 0) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}
