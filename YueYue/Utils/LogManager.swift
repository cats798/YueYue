import Foundation
import SwiftUI

@MainActor
class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var logs: [LogEntry] = []
    private let maxLogs = 200
    
    struct LogEntry: Identifiable {
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
        logs.append(entry)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
    }
    
    func clear() {
        logs.removeAll()
    }
    
    func export() -> String {
        return logs.map { "\($0.timestamp.formatted()) [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}