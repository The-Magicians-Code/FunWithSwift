//
//  QuickTimeChapters.swift
//
//  Created by Tanel Treuberg on 12.08.2025.
//  Claude's proposal for writing QuickTime chapter markers into a .mov file
//  Currently running into an error when attempting to add a new text track

import AVFoundation
import CoreMedia
import UIKit

// MARK: - Swift 6 Compliant Video Chapter Writer
final class VideoChapterWriter {
    
    // MARK: - Error Types
    enum ChapterError: Error {
        case invalidAsset
        case failedCreatingMovie
        case failedCreatingTrack
        case failedCreatingFormatDescription
        case failedPreparingSampleData
        case failedCreatingBlockBuffer
        case failedCreatingSampleBuffer
        case fileAlreadyExists
        case noVideoTrack
    }
    
    // MARK: - Chapter Model
    struct Chapter: Sendable {
        let title: String
        let time: CMTime
        let thumbnail: UIImage?
        let duration: CMTime?
    }
    
    // MARK: - Main Export Function (Async for iOS 16+)
    func writeChaptersToVideo(
        sourceURL: URL,
        destinationURL: URL,
        chapters: [Chapter]
    ) async throws {
        
        // Remove destination file if exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create source movie with precise timing
        let sourceMovie = AVMovie(url: sourceURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        
        // Load movie duration using modern async API
        let movieDuration = try await sourceMovie.load(.duration)
        
//        // Create mutable movie for editing
//        guard let mutableMovie = try? AVMutableMovie(
//            settingsFrom: sourceMovie,
//            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
//        ) else {
//            print(#function, "Failed to create mutable movie")
//            throw ChapterError.failedCreatingMovie
//        }
        
        let mutableMovie = AVMutableMovie()
        
        // Set storage for new media data directly to destination
        mutableMovie.defaultMediaDataStorage = AVMediaDataStorage(url: destinationURL)
        
        // 4. Manually copy essential properties to preserve orientation, etc.
        mutableMovie.preferredTransform = try await sourceMovie.load(.preferredTransform)

        // 5. Copy all existing video and audio tracks from the source to the new movie
        let assetTracks = try await sourceMovie.load(.tracks)
        for track in assetTracks {
            // Filter for only video and audio
            guard track.mediaType == .video || track.mediaType == .audio else { continue }
            
            guard let newVideoTrack = mutableMovie.addMutableTrack(
                withMediaType: track.mediaType,
                copySettingsFrom: track
            ) else {
                print("Failed to add track of type \(track.mediaType) to the new movie.")
                throw ChapterError.failedCreatingTrack
            }
            
            do {
                let timeRange = try await track.load(.timeRange)
                try newVideoTrack.insertTimeRange(timeRange, of: track, at: .zero, copySampleData: true)
            } catch {
                print("Failed to insert time range for track: \(error)")
                throw ChapterError.failedCreatingTrack
            }
        }
        // Use synchronous track access to avoid Sendable issues
//        let videoTracks = mutableMovie.tracks(withMediaType: .video)
//        print(videoTracks)
//        guard let videoTrack = videoTracks.first else {
//            print("Failed to get video track")
//            throw ChapterError.noVideoTrack
//        }
        
        guard let videoTrack = mutableMovie.tracks(withMediaType: .video).first else {
            throw ChapterError.noVideoTrack
        }
        
        print(mutableMovie.tracks)
        // Create chapter tracks (text for titles, video for thumbnails)
        guard let chapterTextTrack = mutableMovie.addMutableTrack(
            withMediaType: .text,
            copySettingsFrom: nil
        ) else {
            print("Failed to create chapter text track")
            throw ChapterError.failedCreatingTrack
        }
        
        guard let chapterThumbnailTrack = mutableMovie.addMutableTrack(
            withMediaType: .video,
            copySettingsFrom: nil
        ) else {
            print("Failed to create chapter thumbnail track")
            throw ChapterError.failedCreatingTrack
        }
        
        // Process and add chapters
        try addChapterSamples(
            chapters: chapters,
            textTrack: chapterTextTrack,
            thumbnailTrack: chapterThumbnailTrack,
            movieDuration: movieDuration
        )
        
        // Configure chapter tracks as disabled (not for playback)
        chapterTextTrack.isEnabled = false
        chapterThumbnailTrack.isEnabled = false
        
        // Create track associations - video track references chapter tracks
        videoTrack.addTrackAssociation(to: chapterTextTrack, type: .chapterList)
        videoTrack.addTrackAssociation(to: chapterThumbnailTrack, type: .chapterList)
        
        // Write movie header to finalize the file
        try mutableMovie.writeHeader(
            to: destinationURL,
            fileType: .mov,
            options: .addMovieHeaderToDestination
        )
    }
    
    // MARK: - Chapter Sample Processing
    private func addChapterSamples(
        chapters: [Chapter],
        textTrack: AVMutableMovieTrack,
        thumbnailTrack: AVMutableMovieTrack,
        movieDuration: CMTime
    ) throws {
        
        for (index, chapter) in chapters.enumerated() {
            // Calculate chapter duration (time to next chapter or movie end)
            let chapterDuration: CMTime
            if let providedDuration = chapter.duration {
                chapterDuration = providedDuration
            } else if index < chapters.count - 1 {
                chapterDuration = CMTimeSubtract(chapters[index + 1].time, chapter.time)
            } else {
                chapterDuration = CMTimeSubtract(movieDuration, chapter.time)
            }
            
            let timeRange = CMTimeRange(start: chapter.time, duration: chapterDuration)
            
            // Add text sample for chapter title
            try appendTextSample(
                title: chapter.title,
                to: textTrack,
                timeRange: timeRange
            )
            
            // Add thumbnail sample if available
            if let thumbnail = chapter.thumbnail {
                try appendThumbnailSample(
                    image: thumbnail,
                    to: thumbnailTrack,
                    timeRange: timeRange
                )
            }
        }
    }
    
    // MARK: - Text Sample Creation
    private func appendTextSample(
        title: String,
        to track: AVMutableMovieTrack,
        timeRange: CMTimeRange
    ) throws {
        
        // Create text format description per QTFF spec
        let formatDesc = try createTextFormatDescription()
        
        // Create sample data with UTF-8 encoding atom
        let sampleData = try createTextSampleData(from: title)
        
        // Append sample to track
        try appendSample(
            data: sampleData,
            formatDescription: formatDesc,
            timeRange: timeRange,
            to: track
        )
    }
    
    private func createTextFormatDescription() throws -> CMTextFormatDescription {
        // Text sample description per QTFF specification
        let textDescription: [UInt8] = [
            0x00, 0x00, 0x00, 0x3C,  // Size: 60 bytes
            0x74, 0x65, 0x78, 0x74,  // Type: 'text'
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Reserved
            0x00, 0x01,  // Data reference index
            0x00, 0x00, 0x00, 0x01,  // Display flags
            0x00, 0x00, 0x00, 0x01,  // Text justification
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Background color
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Default text box
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Reserved
            0x00, 0x00,  // Font number
            0x00, 0x00,  // Font face
            0x00,        // Reserved
            0x00, 0x00,  // Reserved
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Foreground color
            0x00  // Null-terminated text name
        ]
        
        var formatDesc: CMTextFormatDescription?
        let status = textDescription.withUnsafeBytes { ptr in
            CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault,
                bigEndianTextDescriptionData: ptr.baseAddress!,
                size: textDescription.count,
                flavor: nil,
                mediaType: kCMMediaType_Text,
                formatDescriptionOut: &formatDesc
            )
        }
        
        guard status == noErr, let formatDesc else {
            throw ChapterError.failedCreatingFormatDescription
        }
        
        return formatDesc
    }
    
