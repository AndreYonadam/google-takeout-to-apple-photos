//
//  AlertViewController.swift
//  Google Takout to Apple Photos
//
//  Created by Andre Yonadam on 1/5/20.
//  Copyright © 2020 Andre Yonadam. All rights reserved.
//

import Cocoa

class AlertViewController: NSViewController {
    
    // MARK: - Properties
    
    var logMessage = [String]()
    
    // MARK: - Outlets
    
    @IBOutlet weak var logTextField: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        logTextField.stringValue = logMessage.joined(separator: "\n")
    }
    
}
