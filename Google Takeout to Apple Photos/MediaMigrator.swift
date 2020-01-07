//
//  LocationModifier.swift
//  Location Restore
//
//  Created by Andre Yonadam on 12/24/19.
//  Copyright © 2019 Andre Yonadam. All rights reserved.
//

import Cocoa
import AVKit
import Photos
import Checksum

struct ExifData: Codable {
    struct GeoData: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let latitudeSpan: Double
        let longitudeSpan: Double
    }
    let geoData: GeoData
    struct PhotoTakenTime: Codable {
        let timestamp: String
        let formatted: String
    }
    let photoTakenTime: PhotoTakenTime
}

struct OrigionalAsset {
    let url: URL
    let md5: String
    let hasPairingJson: Bool
}

protocol ProgressObserverProtocol: class {
    func started()
    func update(_ currentWork: String)
    func failed()
    func finished(_ errors: [String])
    func stopped(_ errors: [String])
}

class MediaMigrator: NSObject {
    
    // MARK: - Constants
    
    let CustomPhotoAlbumName = "Imported from Google Photos"
    
    // MARK: - Properties
    
    var shouldContinueToRun = true
    private var progressObserver: ProgressObserverProtocol
    private var folderPath: URL
    private var errors = [String]()
    private var assetCollectionPlaceholder: PHObjectPlaceholder?
    private var assetCollection: PHAssetCollection?
    private var mediaAsset: PHFetchResult<AnyObject>!
    private var origionalAssets = [OrigionalAsset]()
    
    // MARK: - Init
    
    init(folderPath: URL, progressObserver: ProgressObserverProtocol) {
        self.progressObserver = progressObserver
        self.folderPath = folderPath
    }
    
    // MARK: - Functions

    func start() {
        progressObserver.started()

        DispatchQueue.global(qos: .background).async {
            self.createAlbum(completion: { (success) -> Void in
                if success {
                    self.iterateOverAllFilesInDirectoryAndAddMedia()
                }
            })
        }
    }
    
