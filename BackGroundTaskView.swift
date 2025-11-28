//
//  ExampleView.swift
//
//  Created by Tanel Treuberg on 15/10/2025.
//

import SwiftUI

// Background task manager that persists across view lifecycle
@MainActor
@Observable
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    var isRunning = false
    var progress: Int = 0
    var result: Int = 0

    private var currentTask: Task<Void, Never>?

    private init() {}

    func startTask() {
        guard !isRunning else { return }

        isRunning = true
        progress = 0
        result = 0

        // Start a detached task that runs independently of view lifecycle
        currentTask = Task.detached(priority: .userInitiated) {
            var counter = 0

            while !Task.isCancelled {
                // Increment counter
                counter += 1

                // Update UI on main actor
                let currentCount = counter
                await MainActor.run {
                    BackgroundTaskManager.shared.progress = currentCount
                    BackgroundTaskManager.shared.result = currentCount
                }

                // Wait for 1 second
                try? await Task.sleep(for: .seconds(1))
            }

            // Task was cancelled
            await MainActor.run {
                BackgroundTaskManager.shared.isRunning = false
            }
        }
    }

    func cancelTask() {
        currentTask?.cancel()
        isRunning = false
    }
}

struct BackGroundTaskView: View {
    private var taskManager = BackgroundTaskManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Background Task Demo")
                .font(.title)

            if taskManager.isRunning {
                VStack(spacing: 10) {
                    Text("Task Running...")
                        .foregroundStyle(.green)

                    Text("Progress: \(taskManager.progress.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView()
                }
            } else {
                VStack(spacing: 10) {
                    Text("Task Idle")
                        .foregroundStyle(.secondary)

                    if taskManager.result > 0 {
                        Text("Last Result: \(taskManager.result.formatted())")
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 15) {
                Button(action: {
                    taskManager.startTask()
                }) {
                    Text("Start Task")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskManager.isRunning)

                Button(action: {
                    taskManager.cancelTask()
                }) {
                    Text("Cancel")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .disabled(!taskManager.isRunning)
            }

            Text("You can navigate away and return - the task continues running!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top)
        }
        .padding()
    }
}
