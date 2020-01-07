//
//  ViewController.swift
//  Location Restore
//
//  Created by Andre Yonadam on 12/24/19.
//  Copyright © 2019 Andre Yonadam. All rights reserved.
//

import Cocoa
import Photos

class ViewController: NSViewController {

    // MARK: - Outlets
    
    @IBOutlet weak var openButton: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var updateTextField: NSTextField!
    
    // MARK: - Constants
    
    let ButtonNotRunningStateTitle = "Start"
    let ButtonRunningStateTitle = "Stop"

    // MARK: - Properties
    
    var mediaMigrator: MediaMigrator?
    var isRunning = false
    var errors = [String]()
    
    // MARK: - Init
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @IBAction func openButtonClicked(_ sender: Any) {
        if isRunning {
            mediaMigrator?.shouldContinueToRun = false
        } else {
            let status = PHPhotoLibrary.authorizationStatus()
            switch status {
            case .authorized:
                openDialogPanel()
            case .denied, .restricted :
                showPermissionUnauthorizedAlert()
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    switch status {
                    case .authorized:
                        self.openDialogPanel()
                    case .denied, .restricted:
                        self.showPermissionUnauthorizedAlert()
                    case .notDetermined:
                        self.showPermissionUnauthorizedAlert()
                    @unknown default:
                        self.showPermissionUnauthorizedAlert()
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    private func openDialogPanel() {
        DispatchQueue.main.async {
            let dialog = NSOpenPanel()
            
            dialog.title = "Choose a folder"
            dialog.showsResizeIndicator = true
            dialog.canChooseDirectories = true
            dialog.allowsMultipleSelection = false
            dialog.canChooseFiles = false

            if (dialog.runModal() == NSApplication.ModalResponse.OK) {
                let result = dialog.url
                
                guard let url = result else {
                    return
                }
                
                self.mediaMigrator = MediaMigrator(folderPath: url, progressObserver: self)
                self.mediaMigrator?.start()
            }
        }
    }
    
    private func showPermissionUnauthorizedAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permissions not allowed"
            alert.informativeText = "This application requires permissions to Photos in order to be able to import photos and videos."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func dialog(question: String, text: String) {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let alertViewController = segue.destinationController as? AlertViewController {
            alertViewController.logMessage = errors
        }
    }
}

// MARK: - ProgressObserverProtocol

extension ViewController: ProgressObserverProtocol {
   
    func started() {
        DispatchQueue.main.async {
            self.isRunning = true
            self.openButton.title = self.ButtonRunningStateTitle
            self.progressBar.isHidden = false
            self.updateTextField.isHidden = false
            self.updateTextField.stringValue = ""
        }
    }
    
    func update(_ currentWork: String) {
        DispatchQueue.main.async {
            self.updateTextField.stringValue = currentWork
        }
    }
    
    func failed() {
        DispatchQueue.main.async {
            self.openButton.title = self.ButtonNotRunningStateTitle
            self.progressBar.isHidden = true
            self.updateTextField.isHidden = true
            self.dialog(question: "Error", text: "Process failed!")
        }
    }
    
    func finished(_ errors: [String]) {
        DispatchQueue.main.async {
            self.isRunning = false
            self.openButton.title = self.ButtonNotRunningStateTitle
            self.progressBar.isHidden = true
            self.updateTextField.isHidden = true
            if errors.isEmpty {
                self.dialog(question: "Complete!", text: "All media has been imported without any errors!")
            } else {
                self.errors = errors
                self.performSegue(withIdentifier: "AlertSegue", sender: nil)
            }
        }
    }
    
    func stopped(_ errors: [String]) {
        DispatchQueue.main.async {
            self.isRunning = false
            self.openButton.title = self.ButtonNotRunningStateTitle
            self.progressBar.isHidden = true
            self.updateTextField.isHidden = true
            if errors.isEmpty {
                self.dialog(question: "Complete!", text: "All media has been imported without any errors!")
            } else {
                self.errors = errors
                self.performSegue(withIdentifier: "AlertSegue", sender: nil)
            }
        }
    }
}

