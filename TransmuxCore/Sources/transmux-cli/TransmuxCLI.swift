import Foundation
import TransmuxCore

@main
struct TransmuxCLI {
    static func main() async {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        let inputPath = args[1]
        let inputURL: URL
        if inputPath.starts(with: "http://") || inputPath.starts(with: "https://") {
            guard let url = URL(string: inputPath) else {
                print("ERROR: Invalid URL: \(inputPath)")
                exit(1)
            }
            inputURL = url
        } else {
            inputURL = URL(fileURLWithPath: inputPath)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                print("ERROR: File not found: \(inputPath)")
                exit(1)
            }
        }

        // Parse options
        let doSeek = args.contains("--seek")
        let testSeek = args.contains("--test-seek")
        let interactive = args.contains("--interactive")
        let seekTime = (doSeek || testSeek) ? getArgValue(for: doSeek ? "--seek" : "--test-seek") ?? 300.0 : 0.0
        let duration = getArgValue(for: "--duration") ?? 10.0
        let verbose = args.contains("--verbose")

        if verbose {
            print("TransmuxCore CLI v1.2.0")
            print("Input: \(inputURL)")
            if interactive {
                print("INTERACTIVE mode: reading commands from stdin")
            } else if testSeek {
                print("TEST-SEEK mode: will seek to \(String(format: "%.1f", seekTime))s and validate logs")
            } else if doSeek {
                print("Will seek to \(String(format: "%.1f", seekTime))s for \(String(format: "%.1f", duration))s")
            }
        }

        let service = TransmuxingService()

        do {
            let session = try await service.startTransmux(from: inputURL)
            print("Transmux started: \(session.sessionID)")
            print("  Output: \(session.outputPath)")
            print("  Playlist: \(session.playlistPath)")
            print("  Init segment: \(session.initSegmentSize) bytes")
            print("  Duration: \(String(format: "%.1f", session.duration))s")

            if interactive {
                // --- Interactive mode: read stdin for SEEK/STATUS/STOP commands ---
                await runInteractive(session: session, verbose: verbose)
            } else if testSeek {
                // --- Programmatic seek test with log validation ---
                await runSeekTest(session: session, seekTarget: seekTime, verbose: verbose)
            } else if doSeek {
                // Wait for enough content before seeking (poll-based, not fixed sleep)
                let minContent = min(30.0, session.duration * 0.1)
                print("Waiting for \(String(format: "%.0f", minContent))s of content before seek...")
                let ready = await waitForContent(session: session, minSeconds: minContent, timeout: 10.0)
                if !ready {
                    print("WARNING: Timed out waiting for initial content, seeking anyway")
                }

                print("Seeking to \(String(format: "%.1f", seekTime))s...")
                session.seekHandle.requestSeek(to: seekTime)

                // Wait for seek to complete and generate segments
                try await Task.sleep(for: .seconds(duration))

                let latestTime = session.segmenter.latestTransmuxedTime()
                print("Seek test complete. Latest transmuxed time: \(String(format: "%.1f", latestTime))s")
            } else {
                print("Transmuxing for \(String(format: "%.1f", duration))s... (press Ctrl+C to stop early)")
                print("  Tip: Monitor logs with: tail -f /tmp/mks-iptv-transmux.log")

                signal(SIGINT) { _ in
                    print("\nInterrupted by user")
                    exit(0)
                }

                try await Task.sleep(for: .seconds(duration))

                let latestTime = session.segmenter.latestTransmuxedTime()
                print("Duration complete. Latest transmuxed time: \(String(format: "%.1f", latestTime))s")
            }

            await service.cleanup(sessionID: session.sessionID)
            print("Cleanup complete")

        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Interactive Mode

    /// Runs in interactive mode, reading commands from stdin line-by-line.
    /// Supported commands:
    ///   - `SEEK <seconds>` — Request a seek to the given time
    ///   - `STATUS` — Print current transmux state as JSON
    ///   - `STOP` — Graceful shutdown
    ///   - EOF on stdin — Same as STOP
    ///
    /// The remux loop continues on its own dispatch queue; `readLine()` blocks
    /// the main async thread which is fine since TransmuxCore runs independently.
    static func runInteractive(session: ProgressiveTransmuxSession, verbose: Bool) async {
        print("INTERACTIVE_READY")
        fflush(stdout)

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let upper = trimmed.uppercased()

            if upper == "STOP" {
                print("STOP received, shutting down...")
                fflush(stdout)
                break
            }

            if upper.hasPrefix("SEEK ") {
                let timeStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let time = Double(timeStr) {
                    print("SEEK_ACK \(String(format: "%.1f", time))")
                    fflush(stdout)
                    session.seekHandle.requestSeek(to: time)
                } else {
                    print("ERROR: invalid seek time '\(timeStr)'")
                    fflush(stdout)
                }
                continue
            }

            if upper == "STATUS" {
                let latestTime = session.segmenter.latestTransmuxedTime()
                let json = """
                {"latestTime":\(String(format: "%.3f", latestTime)),\
                "duration":\(String(format: "%.3f", session.duration)),\
                "sessionId":"\(session.sessionID)"}
                """
                print("STATUS_JSON \(json)")
                fflush(stdout)
                continue
            }

            print("UNKNOWN: \(trimmed)")
            fflush(stdout)
        }

        // stdin closed or STOP received
        print("Interactive session ending")
    }

