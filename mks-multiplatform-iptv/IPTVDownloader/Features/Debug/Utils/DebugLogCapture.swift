import Foundation
import os.log
import IPTVCore

// Captures all logs from LiveLogger and system logs
class DebugLogCapture {
    static let shared = DebugLogCapture()
    
    private var logHandler: ((String, DebugLog.LogType) -> Void)?
    private let logQueue = DispatchQueue(label: "debug.log.capture", qos: .utility)
    
    func startCapturing(handler: @escaping (String, DebugLog.LogType) -> Void) {
        logHandler = handler
        
        // We'll capture logs through console output monitoring instead
    }
    
    func stopCapturing() {
        logHandler = nil
    }
    
    func captureError(_ error: Error, context: String) {
        logQueue.async {
            let errorMessage = "❌ \(context): \(error.localizedDescription)"
            self.logHandler?(errorMessage, .error)
            
            // Extract detailed error info
            if let nsError = error as NSError? {
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    self.logHandler?("   Underlying: \(underlyingError)", .error)
                }
                if let failureReason = nsError.localizedFailureReason {
                    self.logHandler?("   Reason: \(failureReason)", .error)
                }
                if let url = nsError.userInfo["NSURL"] as? URL {
                    self.logHandler?("   URL: \(url)", .error)
                }
                if let dependencies = nsError.userInfo["AVErrorFailedDependenciesKey"] {
                    self.logHandler?("   Failed Dependencies: \(dependencies)", .error)
                }
            }
        }
    }
}