    private func createAlbum(completion: @escaping (Bool) -> ()) {
        PHPhotoLibrary.shared().performChanges({
            let albumCreationRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.CustomPhotoAlbumName)
            self.assetCollectionPlaceholder = albumCreationRequest.placeholderForCreatedAssetCollection
        }) { success, _ in
            if success {
                let collectionFetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [self.assetCollectionPlaceholder!.localIdentifier], options: nil)
                if let assetCollection = collectionFetchResult.firstObject {
                    self.assetCollection = assetCollection
                    completion(true)
                } else {
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
    }
    
    private func iterateOverAllFilesInDirectoryAndAddMedia() {
        guard var fileEnumerator = FileManager.default.enumerator(at: folderPath, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions()) else {
            progressObserver.failed()
            return
        }
        
        // Count number of media files
        while let file = fileEnumerator.nextObject() as? URL {
            if shouldContinueToRun == false {
                progressObserver.stopped(errors)
                return
            }
            
            if !file.hasDirectoryPath {
                if file.absoluteString.contains("json") == false {
                    self.progressObserver.update("Analyzing file: \(file.path)")
                    let checksum = file.checksum(algorithm: .md5)!
                    let hasPairingJson = FileManager.default.fileExists(atPath: file.path + ".json")
                    origionalAssets.append(OrigionalAsset(url: file, md5: checksum, hasPairingJson: hasPairingJson))
                }
            }
        }
        
        if origionalAssets.count == 0 {
            progressObserver.finished(errors)
        } else {
            var uniqueAssets = [OrigionalAsset]()
            
            for origionalAsset in origionalAssets where origionalAsset.hasPairingJson == true {
                if uniqueAssets.contains(where: {$0.md5 == origionalAsset.md5}) == false {
                    self.progressObserver.update("Checking for duplicates: \(origionalAsset.url.path)")
                    uniqueAssets.append(origionalAsset)
                }
            }
            
            for origionalAsset in origionalAssets where origionalAsset.hasPairingJson == false {
                if uniqueAssets.contains(where: {$0.md5 == origionalAsset.md5}) == false {
                    self.progressObserver.update("Checking for duplicates: \(origionalAsset.url.path)")
                    uniqueAssets.append(origionalAsset)
                }
            }
                        
            fileEnumerator = FileManager.default.enumerator(at: folderPath, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions())!
            while let file = fileEnumerator.nextObject() as? URL {
                if shouldContinueToRun == false {
                    progressObserver.stopped(errors)
                    return
                }

                if !file.hasDirectoryPath {
                    if file.absoluteString.contains("json") == false {
                        let jsonURL = URL(string: file.absoluteString + ".json")!
                        let mediaData = loadJson(fileURL: jsonURL)
                        print(mediaData)
                        addMedia(mediaURL: file, mediaData: mediaData)
                    }
                }
            }
        }
    }
    
    private func addMedia(mediaURL: URL, mediaData: ExifData?) {
        addPhoto(mediaURL: mediaURL, mediaData: mediaData, completion: { (success) -> Void in
            if success {
                // Increment count
                self.origionalAssets.removeAll(where: {$0.url == mediaURL})
                self.progressObserver.update("Imported \(mediaURL)")
                self.checkIfCompleted()
            } else {
                self.addVideo(mediaURL: mediaURL, mediaData: mediaData, completion: { (success) -> Void in
                    if success {
                        self.origionalAssets.removeAll(where: {$0.url == mediaURL})
                        self.progressObserver.update("Imported \(mediaURL)")
                        self.checkIfCompleted()
                    } else {
                        // Could not add media
                        // Add the file path to the list of files unable to import
                        self.errors.append("Unable to import media file \(mediaURL)")
                        // Increment count
                        self.origionalAssets.removeAll(where: {$0.url == mediaURL})
                        self.progressObserver.update("Imported \(mediaURL)")
                        self.checkIfCompleted()
                    }
                })
            }
        })
    }
    
    private func addPhoto(mediaURL: URL, mediaData: ExifData?, completion: @escaping (Bool) -> ()) {
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: mediaURL)
            self.addAssetToAlbumWithData(assetRequest: assetRequest, mediaData: mediaData)
        }, completionHandler: { (success, error) in
            completion(success)
        })
    }
    
    private func addVideo(mediaURL: URL, mediaData: ExifData?, completion: @escaping (Bool) -> ()) {
        PHPhotoLibrary.shared().performChanges({
            let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: mediaURL)
            self.addAssetToAlbumWithData(assetRequest: assetRequest, mediaData: mediaData)
        }, completionHandler: { (success, error) in
            completion(success)
        })
    }
    
    /// Add asset to the album and attempt to add creation data and location data if available
    private func addAssetToAlbumWithData(assetRequest: PHAssetChangeRequest?, mediaData: ExifData?) {
        let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection!)
        let assetPlaceholder = assetRequest?.placeholderForCreatedAsset
        albumChangeRequest!.addAssets([assetPlaceholder!] as NSFastEnumeration)

        if let mediaData = mediaData {
            let epoch = Double(mediaData.photoTakenTime.timestamp)
            let creationDate = Date(timeIntervalSince1970: epoch ?? Double(Date().timeIntervalSince1970 * 1000))
            assetRequest?.creationDate = creationDate
            assetRequest?.location =  CLLocation(coordinate: CLLocationCoordinate2D(latitude: mediaData.geoData.latitude, longitude: mediaData.geoData.longitude), altitude: CLLocationDistance(mediaData.geoData.altitude), horizontalAccuracy: CLLocationAccuracy(exactly: mediaData.geoData.latitudeSpan) ?? 0, verticalAccuracy: CLLocationAccuracy(exactly: mediaData.geoData.longitudeSpan) ?? 0, course: CLLocationDirection.init(), speed: 0, timestamp: creationDate as Date)
        }
    }

    func loadJson(fileURL: URL) -> ExifData? {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let jsonData = try decoder.decode(ExifData.self, from: data)
            return jsonData
        } catch {
            // Do nothing
        }
        return nil
    }
    
    private func checkIfCompleted() {
        if origionalAssets.count == 0 {
            progressObserver.finished(errors)
        }
    }
}