    // MARK: - Seek Test

    /// Runs a programmatic seek test that validates the seek/offset logic via log analysis.
    /// 1. Waits for initial content (poll-based)
    /// 2. Issues Seek #1 and waits for completion
    /// 3. Issues Seek #2 (to a different time) and waits for completion
    /// 4. Parses log file and validates: offsets computed correctly, no errors
    static func runSeekTest(session: ProgressiveTransmuxSession, seekTarget: Double, verbose: Bool) async {
        let logPath = "/tmp/mks-iptv-transmux.log"
        // Second seek target: between first seek and end of file
        let seekTarget2 = min(seekTarget + 300, session.duration * 0.8)

        // Step 1: Wait for minimal initial content (local I/O is fast)
        print("[TEST] Step 1: Waiting for initial content...")
        let ready = await waitForContent(session: session, minSeconds: 5.0, timeout: 5.0)
        if !ready {
            print("[TEST] WARNING: Timed out waiting for initial content")
        }
        let preSeekTime = session.segmenter.latestTransmuxedTime()
        print("[TEST] Initial content ready: \(String(format: "%.1f", preSeekTime))s transmuxed")

        // Step 2: Seek #1 — immediately, don't wait
        print("[TEST] Step 2: Requesting seek to \(String(format: "%.1f", seekTarget))s...")
        session.seekHandle.requestSeek(to: seekTarget)

        let seek1Done = await waitForSeekCompletion(session: session, logPath: logPath, seekNumber: 1, timeout: 10.0)
        if !seek1Done {
            print("[TEST] WARNING: Seek #1 may not have completed within timeout")
        }
        let postSeek1Time = session.segmenter.latestTransmuxedTime()
        print("[TEST] After Seek #1: latest transmuxed time = \(String(format: "%.1f", postSeek1Time))s")

        // Step 3: Seek #2 — fire immediately after Seek #1 completes (respecting cooldown)
        print("[TEST] Step 3: Requesting seek to \(String(format: "%.1f", seekTarget2))s (after cooldown)...")
        // Wait for seek cooldown (2s in TransmuxingService)
        try? await Task.sleep(for: .milliseconds(2100))
        session.seekHandle.requestSeek(to: seekTarget2)

        let seek2Done = await waitForSeekCompletion(session: session, logPath: logPath, seekNumber: 2, timeout: 10.0)
        if !seek2Done {
            print("[TEST] WARNING: Seek #2 may not have completed within timeout")
        }
        let postSeek2Time = session.segmenter.latestTransmuxedTime()
        print("[TEST] After Seek #2: latest transmuxed time = \(String(format: "%.1f", postSeek2Time))s")

        // Step 4: Validate logs
        print("[TEST] Step 4: Validating logs...")
        validateSeekLogs(logPath: logPath, expectedSeeks: 2)
    }