    private func createTextSampleData(from text: String) throws -> Data {
        // Text encoding modifier atom for UTF-8 support
        struct TextEncodingAtom {
            let size: UInt32
            let type: UInt32  // 'encd'
            let encoding: UInt32
            
            init() {
                self.size = CFSwapInt32HostToBig(UInt32(MemoryLayout<TextEncodingAtom>.size))
                self.type = CFSwapInt32HostToBig(0x656E6364)  // 'encd'
                self.encoding = CFSwapInt32HostToBig(0x08000100)  // UTF-8
            }
        }
        
        guard let utf8Data = text.data(using: .utf8) else {
            throw ChapterError.failedPreparingSampleData
        }
        
        // Sample structure: [size][text data][encoding atom]
        let textLength = CFSwapInt16HostToBig(UInt16(utf8Data.count))
        let encodingAtom = TextEncodingAtom()
        
        var sampleData = Data()
        withUnsafeBytes(of: textLength) { sampleData.append(contentsOf: $0) }
        sampleData.append(utf8Data)
        withUnsafeBytes(of: encodingAtom) { sampleData.append(contentsOf: $0) }
        
        return sampleData
    }
    
    // MARK: - Thumbnail Sample Creation
    private func appendThumbnailSample(
        image: UIImage,
        to track: AVMutableMovieTrack,
        timeRange: CMTimeRange
    ) throws {
        
        // Create JPEG format description with image dimensions
        let formatDesc = try createJPEGFormatDescription(for: image)
        
        // Convert image to JPEG data
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw ChapterError.failedPreparingSampleData
        }
        
