import Foundation

/// Intercepts stderr and suppresses known noisy Apple framework messages
/// that flood the console but have no functional impact on playback.
///
/// Filtered patterns:
/// - CMTimebase NULL errors from CoreMedia (FigTimebase.c) — cosmetic noise
///   when AVPlayer's HLS stack initializes segments with slight delivery latency.
enum StderrFilter {

    private static var originalStderr: Int32 = -1
    private static var installed = false

    /// Install the stderr filter. Safe to call multiple times (no-op after first).
    static func install() {
        guard !installed else { return }
        installed = true

        // Save original stderr fd
        originalStderr = dup(STDERR_FILENO)

        // Create a pipe: write end replaces stderr, read end is filtered
        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else { return }
        let readFD = pipeFDs[0]
        let writeFD = pipeFDs[1]

        // Redirect stderr to our pipe's write end
        dup2(writeFD, STDERR_FILENO)
        close(writeFD)

        // Background thread reads from pipe, filters, writes to original stderr
        let savedFD = originalStderr
        Thread.detachNewThread {
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            // Accumulated partial line (stderr writes may split mid-line)
            var partial = Data()

            while true {
                let bytesRead = read(readFD, buffer, bufferSize)
                guard bytesRead > 0 else { break }

                partial.append(buffer, count: bytesRead)

                // Process complete lines
                while let newlineRange = partial.range(of: Data([0x0A])) {
                    let lineData = partial[partial.startIndex..<newlineRange.upperBound]
                    partial.removeSubrange(partial.startIndex..<newlineRange.upperBound)

                    if let line = String(data: lineData, encoding: .utf8), Self.shouldSuppress(line) {
                        continue
                    }
                    // Pass through to original stderr
                    lineData.withUnsafeBytes { rawBuf in
                        _ = Darwin.write(savedFD, rawBuf.baseAddress!, rawBuf.count)
                    }
                }

                // Flush partial buffer if it's getting large (no newline yet)
                if partial.count > 8192 {
                    if let text = String(data: partial, encoding: .utf8), Self.shouldSuppress(text) {
                        partial.removeAll()
                    } else {
                        partial.withUnsafeBytes { rawBuf in
                            _ = Darwin.write(savedFD, rawBuf.baseAddress!, rawBuf.count)
                        }
                        partial.removeAll()
                    }
                }
            }

            close(readFD)
        }
    }

    private static func shouldSuppress(_ line: String) -> Bool {
        // CMTimebase NULL timebase errors from CoreMedia internals
        if line.contains("CMTimebase") && line.contains("NULL timebase") { return true }
        if line.contains("FigTimebase.c") { return true }
        // CMSync errors related to the same issue
        if line.contains("kCMSyncError_InvalidParameter") { return true }
        return false
    }
}
