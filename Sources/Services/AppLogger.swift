import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.lungusebi.focus"
    
    static let reminders = Logger(subsystem: subsystem, category: "RemindersService")
    static let timer = Logger(subsystem: subsystem, category: "TimerService")
    static let estimate = Logger(subsystem: subsystem, category: "EstimateStore")
    static let assistant = Logger(subsystem: subsystem, category: "Assistant")
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")
    static let ollama = Logger(subsystem: subsystem, category: "Ollama")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
