import SwiftUI
import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let createdDate: Date
    let modifiedDate: Date
    let isDirectory: Bool
}

struct FileTrackerView: View {
    @State private var files: [FileItem] = []
    @State private var isLoading = false
    @State private var totalSize: Int64 = 0
    
    var body: some View {
        VStack {
            // Summary header
            VStack() {
                Text("Files in Sandbox")
                    .font(.headline)
                HStack {
                    Text("\(files.count) items")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))
            .cornerRadius(8)
            .padding(.horizontal)
            
            if isLoading {
                ProgressView("Scanning files...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files) { file in
                    FileRowView(file: file)
                }
            }
        }
        .navigationTitle("File Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    scanFiles()
                }
            }
        }
        .onAppear {
            scanFiles()
        }
    }
    
    private func scanFiles() {
        isLoading = true
        
        Task {
            let foundFiles = scanSandboxFiles()
            
            await MainActor.run {
                self.files = foundFiles.sorted { $0.modifiedDate > $1.modifiedDate }
                self.totalSize = foundFiles.reduce(0) { $0 + $1.size }
                self.isLoading = false
            }
        }
    }
    
    private func scanSandboxFiles() -> [FileItem] {
        var foundFiles: [FileItem] = []
        
        // Get all sandbox directories
        let fileManager = FileManager.default
        let directories = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.temporaryDirectory,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        for directory in directories {
            foundFiles.append(contentsOf: scanDirectory(directory))
        }
        
        return foundFiles
    }
    
    private func scanDirectory(_ directory: URL) -> [FileItem] {
        var files: [FileItem] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ]
        ) else { return files }
        
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey
                ])
                
                let isDirectory = resourceValues.isDirectory ?? false
                let size = Int64(resourceValues.fileSize ?? 0)
                let createdDate = resourceValues.creationDate ?? Date()
                let modifiedDate = resourceValues.contentModificationDate ?? Date()
                
                files.append(FileItem(
                    name: fileURL.lastPathComponent,
                    path: fileURL.path,
                    size: isDirectory ? 0 : size,
                    createdDate: createdDate,
                    modifiedDate: modifiedDate,
                    isDirectory: isDirectory
                ))
            } catch {
                print("Error reading file attributes: \(error)")
            }
        }
        
        return files
    }
}

struct FileRowView: View {
    let file: FileItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: file.isDirectory ? "folder" : fileIcon(for: file.name))
                    .foregroundColor(file.isDirectory ? .blue : .primary)
                
                Text(file.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                
                Spacer()
                
                if !file.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(file.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Text("Modified: \(file.modifiedDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func fileIcon(for filename: String) -> String {
        let ext = filename.lowercased().split(separator: ".").last ?? ""
        
        switch ext {
        case "mov", "mp4", "avi", "mkv":
            return "video"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo"
        case "mp3", "wav", "aac", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "txt", "md":
            return "doc.text"
        default:
            return "doc"
        }
    }
}

#Preview {
    FileTrackerView()
}
