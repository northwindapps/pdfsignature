//
//  ViewController.swift
//  pdfsignature
//
//  Created by yano on 2024/09/18.
//

import UIKit

class ViewController: UIViewController {

    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupActivityIndicator()
        activityIndicator.startAnimating()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if DocumentManager.shared.documentURL == nil {
            if let target = storyboard?.instantiateViewController(withIdentifier: "icloud") as? iCloudController {
                activityIndicator.stopAnimating()
                activityIndicator.isHidden = true
                target.modalPresentationStyle = .fullScreen
                present(target, animated: true, completion: nil)
            }
        }
    
        if let pdfURL = DocumentManager.shared.documentURL {
            if let target = storyboard?.instantiateViewController(withIdentifier: "pencil") as? PencilController {
                activityIndicator.stopAnimating()
                activityIndicator.isHidden = true
                target.modalPresentationStyle = .fullScreen
                present(target, animated: true, completion: nil)
            }
            
        }
        
        
    }
    
    private func setupActivityIndicator() {
        // Set the center and color of the activity indicator
        activityIndicator.center = view.center
        activityIndicator.color = .gray
        
        // Add it to the view hierarchy
        view.addSubview(activityIndicator)
    }


}

