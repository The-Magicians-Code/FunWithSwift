import SwiftUI

struct MultipleVideosView: View {
    @State private var showFileImporter = false
    @State private var selectedVideoURLs: [URL] = []

    var body: some View {
        VStack(spacing: 20) {
            if selectedVideoURLs.isEmpty {
                VStack {
                    Image(systemName: "video.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No videos selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose Videos", systemImage: "video.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Selected Videos:")
                        .font(.headline)
                    
                    ForEach(selectedVideoURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(.blue)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Add More Videos", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let files):
                files.forEach { file in
                    let gotAccess = file.startAccessingSecurityScopedResource()
                    if !gotAccess { return }
                    selectedVideoURLs.append(file)
                    file.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                print(error)
            }
        }
    }
}

#Preview {
    MultipleVideosView()
}
