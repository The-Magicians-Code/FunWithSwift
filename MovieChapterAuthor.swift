// Swift 6 – Complete helper for adding a QuickTime chapter track to an AVMutableMovie
//
// What it does
// - Creates a hidden `.text` track whose samples are QuickTime Text (QTText) payloads
// - Appends one sample per Chapter (title + start time)
// - Associates the chapter track to your primary video (or audio) track via `.chapterList`
// - Writes a new movie header to `outURL` so the chapters are recognized by players
//
// Requirements
// - AVFoundation, CoreMedia, CoreServices
// - Input file must be a QuickTime/ISO-BMFF container (.mov/.mp4/.m4v/.m4a etc.)
//
// Notes
// - QTText sample payloads are: [UInt16 big-endian length] + [UTF-8 bytes]. No style runs.
// - We set the chapter track’s language tag and disable presentation so it doesn’t render as captions.
// - We set `mediaDataStorage` to the same destination URL so appended samples are stored alongside the output.

import AVFoundation
import CoreMedia
import Foundation

public enum ChapterAuthorError: Error, LocalizedError {
    case mainTrackNotFound
    case chapterTrackCreationFailed
    case formatDescriptionCreationFailed(OSStatus)
    case blockBufferCreationFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case invalidDurations

    public var errorDescription: String? {
        switch self {
        case .mainTrackNotFound:
            return "Couldn’t find a primary track (video or audio) to associate chapters with."
        case .chapterTrackCreationFailed:
            return "Failed to create a chapter (.text) track."
        case .formatDescriptionCreationFailed(let status):
            return "Failed to create QTText format description (OSStatus: \(status))."
        case .blockBufferCreationFailed(let status):
            return "Failed to create CMBlockBuffer for text sample (OSStatus: \(status))."
        case .sampleBufferCreationFailed(let status):
            return "Failed to create CMSampleBuffer for text sample (OSStatus: \(status))."
        case .invalidDurations:
            return "Computed a non-positive duration between chapter markers. Check input times."
        }
    }
}

public struct MovieChapterAuthor {

    /// Adds a chapter track to `sourceURL` and writes the updated movie header + new sample data to `outURL`.
    /// - Parameters:
    ///   - sourceURL: Existing movie to augment.
    ///   - outURL: Destination .mov (or compatible). Will be created/overwritten.
    ///   - chapters: Array of `Chapter` (title + start times). Must be sorted by time.
    ///   - preferAssociationMediaType: `.video` first; falls back to `.audio` if no video track exists.
    ///   - languageTag: BCP-47 tag for chapter titles, e.g. "en", "en-US", "pl".
    ///   - timeScale: Timescale used for the chapter track (default 600).
    public static func addChapters(
        from sourceURL: URL,
        to outURL: URL,
        chapters: [Chapter],
        preferAssociationMediaType: AVMediaType = .video,
        languageTag: String = "en",
        timeScale: CMTimeScale = 600
    ) throws {
        precondition(!chapters.isEmpty, "Chapters array must not be empty")

        // 1) Open mutable movie with precise timing
        let movie = try AVMutableMovie(url: sourceURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // 2) Choose main track to associate chapters with
        let mainTrack: AVMutableMovieTrack? = movie.tracks
            .compactMap { $0 as? AVMutableMovieTrack }
            .first(where: { $0.mediaType == preferAssociationMediaType })
            ?? movie.tracks.compactMap { $0 as? AVMutableMovieTrack }.first(where: { $0.mediaType == .audio })

        guard let mainTrack else { throw ChapterAuthorError.mainTrackNotFound }

        // 3) Create chapter text track
        guard let chapterTrack = movie.addMutableTrack(withMediaType: .text, copySettingsFrom: nil, options: nil) else {
            throw ChapterAuthorError.chapterTrackCreationFailed
        }
        chapterTrack.isEnabled = false                 // hidden; we don’t want visible captions
        chapterTrack.naturalTimeScale = timeScale      // must be set before editing
        chapterTrack.extendedLanguageTag = languageTag // BCP-47

        // Ensure appended sample data goes to the output file we’ll write
        chapterTrack.mediaDataStorage = AVMediaDataStorage(url: outURL, options: nil)

        // 4) Create a QTText format description for the chapter samples
        let formatDesc = try createQTTextFormatDescription()

        // 5) Compute per-chapter durations (each extends until the next marker; last one to movie end)
        let sorted = chapters.sorted { $0.time < $1.time }
        let movieDuration = movie.duration
        var timedChapters: [(title: String, pts: CMTime, dur: CMTime)] = []
        for (idx, ch) in sorted.enumerated() {
            let nextStart = (idx + 1 < sorted.count) ? sorted[idx + 1].time : movieDuration
            var duration = CMTimeSubtract(nextStart, ch.time)
            // Guard against <= 0 duration — give the last one a small tail if needed
            if duration <= .zero { duration = CMTimeMake(value: 1, timescale: timeScale) }
            timedChapters.append((ch.title, ch.time, duration))
        }
        guard timedChapters.allSatisfy({ $0.dur > .zero }) else { throw ChapterAuthorError.invalidDurations }

        // 6) Append one text sample per chapter
        for item in timedChapters {
            let data = makeQTTextSampleData(item.title)
            let sample = try makeTextSampleBuffer(data: data, formatDescription: formatDesc, duration: item.dur)
            // decodeTime is usually kCMTimeInvalid for text; presentationTime is the chapter start
            chapterTrack.append(sample, decodeTime: .invalid, presentationTime: item.pts)
        }

        // 7) Associate the chapter track with the main track
        try mainTrack.addTrackAssociation(to: chapterTrack, type: .chapterList)

        // 8) Commit by writing a new movie header (and ensuring the mdat with our text samples is present)
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }
        try movie.writeMovieHeader(to: outURL, fileType: .mov, options: .addMovieHeaderToDestination)
    }