    /// Poll segmenter until at least `minSeconds` of content has been transmuxed.
    static func waitForContent(session: ProgressiveTransmuxSession, minSeconds: Double, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = session.segmenter.latestTransmuxedTime()
            if current >= minSeconds {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Poll log file for "Seek #N COMPLETE" to confirm seek was processed.
    static func waitForSeekCompletion(session: ProgressiveTransmuxSession, logPath: String, seekNumber: Int, timeout: Double) async -> Bool {
        let marker = "Seek #\(seekNumber) COMPLETE"
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOfFile: logPath, encoding: .utf8) {
                if contents.contains(marker) {
                    return true
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Parse the transmux log and validate seek correctness.
    static func validateSeekLogs(logPath: String, expectedSeeks: Int) {
        guard let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            print("[TEST] FAIL: Cannot read log file at \(logPath)")
            exit(1)
        }

        let lines = contents.components(separatedBy: "\n")
        var seekCompleteCount = 0
        var offsetFromAverage = 0
        var offsetFirstVideo = 0
        var nonMonotonicCount = 0
        var writeErrors = 0
        var offsets: [Int64] = []

        for line in lines {
            if line.contains("Seek #") && line.contains("COMPLETE") {
                seekCompleteCount += 1
            }
            if line.contains("VIDEO OFFSET:") && line.contains("minPostSeekDts") {
                offsetFromAverage += 1
                // Extract offset value
                if let range = line.range(of: "offset=") {
                    let afterOffset = line[range.upperBound...]
                    // Take digits, minus sign
                    var numStr = ""
                    for ch in afterOffset {
                        if ch == "-" || ch.isNumber { numStr.append(ch) }
                        else if !numStr.isEmpty { break }
                    }
                    if let val = Int64(numStr) {
                        offsets.append(val)
                    }
                }
            }
            if line.contains("VIDEO OFFSET:") && line.contains("first video or invalid") {
                offsetFirstVideo += 1
            }
            if line.contains("NON-MONOTONIC DTS") {
                nonMonotonicCount += 1
            }
            if line.contains("write_frame ERROR") {
                writeErrors += 1
            }
        }

        // Report results
        print("")
        print("=== SEEK TEST RESULTS ===")
        print("  Seeks completed:       \(seekCompleteCount)/\(expectedSeeks)")
        print("  Offset from AVERAGE:   \(offsetFromAverage) (expected: \(expectedSeeks))")
        print("  Offset first/invalid:  \(offsetFirstVideo) (expected: 0)")
        print("  Non-monotonic DTS:     \(nonMonotonicCount) (expected: 0)")
        print("  Write frame errors:    \(writeErrors) (expected: 0)")
        if !offsets.isEmpty {
            print("  Computed offsets:      \(offsets)")
        }
        print("")

        // Determine pass/fail
        var passed = true
        var failures: [String] = []

        if seekCompleteCount < expectedSeeks {
            passed = false
            failures.append("Only \(seekCompleteCount)/\(expectedSeeks) seeks completed")
        }
        if offsetFirstVideo > 0 {
            passed = false
            failures.append("\(offsetFirstVideo) seek(s) fell back to offset=0 (lastWrittenDts was AV_NOPTS)")
        }
        if offsetFromAverage < expectedSeeks {
            passed = false
            failures.append("Only \(offsetFromAverage)/\(expectedSeeks) offsets computed from AVERAGE")
        }
        if nonMonotonicCount > 0 {
            passed = false
            failures.append("\(nonMonotonicCount) non-monotonic DTS errors (audio leak during seek)")
        }
        if writeErrors > 0 {
            passed = false
            failures.append("\(writeErrors) write_frame errors (muxer rejected packets)")
        }

        if passed {
            print("[TEST] PASS: All seek validations passed")
        } else {
            print("[TEST] FAIL:")
            for f in failures {
                print("  - \(f)")
            }
            exit(1)
        }
    }

    // MARK: - Usage

    static func printUsage() {
        print("""
        TransmuxCore CLI - FFmpeg-based container transmuxing without re-encoding

        USAGE:
            transmux-cli <input> [options]

        ARGUMENTS:
            <input>                 Input file path or HTTP(S) URL

        OPTIONS:
            --interactive           Interactive mode: read SEEK/STATUS/STOP from stdin
            --seek TIME             Seek to TIME seconds (one-shot seek during remux)
            --test-seek TIME        Run automated seek test with log validation
            --duration SECONDS      Duration to run transmux (default: 10 seconds)
            --verbose               Enable verbose output

        EXAMPLES:
            # Basic transmux for 10 seconds
            transmux-cli movie.mkv

            # Transmux for 30 seconds
            transmux-cli movie.mkv --duration 30

            # Interactive mode (used by web backend)
            transmux-cli movie.mkv --interactive --verbose

            # One-shot seek at 5 minutes
            transmux-cli movie.mkv --seek 300 --duration 20

            # Automated seek test with validation (recommended for CI)
            transmux-cli movie.mkv --test-seek 300

            # Remote URL with verbose output
            transmux-cli http://example.com/stream.mkv --verbose

        OUTPUT:
            Transmuxed files are written to /tmp/mks-iptv-transmux-<sessionID>/
            - stream.mp4: Progressive fMP4 output (growing file)
            - stream.m3u8: HLS VOD playlist (all segments declared upfront)

        For more information, see: https://github.com/MKS2508/MKS-IPTV-App
        """)
    }

    static func getArgValue(for flag: String) -> Double? {
        guard let idx = CommandLine.arguments.firstIndex(of: flag),
              idx + 1 < CommandLine.arguments.count,
              let value = Double(CommandLine.arguments[idx + 1]) else {
            return nil
        }
        return value
    }
}
