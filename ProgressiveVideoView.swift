import SwiftUI
import PhotosUI

struct ProgressiveVideoView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Select Video", systemImage: "video.fill")
                }
                .buttonStyle(.borderedProminent)

                if isLoading {
                    ProgressView("Loading Video...")
                }
                
                if let videoURL = videoURL {
                    VStack(alignment: .leading) {
                        Text("Video Loaded!")
                            .font(.headline)
                        Text(videoURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(Color.green.opacity(0.2), in: .rect(cornerRadius: 8))
                }
              
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Video Loader")
            .onChange(of: selectedItem) { _, newItem in
                guard let item = newItem else { return }
                Task {
                    await loadVideo(from: item)
                }
            }
        }
    }

    private func loadVideo(from item: PhotosPickerItem) async {
        isLoading = true
        videoURL = nil
        errorMessage = nil
        do {
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Failed to load video data."
                isLoading = false
                return
            }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(item.supportedContentTypes.first?.preferredMIMEType ?? "mov")
          
            try videoData.write(to: tempURL)
            self.videoURL = tempURL
        } catch {
            self.errorMessage = "An error occurred: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

#Preview {
    ProgressiveVideoView()
}
