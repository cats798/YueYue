import Foundation
import SwiftUI

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var logs: [LogEntry] = []
    private let maxLogs = 200
    private let queue = DispatchQueue(label: "logmanager.queue")
    
    private struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel
    }
    
    enum LogLevel: String {
        case info = "ℹ️"
        case warning = "⚠️"
        case error = "❌"
        case success = "✅"
        case debug = "🔍"
    }
    
    private init() {}
    
    func add(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, level: level)
        queue.async { [weak self] in
            guard let self = self else { return }
            var newLogs = self.logs
            newLogs.append(entry)
            if newLogs.count > self.maxLogs {
                newLogs = Array(newLogs.suffix(self.maxLogs))
            }
            DispatchQueue.main.async {
                self.logs = newLogs
            }
        }
    }
    
    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.logs.removeAll()
            }
        }
    }
    
    func export() -> String {
        return logs.map { "\($0.timestamp.formatted()) [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}