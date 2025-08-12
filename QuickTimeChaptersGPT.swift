//
//  QuickTimeChaptersGPT.swift
//
//  Created by Tanel Treuberg on 12.08.2025.
//  Write chapter markers to a QuickTime .mov video, proposed by GPT 5
//  Currently running into errors when attempting to add a new text track

import AVFoundation
import CoreMedia
import CoreVideo

/// Minimal chapter model
public struct Chapter2: Sendable, Hashable {
    public let title: String
    public let start: CMTime
    public init(_ title: String, seconds: Double) {
        self.title = title
        self.start = CMTime(seconds: seconds, preferredTimescale: 600)
    }
}

/// Writes a .mov that contains a proper QuickTime chapter (text) track
/// and associates it with the primary video track. No re-encode.
/// - Note: You can rewrap to MP4 afterwards if needed.
public func writeChaptersGPT(
    sourceURL: URL,
    outputURL: URL,
    chapters: [Chapter2]
) async throws {
    // Clean destination; AVMutableMovie won't overwrite
    try? FileManager.default.removeItem(at: outputURL)

    // 1) Create editable movie cloned from source (precise timing)
    let src = AVMovie(url: sourceURL,
                      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let dst = try? AVMutableMovie(settingsFrom: src,
                                        options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]) else {
        throw NSError(domain: "Chapters", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create mutable movie"])
    }

    // New samples (chapter text) will be stored at the destination
    dst.defaultMediaDataStorage = AVMediaDataStorage(url: outputURL)

    // 2) Copy all source media tracks “as is” (no re-encoding)
    let sourceTracks = try await src.load(.tracks)
    for s in sourceTracks {
        guard let t = dst.addMutableTrack(withMediaType: s.mediaType, copySettingsFrom: s) else {
            throw NSError(domain: "Chapters", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add track"])
        }
        let full = try await s.load(.timeRange)
        try t.insertTimeRange(full, of: s, at: full.start, copySampleData: true)
    }

    // Find the primary video track for association
    guard
        let videoTrack = try await dst.loadTracks(withMediaType: .video).first
    else { throw NSError(domain: "Chapters", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video track"]) }

    // 3) Create a TEXT chapter track
    guard let chapterTrack = dst.addMutableTrack(withMediaType: .text, copySettingsFrom: nil) else {
        throw NSError(domain: "Chapters", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot create chapter track"])
    }

    // Build the common TEXT sample description (QuickTime 'text')
    let textFormatDesc = try makeQTTextFormatDescription()

    // 4) Append one text sample per chapter spanning until the next chapter
    //    (chapter writing core: create CMSampleBuffer for each title & append)
    let sorted = chapters.sorted { $0.start < $1.start }
    let movieDuration = try await dst.load(.duration)
    for (i, ch) in sorted.enumerated() {
        let nextStart = (i + 1 < sorted.count) ? sorted[i + 1].start : movieDuration
        let dur = CMTimeSubtract(nextStart, ch.start)
        let timeRange = CMTimeRange(start: ch.start, duration: dur)

        let sample = try makeQTTextSampleBuffer(
            text: ch.title,
            formatDesc: textFormatDesc,
            timeRange: timeRange
        )
        // Appends sample data and updates sample tables for the text track
        try chapterTrack.append(sample, decodeTime: nil, presentationTime: nil)
    }

    // Make chapter track span the full movie timeline (media time mapping)
    let fullRange = CMTimeRange(start: .zero, duration: movieDuration)
    chapterTrack.insertMediaTimeRange(fullRange, into: fullRange)

    // 5) Associate the chapter text track to the video as a chapter list
    videoTrack.addTrackAssociation(to: chapterTrack, type: .chapterList)
    chapterTrack.isEnabled = false // chapters are navigational, not “playback” media

    // 6) Finalize headers (write moov/track tables) — no data rewrite
    try dst.writeHeader(to: outputURL, fileType: .mov, options: .addMovieHeaderToDestination)
}

/// Build a QuickTime 'text' sample description and wrap it into a CMFormatDescription.
/// Matches the QTFF Text Sample Description layout used for chapter tracks.
private func makeQTTextFormatDescription() throws -> CMFormatDescription {
    // 60-byte 'text' sample description (big-endian fields).
    // This is the minimal, valid descriptor for static chapter text.
    let desc: [UInt8] = [
        0x00,0x00,0x00,0x3C,  0x74,0x65,0x78,0x74,             // size(60), 'text'
        0x00,0x00,0x00,0x00, 0x00,0x00,                         // reserved(6)
        0x00,0x01,                                             // dataRefIndex
        0x00,0x00,0x00,0x01,                                   // display flags
        0x00,0x00,0x00,0x01,                                   // text justification
        0x00,0x00,0x00,0x00,0x00,0x00,                         // bg color
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,               // default text box
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,               // reserved
        0x00,0x00,                                             // font number
        0x00,0x00,                                             // font face
        0x00,                                                  // reserved
        0x00,0x00,                                             // reserved
        0x00,0x00,0x00,0x00,0x00,0x00,                         // fg color
        0x00                                                  // name (C-string)
    ]
    let data = Data(desc)
    var fmt: CMFormatDescription?
    try data.withUnsafeBytes { buf in
        let st = CMFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            mediaType: kCMMediaType_Text,             // QuickTime TEXT media
            mediaSubType: FourCharCode(bigEndian: "text".fourCC),
            extensions: nil,
            formatDescriptionOut: &fmt
        )
        guard st == noErr, fmt != nil else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: "CMFormatDescriptionCreate failed"])
        }
    }
    return fmt!
}

/// Encodes the title as UTF-8 sample data and returns a CMSampleBuffer spanning `timeRange`.
private func makeQTTextSampleBuffer(
    text: String,
    formatDesc: CMFormatDescription,
    timeRange: CMTimeRange
) throws -> CMSampleBuffer {
    // Chapter text payload: UTF-8 bytes are accepted by QuickTime text decoders for chapter lists.
    var bytes = [UInt8](text.utf8)
    let length = bytes.count

    var block: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: &bytes, // uses our stack buffer; retained by CoreMedia until sample is created
        blockLength: length,
        blockAllocator: kCFAllocatorNull,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: length,
        flags: 0,
        blockBufferOut: &block
    )
    guard status == kCMBlockBufferNoErr, let bb = block else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CMBlockBufferCreateWithMemoryBlock failed"])
    }

    var sample: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: timeRange.duration,
        presentationTimeStamp: timeRange.start,
        decodeTimeStamp: .invalid
    )
    status = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: bb,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDesc,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sample
    )
    guard status == noErr, let sb = sample else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CMSampleBufferCreate failed"])
    }
    return sb
}

private extension String {
    var fourCC: UInt32 {
        let scalars = unicodeScalars
        var value: UInt32 = 0
        for s in scalars.prefix(4) { value = (value << 8) | UInt32(s.value & 0xFF) }
        return value
    }
}
