//
//  FileTracker.swift
//
//  Created by Tanel Treuberg on 28.08.2025.
//

import Foundation

@Observable
class FileTracker {
    private var trackedFiles: Set<URL> = []
    
    func track(_ fileURL: URL) {
        trackedFiles.insert(fileURL)
    }
    
    func remove(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            print("Error removing file or it does not exist: \(error)")
        }
        trackedFiles.remove(fileURL)
    }
    
    func removeAll() {
        for fileURL in trackedFiles {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Error removing file or it does not exist: \(error)")
            }
        }
        trackedFiles.removeAll()
    }
}
