import SwiftUI
import Foundation

// MARK: - File Model
struct TrackedFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let type: FileType
    let dateCreated: Date
    let dateModified: Date
    
    enum FileType: String, CaseIterable {
        case image = "Image"
        case document = "Document"
        case video = "Video"
        case audio = "Audio"
        case data = "Data"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .image: return "photo"
            case .document: return "doc.text"
            case .video: return "video"
            case .audio: return "music.note"
            case .data: return "folder"
            case .other: return "questionmark.folder"
            }
        }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - File Tracker Observable Model
@Observable
class FileTracker {
    private(set) var trackedFiles: [TrackedFile] = []
    private(set) var totalSize: Int64 = 0
    private(set) var lastUpdated: Date = Date()
    
    func addFile(_ file: TrackedFile) {
        trackedFiles.append(file)
        updateMetrics()
    }
    
    func removeFile(withId id: UUID) {
        trackedFiles.removeAll { $0.id == id }
        updateMetrics()
    }
    
    func clearAll() {
        trackedFiles.removeAll()
        updateMetrics()
    }
    
    func getFilesByType(_ type: TrackedFile.FileType) -> [TrackedFile] {
        trackedFiles.filter { $0.type == type }
    }
    
    var fileTypeBreakdown: [TrackedFile.FileType: Int] {
        Dictionary(grouping: trackedFiles, by: { $0.type })
            .mapValues { $0.count }
    }
    
    private func updateMetrics() {
        totalSize = trackedFiles.reduce(0) { $0 + $1.size }
        lastUpdated = Date()
    }
}

// MARK: - File Tracker View
struct FileTrackerDesktopView: View {
    @State private var tracker = FileTracker()
    @State private var selectedFilter: TrackedFile.FileType? = nil
    
    private var filteredFiles: [TrackedFile] {
        if let filter = selectedFilter {
            return tracker.getFilesByType(filter)
        }
        return tracker.trackedFiles
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header Stats
                headerStatsView
                
                // Filter Buttons
                filterButtonsView
                
                // Files List
                filesListView
                
                Spacer()
                
                // Action Buttons
                actionButtonsView
            }
            .padding()
            .navigationTitle("File Tracker")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var headerStatsView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(tracker.trackedFiles.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Total Size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: tracker.totalSize, countStyle: .file))
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            
            Text("Last updated: \(tracker.lastUpdated.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var filterButtonsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterButton(
                    title: "All",
                    count: tracker.trackedFiles.count,
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                }
                
                ForEach(TrackedFile.FileType.allCases, id: \.self) { type in
                    let count = tracker.fileTypeBreakdown[type] ?? 0
                    FilterButton(
                        title: type.rawValue,
                        count: count,
                        isSelected: selectedFilter == type,
                        icon: type.icon
                    ) {
                        selectedFilter = type
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var filesListView: some View {
        List {
            ForEach(filteredFiles) { file in
                FileRowView2(file: file)
            }
            .onDelete(perform: deleteFiles)
        }
        .listStyle(PlainListStyle())
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            Button("Add Sample File") {
                addSampleFile()
            }
            .buttonStyle(.bordered)
            
            Button("Clear All") {
                tracker.clearAll()
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracker.trackedFiles.isEmpty)
        }
    }
    
    private func deleteFiles(offsets: IndexSet) {
        for index in offsets {
            let file = filteredFiles[index]
            tracker.removeFile(withId: file.id)
        }
    }
    
    private func addSampleFile() {
        let sampleFiles = [
            TrackedFile(name: "photo.jpg", path: "/Documents/photo.jpg", size: 2048576, type: .image, dateCreated: Date(), dateModified: Date()),
            TrackedFile(name: "document.pdf", path: "/Documents/document.pdf", size: 1024000, type: .document, dateCreated: Date(), dateModified: Date()),
            TrackedFile(name: "video.mp4", path: "/Documents/video.mp4", size: 52428800, type: .video, dateCreated: Date(), dateModified: Date()),
            TrackedFile(name: "audio.mp3", path: "/Documents/audio.mp3", size: 4194304, type: .audio, dateCreated: Date(), dateModified: Date())
        ]
        
        let randomFile = sampleFiles.randomElement()!
        tracker.addFile(TrackedFile(
            name: "\(Int.random(in: 1...999))_\(randomFile.name)",
            path: randomFile.path,
            size: randomFile.size + Int64.random(in: -100000...100000),
            type: randomFile.type,
            dateCreated: Date(),
            dateModified: Date()
        ))
    }
}

// MARK: - Supporting Views
struct FilterButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let icon: String?
    let action: () -> Void
    
    init(title: String, count: Int, isSelected: Bool, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

struct FileRowView2: View {
    let file: TrackedFile
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.type.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(file.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(file.formattedSize)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(file.dateModified.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview {
    FileTrackerView()
}
