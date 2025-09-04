import SwiftUI
import UniformTypeIdentifiers

struct DocumentReader: UIViewControllerRepresentable {
    @Binding var filePath: URL?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                UTType.movie,
                UTType.video,
                UTType.mpeg4Movie,
                UTType.quickTimeMovie,
                UTType.avi,
                UTType("public.mpeg-4")!,
                UTType("com.apple.m4v-video")!
            ],
            asCopy: true
        )
        
        documentPicker.delegate = context.coordinator
        documentPicker.allowsMultipleSelection = false
        
        return documentPicker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentReader
        
        init(_ parent: DocumentReader) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else { return }
            
            guard selectedURL.startAccessingSecurityScopedResource() else { return }
            defer { selectedURL.stopAccessingSecurityScopedResource() }
            
            do {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileName = selectedURL.lastPathComponent
                let destinationURL = documentsDirectory.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.copyItem(at: selectedURL, to: destinationURL)
                parent.filePath = destinationURL
            } catch {
                print("Error copying file: \(error)")
                parent.filePath = nil
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.filePath = nil
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var filePath: URL? = nil
        
        var body: some View {
            VStack {
                Text("Selected: \(filePath?.lastPathComponent ?? "None")")
                DocumentReader(filePath: $filePath)
            }
        }
    }
    
    return PreviewWrapper()
}
