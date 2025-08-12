//
//  MetaLoader.swift
//
//  Created by Tanel Treuberg on 20.07.2025.
//

import Foundation
import AVFoundation
import UIKit // For UIImage if handling artwork

enum MetadataError: Error {
    case metadataNotFound
    case dataCorrupted
}

struct VideoMetadata {
    let title: String?
    let creationDate: Date?
    let artwork: UIImage?
    let duration: TimeInterval?
}

func readVideoMetadata(from videoURL: URL) async throws -> VideoMetadata {
    let asset = AVURLAsset(url: videoURL)

    // Asynchronously load the common metadata and duration
    // Using .load() is efficient as it loads multiple properties in parallel
    let (commonMetadata, duration) = try await asset.load(.metadata, .duration)

    // Or, for just one property:
    // let commonMetadata = try await asset.loadMetadata(for: .common)

    // --- Parse Common Metadata ---
    var title: String?
    var creationDate: Date?
    var artworkImage: UIImage?

    for item in commonMetadata {
        guard let key = item.commonKey?.rawValue else { continue }

        switch key {
        case AVMetadataKey.commonKeyTitle.rawValue:
            title = try await item.load(.stringValue)
        case AVMetadataKey.commonKeyCreationDate.rawValue:
            // The value for creationDate is often a String in "yyyy-MM-dd'T'HH:mm:ssZ" format
            if let dateString = try await item.load(.stringValue) {
                let formatter = ISO8601DateFormatter()
                creationDate = formatter.date(from: dateString)
            }
        case AVMetadataKey.commonKeyArtwork.rawValue:
            if let imageData = try await item.load(.dataValue) {
                artworkImage = UIImage(data: imageData)
            }
        default:
            break
        }
    }
    
    // Get the duration in seconds
    let durationInSeconds = duration.seconds

    return VideoMetadata(
        title: title,
        creationDate: creationDate,
        artwork: artworkImage,
        duration: durationInSeconds
    )
}

// --- How to use it ---
func exampleUsage() {
    guard let url = Bundle.main.url(forResource: "myVideo", withExtension: "mov") else {
        print("Video file not found.")
        return
    }

    Task {
        do {
            let metadata = try await readVideoMetadata(from: url)
            print("Title: \(metadata.title ?? "N/A")")
            print("Duration: \(metadata.duration ?? 0) seconds")
            if let date = metadata.creationDate {
                print("Created on: \(date)")
            }
            if metadata.artwork != nil {
                print("Artwork found.")
            }
        } catch {
            print("Failed to read metadata: \(error)")
        }
    }
}