        // Append sample to track
        try appendSample(
            data: jpegData,
            formatDescription: formatDesc,
            timeRange: timeRange,
            to: track
        )
    }
    
    private func createJPEGFormatDescription(for image: UIImage) throws -> CMVideoFormatDescription {
        let size = image.size
        
        // Ensure dimensions fit in UInt16
        guard size.width <= CGFloat(UInt16.max),
              size.height <= CGFloat(UInt16.max) else {
            throw ChapterError.failedCreatingFormatDescription
        }
        
        // JPEG video sample description per QTFF specification
        var jpegDescription: [UInt8] = [
            0x00, 0x00, 0x00, 0x56,  // Size: 86 bytes
            0x6A, 0x70, 0x65, 0x67,  // Type: 'jpeg'
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Reserved
            0x00, 0x00,  // Data reference index
            0x00, 0x00,  // Version
            0x00, 0x00,  // Revision level
            0x00, 0x00, 0x00, 0x00,  // Vendor
            0x00, 0x00, 0x00, 0x00,  // Temporal quality
            0x00, 0x00, 0x00, 0x00,  // Spatial quality
            0x00, 0x00,  // Width (to be filled)
            0x00, 0x00,  // Height (to be filled)
            0x00, 0x48, 0x00, 0x00,  // Horizontal resolution
            0x00, 0x48, 0x00, 0x00,  // Vertical resolution
            0x00, 0x00, 0x00, 0x00,  // Data size
            0x00, 0x01,  // Frame count: 1
            // 32 bytes for compressor name (zeros)
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x18,  // Color depth: 24
            0xFF, 0xFF   // Color table ID: -1
        ]
        
        // Insert image dimensions at correct offsets
        let width = CFSwapInt16HostToBig(UInt16(size.width))
        let height = CFSwapInt16HostToBig(UInt16(size.height))
        
        jpegDescription.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: width, toByteOffset: 32, as: UInt16.self)
            ptr.storeBytes(of: height, toByteOffset: 34, as: UInt16.self)
        }
        
        var formatDesc: CMVideoFormatDescription?
        let status = jpegDescription.withUnsafeBytes { ptr in
            CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
                allocator: kCFAllocatorDefault,
                bigEndianImageDescriptionData: ptr.baseAddress!,
                size: jpegDescription.count,
                stringEncoding: CFStringGetSystemEncoding(),
                flavor: nil,
                formatDescriptionOut: &formatDesc
            )
        }
        
        guard status == noErr, let formatDesc else {
            throw ChapterError.failedCreatingFormatDescription
        }
        
        return formatDesc
    }
    
    // MARK: - Sample Buffer Creation
    private func appendSample(
        data: Data,
        formatDescription: CMFormatDescription,
        timeRange: CMTimeRange,
        to track: AVMutableMovieTrack
    ) throws {
        
        // Create block buffer from data
        let blockBuffer = try createBlockBuffer(from: data)
        
        // Create sample buffer with timing info
        let sampleBuffer = try createSampleBuffer(
            from: blockBuffer,
            formatDescription: formatDescription,
            timeRange: timeRange
        )
        
        // Append to track
        try track.append(sampleBuffer, decodeTime: nil, presentationTime: nil)
    }
    
    private func createBlockBuffer(from data: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        
        // Allocate and copy data to avoid use-after-free
        let status = data.withUnsafeBytes { ptr in
            var localBlockBuffer: CMBlockBuffer?
            
            // Create with allocated memory
            let createStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &localBlockBuffer
            )
            
            guard createStatus == kCMBlockBufferNoErr,
                  let buffer = localBlockBuffer else {
                return createStatus
            }
            
            // Ensure memory is allocated
            let assureStatus = CMBlockBufferAssureBlockMemory(buffer)
            guard assureStatus == kCMBlockBufferNoErr else {
                return assureStatus
            }
            
            // Copy data into buffer
            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
            
            blockBuffer = buffer
            return replaceStatus
        }
        
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw ChapterError.failedCreatingBlockBuffer
        }
        
        return blockBuffer
    }
    
    private func createSampleBuffer(
        from blockBuffer: CMBlockBuffer,
        formatDescription: CMFormatDescription,
        timeRange: CMTimeRange
    ) throws -> CMSampleBuffer {
        
        var sampleTiming = CMSampleTimingInfo(
            duration: timeRange.duration,
            presentationTimeStamp: timeRange.start,
            decodeTimeStamp: .invalid
        )
        
        var sampleSize = CMBlockBufferGetDataLength(blockBuffer)
        var sampleBuffer: CMSampleBuffer?
        
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        
        guard status == noErr, let sampleBuffer else {
            throw ChapterError.failedCreatingSampleBuffer
        }
        
        return sampleBuffer
    }
}

// MARK: - Usage Example
extension VideoChapterWriter {
    static func example() async throws {
        let writer = VideoChapterWriter()
        
        let sourceURL = Bundle.main.url(
            forResource: "UnChaptered",
            withExtension: "mov")!
        print("Source URL: \(sourceURL)")
        let fileName = "Claude-\(UUID().uuidString).mov"
        let destinationURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(fileName)
        print("Destination URL: \(destinationURL)")
        let chapters = [
            Chapter(
                title: "Introduction",
                time: CMTime(seconds: 0, preferredTimescale: 600),
                thumbnail: UIImage(systemName: "play.circle"),
                duration: nil
            ),
            Chapter(
                title: "Main Content",
                time: CMTime(seconds: 60, preferredTimescale: 600),
                thumbnail: UIImage(systemName: "star.fill"),
                duration: nil
            ),
            Chapter(
                title: "Conclusion",
                time: CMTime(seconds: 180, preferredTimescale: 600),
                thumbnail: UIImage(systemName: "checkmark.circle"),
                duration: nil
            )
        ]
        
//        let sourceURL = URL(fileURLWithPath: "input.mov")
//        let destinationURL = URL(fileURLWithPath: "output.mov")
        
        try await writer.writeChaptersToVideo(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            chapters: chapters
        )
    }
}
