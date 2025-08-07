import Foundation

enum LogLevel: Int, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    var prefix: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

class Logger {
    static let shared = Logger()
    
    #if DEBUG
    private var currentLevel: LogLevel = .debug  // Changed from .info to .debug for better visibility
    #else
    private var currentLevel: LogLevel = .error
    #endif
    
    private init() {}
    
    func setLevel(_ level: LogLevel) {
        currentLevel = level
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.logMessage(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.logMessage(level: .info, message: message, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.logMessage(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.logMessage(level: .error, message: message, file: file, function: function, line: line)
    }
    
    static func log(level: LogLevel, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.logMessage(level: level, message: message, file: file, function: function, line: line)
    }
    
    private func logMessage(level: LogLevel, message: String, file: String, function: String, line: Int) {
        guard level.rawValue >= currentLevel.rawValue else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        #if DEBUG
        print("\(level.prefix) [\(timestamp)] \(fileName):\(line) \(function) - \(message)")
        #else
        if level == .error {
            print("\(level.prefix) [\(timestamp)] \(fileName):\(line) - \(message)")
        }
        #endif
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}