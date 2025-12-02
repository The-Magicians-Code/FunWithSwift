//
//  SimpleBackgroundThreadTask.swift
//  Testly
//
//  Created by Tanel Treuberg on 02/12/2025.
//

import SwiftUI

// Define this bit in a separate file
func listAllTempDirFiles() async -> [String] {
//    print("\(#function):\(Thread.isMainThread)")
    return (try? FileManager.default.contentsOfDirectory(
        at: FileManager.default.temporaryDirectory,
        includingPropertiesForKeys: nil
    ).map { $0.lastPathComponent }) ?? []
}

struct SimpleBackgroundThreadTask: View {
    @State private var files: [String] = []
    var body: some View {
        VStack {
            List(files, id: \.self) { Text($0) }
            .refreshable {
                Task(name: "Runs") {
                    files = await listAllTempDirFiles()
                }
            }
        }
        .navigationTitle("App Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SimpleBackgroundThreadTask()
}