    // MARK: - Internals

    /// Creates a QTText format description for text samples used as chapter titles.
    /// We use kCMMediaType_Text + kCMTextFormatType_QTText with minimal extensions.
    private static func createQTTextFormatDescription() throws -> CMFormatDescription {
        var desc: CMFormatDescription?
        // Minimal extension dictionary; you can add display flags, default styles, etc., if desired.
        let extensions = NSDictionary() as CFDictionary
        let status = CMTextFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            mediaSubType: CMTextFormatType(kCMTextFormatType_QTText),
            formatDescriptionOut: &desc,
            textFormatDescriptionExtension: extensions
        )
        if status != noErr || desc == nil { throw ChapterAuthorError.formatDescriptionCreationFailed(status) }
        return desc!
    }

    /// Builds the QTText sample payload: 2-byte big-endian length + UTF-8 bytes of the title.
    private static func makeQTTextSampleData(_ title: String) -> Data {
        let utf8 = Array(title.utf8)
        let length = UInt16(utf8.count).bigEndian
        var data = Data()
        withUnsafeBytes(of: length) { data.append(contentsOf: $0) }
        data.append(contentsOf: utf8)
        return data
    }

    /// Wraps the text payload in CMBlockBuffer/CMSampleBuffer with timing.
    private static func makeTextSampleBuffer(
        data: Data,
        formatDescription: CMFormatDescription,
        duration: CMTime
    ) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer? = nil
        // Allocate a block buffer and copy the data in
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status != noErr || blockBuffer == nil { throw ChapterAuthorError.blockBufferCreationFailed(status) }

        data.withUnsafeBytes { raw in
            _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: data.count)
        }

        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer? = nil
        var sampleSize = data.count
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        if status != noErr || sampleBuffer == nil { throw ChapterAuthorError.sampleBufferCreationFailed(status) }
        return sampleBuffer!
    }
}

// MARK: - Example usage
//
// let chapters: [Chapter] = [
//     .init(title: "Intro", startTime: 0.0),
//     .init(title: "Setup", startTime: 42.5),
//     .init(title: "Demo",  startTime: 120.0)
// ]
// try MovieChapterAuthor.addChapters(
//     from: inputURL,
//     to: outputURL,
//     chapters: chapters,
//     preferAssociationMediaType: .video,
//     languageTag: "en"
// )
//
// After writing, load `outputURL` in AVPlayerViewController; the chapter popover/menus should appear.
