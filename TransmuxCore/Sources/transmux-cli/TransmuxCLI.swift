import Foundation
import TransmuxCore

@main
struct TransmuxCLI {
    static func main() async {
        let args = CommandLine.arguments

        // --discover: standalone SSDP discovery for Cast devices (no input file needed)
        if args.contains("--discover") {
            print("TransmuxCore CLI v1.5.0 — SSDP Discovery (Cast)")
            print("")
            let timeout = Int(getArgValue(for: "--timeout") ?? 5.0)
            let devices = discoverCastDevices(timeout: timeout)
            print("")
            if devices.isEmpty {
                print("No Cast devices found.")
            } else {
                print("Found \(devices.count) device(s):")
                for (i, d) in devices.enumerated() {
                    print("  [\(i + 1)] \(d.name) (\(d.model)) — \(d.ip):\(d.port)")
                }
            }
            exit(0)
        }

        // --discover-dlna: standalone SSDP discovery for DLNA MediaRenderers (no input file needed)
        if args.contains("--discover-dlna") {
            print("TransmuxCore CLI v1.5.0 — SSDP Discovery (DLNA MediaRenderers)")
            print("")
            let timeout = Int(getArgValue(for: "--timeout") ?? 5.0)
            let devices = await discoverDLNADevices(timeout: timeout)
            print("")
            if devices.isEmpty {
                print("No DLNA MediaRenderer devices found.")
            } else {
                print("Found \(devices.count) DLNA device(s):")
                for (i, d) in devices.enumerated() {
                    print("  [\(i + 1)] \(d.friendlyName) (\(d.modelName ?? "?")) — \(d.ip):\(d.port)")
                    print("       AVTransport: \(d.avTransportControlURL)")
                    if let rc = d.renderingControlURL {
                        print("       RenderingControl: \(rc)")
                    }
                }
            }
            exit(0)
        }

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
        let serveTest = args.contains("--serve-test")
        let serve = args.contains("--serve")
        let castArg = getArgString(for: "--cast")
        let castOnly = args.contains("--cast") && castArg == nil // --cast with no argument = discover
        let castIP: String? = {
            if let arg = castArg, arg.lowercased() != "discover" {
                return arg // explicit IP
            }
            if castArg?.lowercased() == "discover" || castOnly {
                return "discover" // will trigger SSDP discovery
            }
            return nil
        }()
        let dlnaArg = getArgString(for: "--dlna")
        let dlnaOnly = args.contains("--dlna") && dlnaArg == nil // --dlna with no argument = discover
        let dlnaTarget: String? = {
            if let arg = dlnaArg, arg.lowercased() != "discover" {
                return arg // explicit IP
            }
            if dlnaArg?.lowercased() == "discover" || dlnaOnly {
                return "discover" // will trigger SSDP discovery
            }
            return nil
        }()
        let seekTime = (doSeek || testSeek) ? getArgValue(for: doSeek ? "--seek" : "--test-seek") ?? 300.0 : 0.0
        let duration = getArgValue(for: "--duration") ?? 10.0
        let verbose = args.contains("--verbose")
        let transcodeAudio = args.contains("--transcode-audio")
        let benchmark = args.contains("--benchmark")
        let benchmarkSeek = getArgValue(for: "--benchmark-seek")

        if benchmark {
            await runBenchmark(
                inputURL: inputURL,
                transcodeAudio: transcodeAudio,
                seekTarget: benchmarkSeek,
                verbose: verbose
            )
            exit(0)
        }

        if verbose {
            print("TransmuxCore CLI v1.5.0")
            print("Input: \(inputURL)")
            if let ip = castIP {
                if ip == "discover" {
                    print("CAST mode: SSDP discovery + TransmuxServer + Cast")
                } else {
                    print("CAST mode: TransmuxServer + Cast to \(ip):8009")
                }
            } else if let dlna = dlnaTarget {
                if dlna == "discover" {
                    print("DLNA mode: SSDP discovery + TransmuxServer + DLNA")
                } else {
                    print("DLNA mode: TransmuxServer + DLNA to \(dlna)")
                }
            } else if serve {
                print("SERVE mode: HTTP server + interactive seek commands")
            } else if interactive {
                print("INTERACTIVE mode: reading commands from stdin")
            } else if testSeek {
                print("TEST-SEEK mode: will seek to \(String(format: "%.1f", seekTime))s and validate logs")
            } else if doSeek {
                print("Will seek to \(String(format: "%.1f", seekTime))s for \(String(format: "%.1f", duration))s")
            }
            if transcodeAudio {
                print("Audio transcoding: AC3/EAC3/DTS → AAC (192kbps, 48kHz, stereo)")
            }
        }

        let service = TransmuxingService()

        do {
            let isCastMode = castArg != nil || castOnly

            // Cast mode: use MPEG-TS pipeline (Default Media Receiver's MPL only supports MPEG-TS)
            if isCastMode {
                let castSession = try await service.startCastTransmux(from: inputURL, transcodeAudio: transcodeAudio)
                print("Cast transmux started: \(castSession.sessionID)")
                print("  Output dir: \(castSession.outputDir)")
                print("  Playlist: \(castSession.playlistPath)")
                print("  Duration: \(String(format: "%.1f", castSession.duration))s")
                print("  Format: HLS + MPEG-TS (Cast compatible)")

                if castSession.audioTracks.isEmpty {
                    print("  Audio tracks: none")
                } else {
                    for (i, a) in castSession.audioTracks.enumerated() {
                        print("  Audio [\(i)]: \(a.codecName) \(a.channels)ch \(a.sampleRate)Hz lang=\(a.language)")
                    }
                }

                await runCastMPEGTS(session: castSession, castIP: castIP!, verbose: verbose)
                await service.cleanup(sessionID: castSession.sessionID)
                print("Cleanup complete")
                exit(0)
            }

            // DLNA mode: transmux to fMP4, serve via TransmuxServer with DLNA headers,
            // send SetAVTransportURI to the DLNA TV which pulls content via HTTP range requests
            let isDLNAMode = dlnaArg != nil || dlnaOnly
            if isDLNAMode {
                await runDLNA(
                    inputURL: inputURL,
                    dlnaTarget: dlnaTarget!,
                    service: service,
                    verbose: verbose,
                    transcodeAudio: transcodeAudio
                )
                exit(0)
            }

            let session = try await service.startTransmux(from: inputURL, transcodeAudio: transcodeAudio)
            print("Transmux started: \(session.sessionID)")
            print("  Output: \(session.outputPath)")
            print("  Playlist: \(session.playlistPath)")
            print("  Init segment: \(session.initSegmentSize) bytes")
            print("  Duration: \(String(format: "%.1f", session.duration))s")

            // Print discovered audio tracks
            if session.audioTracks.isEmpty {
                print("  Audio tracks: none")
            } else {
                print("  Audio tracks (\(session.audioTracks.count)):")
                for (i, a) in session.audioTracks.enumerated() {
                    let def = a.isDefault ? " [DEFAULT]" : ""
                    print("    [\(i)] in:\(a.inputStreamIndex)→out:\(a.outputStreamIndex) \(a.codecName) \(a.channels)ch \(a.sampleRate)Hz lang=\(a.language) title=\"\(a.title)\"\(def)")
                }
            }

            // Print discovered subtitle tracks
            if session.subtitleTracks.isEmpty {
                print("  Subtitle tracks: none")
            } else {
                print("  Subtitle tracks (\(session.subtitleTracks.count)):")
                for (i, s) in session.subtitleTracks.enumerated() {
                    let forced = s.isForced ? " [FORCED]" : ""
                    print("    [\(i)] lang=\(s.language) title=\"\(s.title)\" vtt=\(s.vttFileName)\(forced)")
                }
            }

            if serve {
                // --- Serve mode: HTTP server + interactive seek commands ---
                await runServe(session: session, verbose: verbose)
            } else if serveTest {
                // --- Server test mode: starts TransmuxServer and simulates segment requests ---
                await runServeTest(session: session, verbose: verbose)
            } else if interactive {
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

    // MARK: - Serve Mode (Interactive Server)

    /// Starts TransmuxServer and enters an interactive command loop.
    /// The server stays running until the user types STOP/QUIT or presses Ctrl+C.
    /// Point AVPlayer, HLS.js, or a browser at the printed URL to stream.
    ///
    /// Commands:
    ///   SEEK <seconds>   — Seek the transmux pipeline to the given source time
    ///   STATUS           — Print current state (buffered time, segments, server port)
    ///   SEGMENTS [N]     — List the last N real segments (default 10)
    ///   TFDT <seg>       — Fetch a segment via HTTP and dump its tfdt values
    ///   LOG [N]          — Print last N lines from the transmux log (default 30)
    ///   STOP / QUIT      — Shutdown server and exit
    static func runServe(session: ProgressiveTransmuxSession, verbose: Bool) async {
        print("[SERVE] Waiting for initial content...")
        let ready = await waitForContent(session: session, minSeconds: 12.0, timeout: 20.0)
        if !ready {
            print("[SERVE] WARNING: Timed out waiting for 12s of content, starting server anyway")
        }
        let initialTime = session.segmenter.latestBufferedSourceTime()
        print("[SERVE] Initial content ready: \(String(format: "%.1f", initialTime))s buffered")

        // Start TransmuxServer
        do {
            let serverSession = try await TransmuxServer.shared.start(
                filePath: session.outputPath,
                playlistPath: session.playlistPath,
                mediaPlaylistPath: session.mediaPlaylistPath,
                expectedSize: session.expectedSize,
                segmenter: session.segmenter,
                initSegmentSize: session.initSegmentSize,
                seekHandle: session.seekHandle
            )
            let baseURL = serverSession.localURL.absoluteString
                .replacingOccurrences(of: "/master.m3u8", with: "")
                .replacingOccurrences(of: "/stream.m3u8", with: "")

            print("")
            print("=========================================")
            print("  TransmuxServer running on port \(serverSession.port)")
            print("")
            print("  Entry URL: \(serverSession.localURL)")
            print("  Init seg:  \(baseURL)/init.mp4")
            print("  Segments:  \(baseURL)/seg_000.mp4 ... seg_\(String(format: "%03d", session.segmenter.totalSegmentCount - 1)).mp4")
            print("  Duration:  \(String(format: "%.1f", session.duration))s (\(session.segmenter.totalSegmentCount) virtual segments)")
            print("  Audio:     \(session.audioTracks.count) track(s)")
            print("  Subtitles: \(session.subtitleTracks.count) track(s)")
            print("")

            // Print master playlist content for debugging
            if session.audioTracks.count > 1 || !session.subtitleTracks.isEmpty {
                let masterPath = (session.mediaPlaylistPath as NSString).deletingLastPathComponent + "/master.m3u8"
                if let masterContent = try? String(contentsOfFile: masterPath, encoding: .utf8) {
                    print("  Master playlist (master.m3u8):")
                    for line in masterContent.components(separatedBy: "\n") {
                        print("    \(line)")
                    }
                    print("")
                }
            }

            print("  Log file:  /tmp/mks-iptv-transmux.log")
            print("  Tail logs: tail -f /tmp/mks-iptv-transmux.log")
            print("")
            print("  Commands: SEEK <s> | STATUS | SEGMENTS [N] | TFDT <seg> | LOG [N] | STOP")
            print("=========================================")
            print("")

            // Handle Ctrl+C — just exit (same as other CLI modes).
            // Server cleanup happens via OS process teardown.
            signal(SIGINT) { _ in
                print("\n[SERVE] Interrupted — exiting")
                exit(0)
            }

            // Interactive command loop
            print("> ", terminator: "")
            fflush(stdout)

            while let line = readLine() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    print("> ", terminator: "")
                    fflush(stdout)
                    continue
                }

                let parts = trimmed.split(separator: " ", maxSplits: 1)
                let cmd = String(parts[0]).uppercased()

                switch cmd {
                case "STOP", "QUIT", "EXIT", "Q":
                    print("[SERVE] Shutting down...")
                    await TransmuxServer.shared.stop()
                    return

                case "SEEK":
                    guard parts.count > 1, let time = Double(parts[1]) else {
                        print("[SERVE] Usage: SEEK <seconds>")
                        break
                    }
                    guard time >= 0, time <= session.duration else {
                        print("[SERVE] Out of range. Duration is \(String(format: "%.1f", session.duration))s")
                        break
                    }
                    let bufferedBefore = session.segmenter.latestBufferedSourceTime()
                    print("[SERVE] Seeking to \(String(format: "%.1f", time))s (currently buffered: \(String(format: "%.1f", bufferedBefore))s)")
                    session.seekHandle.requestSeek(to: time)

                    // Poll for seek completion (check log for SEEK OK marker)
                    let seekDone = await waitForSeekInLog(timeout: 12.0)
                    let bufferedAfter = session.segmenter.latestBufferedSourceTime()
                    if seekDone {
                        print("[SERVE] Seek complete. Buffered: \(String(format: "%.1f", bufferedAfter))s")
                    } else {
                        print("[SERVE] Seek may still be processing. Buffered: \(String(format: "%.1f", bufferedAfter))s")
                    }

                    // Show post-seek tfdt log entries
                    printRecentTfdtLogs(lastN: 15)

                case "STATUS":
                    let buffered = session.segmenter.latestBufferedSourceTime()
                    let transmuxed = session.segmenter.latestTransmuxedTime()
                    let seekGen = session.seekHandle.seekGeneration
                    let lastSeek = session.seekHandle.lastSeekTarget
                    let complete = session.seekHandle.isTransmuxComplete
                    print("[STATUS]")
                    print("  Buffered source time: \(String(format: "%.3f", buffered))s")
                    print("  Latest transmuxed:    \(String(format: "%.3f", transmuxed))s")
                    print("  Total duration:       \(String(format: "%.1f", session.duration))s")
                    print("  Seek generation:      \(seekGen)")
                    if let ls = lastSeek {
                        print("  Last seek target:     \(String(format: "%.1f", ls))s")
                    }
                    print("  Transmux complete:    \(complete)")
                    print("  Server URL:           \(serverSession.localURL)")

                case "SEGMENTS", "SEGS":
                    let count = parts.count > 1 ? (Int(parts[1]) ?? 10) : 10
                    printSegmentInfo(session: session, lastN: count)

                case "TFDT":
                    guard parts.count > 1, let segIdx = Int(parts[1]) else {
                        print("[SERVE] Usage: TFDT <segment_index>")
                        break
                    }
                    await fetchAndDumpTfdt(baseURL: baseURL, segIndex: segIdx, segmenter: session.segmenter)

                case "LOG":
                    let count = parts.count > 1 ? (Int(parts[1]) ?? 30) : 30
                    printRecentLog(lastN: count)

                case "HELP", "?":
                    print("Commands:")
                    print("  SEEK <seconds>   Seek transmux pipeline to source time")
                    print("  STATUS           Show current state")
                    print("  SEGMENTS [N]     List last N real segments (default 10)")
                    print("  TFDT <seg>       Fetch segment via HTTP, dump tfdt values")
                    print("  LOG [N]          Print last N log lines (default 30)")
                    print("  STOP             Shutdown and exit")

                default:
                    print("[SERVE] Unknown command: \(trimmed). Type HELP for commands.")
                }

                print("> ", terminator: "")
                fflush(stdout)
            }

            // stdin closed
            print("[SERVE] stdin closed — shutting down...")
            await TransmuxServer.shared.stop()

        } catch {
            print("[SERVE] ERROR starting server: \(error.localizedDescription)")
        }
    }

    /// Wait for the latest "SEEK #N OK" line to appear in the log.
    static func waitForSeekInLog(timeout: Double) async -> Bool {
        let logPath = "/tmp/mks-iptv-transmux.log"
        // Snapshot current SEEK OK count
        let initialCount: Int
        if let contents = try? String(contentsOfFile: logPath, encoding: .utf8) {
            initialCount = contents.components(separatedBy: " OK vOff=").count - 1
        } else {
            initialCount = 0
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOfFile: logPath, encoding: .utf8) {
                let currentCount = contents.components(separatedBy: " OK vOff=").count - 1
                if currentCount > initialCount {
                    return true
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Print recent tfdt-related log lines for post-seek analysis.
    static func printRecentTfdtLogs(lastN: Int) {
        let logPath = "/tmp/mks-iptv-transmux.log"
        guard let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else { return }
        let lines = contents.components(separatedBy: "\n")
        let tfdtLines = lines.filter { $0.contains("tfdt ") || $0.contains("POST-SEEK") || $0.contains("SEEK #") }
        let recent = tfdtLines.suffix(lastN)
        if !recent.isEmpty {
            print("[TFDT LOG] Last \(recent.count) tfdt/seek entries:")
            for line in recent {
                print("  \(line)")
            }
        }
    }

    /// Print info about the last N real segments discovered by the segmenter.
    static func printSegmentInfo(session: ProgressiveTransmuxSession, lastN: Int) {
        let targetDuration = session.segmenter.targetSegmentDuration
        let allFragments = session.segmenter.realSegments(inTimeRange: 0, end: session.duration + 60)
        let total = allFragments.count
        let display = Array(allFragments.suffix(lastN))

        print("[SEGMENTS] \(total) real fragments total (showing last \(display.count)):")
        print("  idx    srcTime      virt_seg     bytes")
        for (i, frag) in display.enumerated() {
            let globalIdx = total - display.count + i
            let virtSeg = Int(frag.sourceStartTime / targetDuration)
            let srcTime = String(format: "%.3f", frag.sourceStartTime) + "s"
            let segName = "seg_\(String(format: "%03d", virtSeg))"
            print("  \(globalIdx)\t \(srcTime)\t \(segName)\t \(frag.length)B")
        }
    }

    /// Fetch a segment via HTTP and parse/dump the tfdt values from its moof boxes.
    static func fetchAndDumpTfdt(baseURL: String, segIndex: Int, segmenter: HLSSegmenter) async {
        let path = "/seg_\(String(format: "%03d", segIndex)).mp4"
        print("[TFDT] Fetching \(path)...")

        guard let data = await fetchSegment(baseURL: baseURL, path: path) else {
            print("[TFDT] Failed to fetch segment (404 or error)")
            return
        }
        print("[TFDT] Got \(data.count) bytes. Parsing moof boxes...")

        // Walk top-level boxes to find moof, then parse traf→{tfhd, tfdt}
        var pos = 0
        var fragCount = 0
        while pos + 8 <= data.count {
            guard let box = readBoxHeader(data: data, at: pos) else { break }
            let boxSize = Int(box.size)
            if boxSize < 8 { break }
            let boxEnd = pos + boxSize
            if boxEnd > data.count { break }

            if box.type == "moof" {
                fragCount += 1
                // Parse moof children for traf
                var child = pos + 8
                while child + 8 <= boxEnd {
                    guard let childBox = readBoxHeader(data: data, at: child) else { break }
                    let childSize = Int(childBox.size)
                    if childSize < 8 { break }
                    let childEnd = child + childSize
                    if childEnd > boxEnd { break }

                    if childBox.type == "traf" {
                        parseTrafForDump(data: data, trafStart: child, trafEnd: childEnd, timescales: segmenter.trackTimescales)
                    }
                    child = childEnd
                }
            }
            pos = boxEnd
        }
        print("[TFDT] \(fragCount) moof boxes in segment")
    }

    /// Parse a single traf and print track_ID + tfdt info.
    private static func parseTrafForDump(data: Data, trafStart: Int, trafEnd: Int, timescales: [UInt32: UInt32]) {
        var trackID: UInt32?
        var tfdtValue: UInt64?
        var tfdtVersion: UInt8?

        var offset = trafStart + 8
        while offset + 8 <= trafEnd {
            guard let box = readBoxHeader(data: data, at: offset) else { break }
            let boxSize = Int(box.size)
            if boxSize < 8 { break }
            let boxEnd = offset + boxSize
            if boxEnd > trafEnd { break }

            if box.type == "tfhd" {
                let idOffset = offset + 8 + 4
                if idOffset + 4 <= boxEnd {
                    trackID = data.withUnsafeBytes { ptr in
                        ptr.loadUnaligned(fromByteOffset: idOffset, as: UInt32.self).bigEndian
                    }
                }
            } else if box.type == "tfdt" {
                let vOffset = offset + 8
                if vOffset + 4 <= boxEnd {
                    tfdtVersion = data[vOffset]
                    if tfdtVersion == 1, vOffset + 4 + 8 <= boxEnd {
                        tfdtValue = data.withUnsafeBytes { ptr in
                            ptr.loadUnaligned(fromByteOffset: vOffset + 4, as: UInt64.self).bigEndian
                        }
                    } else if vOffset + 4 + 4 <= boxEnd {
                        tfdtValue = UInt64(data.withUnsafeBytes { ptr in
                            ptr.loadUnaligned(fromByteOffset: vOffset + 4, as: UInt32.self).bigEndian
                        })
                    }
                }
            }
            offset = boxEnd
        }

        if let tid = trackID, let tfdt = tfdtValue {
            let ts = timescales[tid] ?? 90000
            let seconds = Double(tfdt) / Double(ts)
            print("  track=\(tid) tfdt=\(tfdt) ts=\(ts) -> \(String(format: "%.3f", seconds))s (v\(tfdtVersion ?? 0))")
        }
    }

    /// Minimal box header reader for segment parsing (same logic as MP4BoxParser).
    private static func readBoxHeader(data: Data, at offset: Int) -> (size: Int64, type: String)? {
        guard offset + 8 <= data.count else { return nil }
        let size32 = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
        }
        let typeBytes = data.subdata(in: (offset + 4)..<(offset + 8))
        let type = String(bytes: typeBytes, encoding: .ascii) ?? "????"
        return (Int64(size32), type)
    }

    /// Print last N lines from the transmux log file.
    static func printRecentLog(lastN: Int) {
        let logPath = "/tmp/mks-iptv-transmux.log"
        guard let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            print("[LOG] Cannot read \(logPath)")
            return
        }
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        let recent = Array(lines.suffix(lastN))
        print("[LOG] Last \(recent.count) lines:")
        for line in recent {
            print("  \(line)")
        }
    }

    // MARK: - Serve Test

    /// Starts TransmuxServer alongside the transmux pipeline and simulates
    /// segment requests via URLSession. Tests cache hits, mmap reads, and prefetch.
    ///
    /// Flow:
    /// 1. Wait for transmux to produce some data
    /// 2. Start TransmuxServer on localhost
    /// 3. Request segments sequentially (tests mmap + prefetch)
    /// 4. Re-request same segments (tests cache hits)
    /// 5. Request far-ahead segment (tests seek + polling)
    /// 6. Report results from log
    static func runServeTest(session: ProgressiveTransmuxSession, verbose: Bool) async {
        print("[SERVE-TEST] Starting server test...")

        // Step 1: Wait for initial content
        print("[SERVE-TEST] Step 1: Waiting for initial content...")
        let ready = await waitForContent(session: session, minSeconds: 30.0, timeout: 15.0)
        if !ready {
            print("[SERVE-TEST] WARNING: Timed out waiting for 30s of content")
        }
        let initialTime = session.segmenter.latestBufferedSourceTime()
        print("[SERVE-TEST] Initial content ready: \(String(format: "%.1f", initialTime))s buffered")

        // Step 2: Start TransmuxServer
        print("[SERVE-TEST] Step 2: Starting TransmuxServer...")
        do {
            let serverSession = try await TransmuxServer.shared.start(
                filePath: session.outputPath,
                playlistPath: session.playlistPath,
                mediaPlaylistPath: session.mediaPlaylistPath,
                expectedSize: session.expectedSize,
                segmenter: session.segmenter,
                initSegmentSize: session.initSegmentSize,
                seekHandle: session.seekHandle
            )
            let baseURL = serverSession.localURL.absoluteString
                .replacingOccurrences(of: "/master.m3u8", with: "")
                .replacingOccurrences(of: "/stream.m3u8", with: "")
            print("[SERVE-TEST] Server started at \(baseURL)")

            // Step 3: Request init segment
            print("[SERVE-TEST] Step 3: Requesting init.mp4...")
            let initData = await fetchSegment(baseURL: baseURL, path: "/init.mp4")
            print("[SERVE-TEST]   init.mp4: \(initData?.count ?? 0) bytes")

            // Step 4: Request first 5 segments sequentially (tests mmap + prefetch)
            print("[SERVE-TEST] Step 4: Requesting segments 0-4 (first serve — mmap + prefetch)...")
            var firstServeBytes: [Int] = []
            for i in 0..<5 {
                let segPath = "/seg_\(String(format: "%03d", i)).mp4"
                let data = await fetchSegment(baseURL: baseURL, path: segPath)
                let bytes = data?.count ?? 0
                firstServeBytes.append(bytes)
                print("[SERVE-TEST]   seg_\(String(format: "%03d", i)): \(bytes) bytes")
            }

            // Step 5: Re-request same segments (should hit cache)
            print("[SERVE-TEST] Step 5: Re-requesting segments 0-4 (expect cache hits)...")
            var cacheServeBytes: [Int] = []
            for i in 0..<5 {
                let segPath = "/seg_\(String(format: "%03d", i)).mp4"
                let data = await fetchSegment(baseURL: baseURL, path: segPath)
                let bytes = data?.count ?? 0
                cacheServeBytes.append(bytes)
                print("[SERVE-TEST]   seg_\(String(format: "%03d", i)): \(bytes) bytes")
            }

            // Step 6: Request a far-ahead segment (tests seek or immediate from already-produced data)
            let farSegIndex = 100  // ~600s into a 6s segment file
            print("[SERVE-TEST] Step 6: Requesting far segment seg_\(String(format: "%03d", farSegIndex))...")
            let farData = await fetchSegment(baseURL: baseURL, path: "/seg_\(String(format: "%03d", farSegIndex)).mp4")
            print("[SERVE-TEST]   seg_\(String(format: "%03d", farSegIndex)): \(farData?.count ?? 0) bytes")

            // Step 7: Re-request far segment (should hit cache)
            print("[SERVE-TEST] Step 7: Re-requesting far segment (expect cache hit)...")
            let farCacheData = await fetchSegment(baseURL: baseURL, path: "/seg_\(String(format: "%03d", farSegIndex)).mp4")
            print("[SERVE-TEST]   seg_\(String(format: "%03d", farSegIndex)): \(farCacheData?.count ?? 0) bytes")

            // Wait a moment for logs to flush
            try? await Task.sleep(for: .milliseconds(500))

            // Step 8: Analyze logs
            print("")
            print("[SERVE-TEST] === RESULTS ===")
            analyzeServeLogs()

            // Verify data integrity
            print("")
            print("[SERVE-TEST] === DATA INTEGRITY ===")
            var allMatch = true
            for i in 0..<5 {
                let match = firstServeBytes[i] == cacheServeBytes[i]
                if !match { allMatch = false }
                print("  seg_\(String(format: "%03d", i)): first=\(firstServeBytes[i])B cache=\(cacheServeBytes[i])B \(match ? "OK" : "MISMATCH")")
            }
            print("  All segments match: \(allMatch ? "YES" : "NO")")

            // Stop server
            await TransmuxServer.shared.stop()
            print("")
            print("[SERVE-TEST] Server stopped. Test complete.")

        } catch {
            print("[SERVE-TEST] ERROR: \(error.localizedDescription)")
        }
    }

    /// Fetch a segment from the local TransmuxServer.
    static func fetchSegment(baseURL: String, path: String) async -> Data? {
        guard let url = URL(string: baseURL + path) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    print("[SERVE-TEST]   HTTP \(httpResponse.statusCode) for \(path)")
                    return nil
                }
            }
            return data
        } catch {
            print("[SERVE-TEST]   ERROR fetching \(path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse the transmux log and report segment serve statistics.
    static func analyzeServeLogs() {
        let logPath = "/tmp/mks-iptv-transmux.log"
        guard let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            print("  Cannot read log file")
            return
        }

        let lines = contents.components(separatedBy: "\n")
        var sourceCounts: [String: Int] = [:]
        var totalServes = 0

        for line in lines {
            // Match segment served lines with source=
            if line.contains("[Segment]") && line.contains("source=") {
                totalServes += 1
                // Extract source value
                if let range = line.range(of: "source=") {
                    let afterSource = line[range.upperBound...]
                    let source = String(afterSource.prefix(while: { $0 != " " && $0 != "," && $0 != "]" }))
                    sourceCounts[source, default: 0] += 1
                }
            }
        }

        print("  Total segment serves: \(totalServes)")
        for (source, count) in sourceCounts.sorted(by: { $0.key < $1.key }) {
            print("    \(source): \(count)")
        }

        // Check for cache hits specifically
        let cacheHits = sourceCounts["cache-hit"] ?? 0
        print("")
        print("  Cache hits: \(cacheHits)")
        print("  Cache hit rate: \(totalServes > 0 ? String(format: "%.0f", Double(cacheHits) / Double(totalServes) * 100) : "0")%")

        // Check for errors
        let errors = lines.filter { $0.contains("write_frame ERROR") }.count
        print("  Write errors: \(errors)")
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

    /// Poll log file for "SEEK #N OK" to confirm seek was processed.
    static func waitForSeekCompletion(session: ProgressiveTransmuxSession, logPath: String, seekNumber: Int, timeout: Double) async -> Bool {
        let marker = "SEEK #\(seekNumber) OK"
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
            if line.contains("SEEK #") && line.contains(" OK ") {
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
            --discover              Scan LAN for Cast devices via SSDP (no input file needed)
            --discover-dlna         Scan LAN for DLNA MediaRenderers via SSDP (no input file needed)
            --timeout SECONDS       Discovery timeout (default: 5, used with --discover/--discover-dlna)
            --serve                 Start HTTP server + interactive command loop for manual testing
            --cast [IP|discover]    Start HTTP server + connect to Chromecast + LOAD
                                    Without IP or with 'discover': auto-discover via SSDP
                                    With IP: connect directly to that address on port 8009
            --dlna [IP|discover]    Transmux + serve via HTTP + DLNA playback on TV
                                    Without IP or with 'discover': auto-discover DLNA devices
                                    With IP: connect directly (tries common ports/paths)
            --interactive           Interactive mode: read SEEK/STATUS/STOP from stdin (no HTTP server)
            --serve-test            Automated server test: fetch segments, verify cache/mmap/prefetch
            --seek TIME             Seek to TIME seconds (one-shot seek during remux)
            --test-seek TIME        Run automated seek test with log validation
            --duration SECONDS      Duration to run transmux (default: 10 seconds)
            --transcode-audio       Transcode AC3/EAC3/DTS audio to AAC (192kbps, 48kHz, stereo)
                                    Use with --cast or --dlna for devices that don't support AC3/DTS
            --benchmark             Run performance benchmark: measures open time, first segment,
                                    throughput (MB/s), total remux time, peak memory
            --benchmark-seek TIME   Include seek latency measurement at TIME seconds in benchmark
            --verbose               Enable verbose output

        EXAMPLES:
            # Interactive server mode — start HTTP server, seek manually, inspect logs
            transmux-cli movie.mkv --serve --verbose

            # Cast to Chromecast — auto-discover device on LAN
            transmux-cli movie.mkv --cast --verbose

            # Cast to Chromecast — explicit discovery
            transmux-cli movie.mkv --cast discover --verbose

            # Cast to Chromecast — direct IP (skip discovery)
            transmux-cli movie.mkv --cast 192.168.1.128 --verbose

            # DLNA playback on TV — auto-discover
            transmux-cli movie.mkv --dlna --verbose

            # DLNA playback — direct IP (e.g. TELEFUNKEN at 192.168.1.142)
            transmux-cli movie.mkv --dlna 192.168.1.142 --verbose

            # DLNA with audio transcoding (AC3/DTS → AAC for TV compatibility)
            transmux-cli movie.mkv --dlna 192.168.1.142 --transcode-audio --verbose

            # Benchmark: full file remux performance
            transmux-cli movie.mkv --benchmark

            # Benchmark with seek latency measurement
            transmux-cli movie.mkv --benchmark --benchmark-seek 300

            # Benchmark with audio transcoding to measure Tier 1 overhead
            transmux-cli movie.mkv --benchmark --transcode-audio

            # Cast with audio transcoding (AC3/DTS → AAC for Chromecast)
            transmux-cli movie.mkv --cast --transcode-audio --verbose

            # Discover DLNA devices only (no playback)
            transmux-cli --discover-dlna

            # Same, with a remote MKV
            transmux-cli "http://iptv.example.com/movie.mkv" --serve --verbose

            # Basic transmux for 10 seconds
            transmux-cli movie.mkv

            # Transmux for 30 seconds
            transmux-cli movie.mkv --duration 30

            # Full server test with cache/mmap/prefetch validation
            transmux-cli movie.mkv --serve-test --verbose

            # Interactive mode (used by web backend, no HTTP server)
            transmux-cli movie.mkv --interactive --verbose

            # One-shot seek at 5 minutes
            transmux-cli movie.mkv --seek 300 --duration 20

            # Automated seek test with validation (recommended for CI)
            transmux-cli movie.mkv --test-seek 300

        SERVE MODE COMMANDS:
            SEEK <seconds>          Seek transmux pipeline to source time
            STATUS                  Show buffered time, seek generation, server URL
            SEGMENTS [N]            List last N real segments (default 10)
            TFDT <segment_index>    Fetch segment via HTTP, dump tfdt decode times
            LOG [N]                 Print last N transmux log lines (default 30)
            STOP / QUIT             Shutdown server and exit

        CAST MODE COMMANDS:
            LOAD [url]              (Re)load media on Chromecast (default: server URL)
            PLAY                    Resume playback
            PAUSE                   Pause playback
            STOP                    Stop media
            SEEK <seconds>          Seek to position
            STATUS                  Get media status from device
            QUIT                    Disconnect and exit

        DLNA MODE COMMANDS:
            PLAY                    Resume playback
            PAUSE                   Pause playback
            STOP                    Stop media
            SEEK <seconds>          Seek to position (REL_TIME)
            STATUS                  Get position + transport state
            VOLUME <0-100>          Set volume (if RenderingControl available)
            LOAD [url]              (Re)load content on the TV
            QUIT                    Stop and exit

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

    static func getArgString(for flag: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: flag),
              idx + 1 < CommandLine.arguments.count else {
            return nil
        }
        let val = CommandLine.arguments[idx + 1]
        // Don't return the next flag as a value
        if val.hasPrefix("--") { return nil }
        return val
    }

    // MARK: - Benchmark Mode

    /// Runs a comprehensive performance benchmark of the TransmuxCore pipeline.
    /// Measures: open time, time to first segment, throughput, seek latency, peak memory.
    /// Outputs structured results for v1 baseline comparison.
    static func runBenchmark(
        inputURL: URL,
        transcodeAudio: Bool,
        seekTarget: Double?,
        verbose: Bool
    ) async {
        let service = TransmuxingService()
        let isLocalFile = inputURL.isFileURL
        var inputFileSize: Int64 = 0
        if isLocalFile,
           let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path),
           let size = attrs[.size] as? Int64 {
            inputFileSize = size
        }

        print(String(repeating: "=", count: 60))
        print("TransmuxCore v1 — Performance Benchmark")
        print(String(repeating: "=", count: 60))
        print("")
        print("Input: \(inputURL.lastPathComponent)")
        if inputFileSize > 0 {
            print("Input size: \(formatBytes(inputFileSize))")
        }
        print("Audio transcode: \(transcodeAudio ? "ON (AC3/EAC3/DTS → AAC)" : "OFF (passthrough)")")
        if let seek = seekTarget {
            print("Seek test: \(String(format: "%.1f", seek))s")
        }
        print("")

        // --- Phase 1: Open + Stream Analysis ---
        print("--- Phase 1: Open + Stream Analysis ---")
        let t0 = CFAbsoluteTimeGetCurrent()

        let session: ProgressiveTransmuxSession
        do {
            session = try await service.startTransmux(from: inputURL, transcodeAudio: transcodeAudio)
        } catch {
            print("ERROR: Failed to start transmux: \(error.localizedDescription)")
            return
        }

        let tStarted = CFAbsoluteTimeGetCurrent()
        let openTime = tStarted - t0

        print("  Open + start: \(String(format: "%.3f", openTime))s")
        print("  Duration: \(String(format: "%.1f", session.duration))s")
        print("  Init segment: \(formatBytes(session.initSegmentSize))")
        print("  Audio tracks: \(session.audioTracks.count)")
        for (i, a) in session.audioTracks.enumerated() {
            print("    [\(i)] \(a.codecName) \(a.channels)ch \(a.sampleRate)Hz lang=\(a.language)")
        }
        print("  Subtitle tracks: \(session.subtitleTracks.count)")
        print("")

        // --- Phase 2: Time to First Segment ---
        print("--- Phase 2: Time to First Segment ---")
        let tFirstSegStart = CFAbsoluteTimeGetCurrent()
        var firstSegTime: Double = 0
        let firstSegDeadline = Date().addingTimeInterval(30.0)
        while Date() < firstSegDeadline {
            let buffered = session.segmenter.latestTransmuxedTime()
            if buffered > 0 {
                firstSegTime = CFAbsoluteTimeGetCurrent() - tFirstSegStart
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        if firstSegTime > 0 {
            print("  First segment: \(String(format: "%.3f", firstSegTime))s")
        } else {
            print("  First segment: TIMEOUT (30s)")
        }
        print("")

        // --- Phase 3: Full Remux Throughput ---
        print("--- Phase 3: Full Remux Throughput ---")
        print("  Waiting for full remux to complete...")

        // Sample progress every 500ms for throughput curve
        var progressSamples: [(time: Double, buffered: Double)] = []
        let tRemuxStart = CFAbsoluteTimeGetCurrent()
        let remuxDeadline = Date().addingTimeInterval(max(session.duration * 3, 120.0)) // generous timeout

        while Date() < remuxDeadline {
            if session.seekHandle.isTransmuxComplete {
                break
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - tRemuxStart
            let buffered = session.segmenter.latestTransmuxedTime()
            progressSamples.append((time: elapsed, buffered: buffered))

            if verbose && progressSamples.count % 10 == 0 {
                let ratio = buffered / max(elapsed, 0.001)
                print("    [\(String(format: "%5.1f", elapsed))s] buffered: \(String(format: "%.1f", buffered))s (\(String(format: "%.1f", ratio))x realtime)")
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        let tRemuxEnd = CFAbsoluteTimeGetCurrent()
        let totalRemuxTime = tRemuxEnd - tRemuxStart
        let finalBuffered = session.segmenter.latestTransmuxedTime()
        let remuxComplete = session.seekHandle.isTransmuxComplete

        // Get output file size
        var outputFileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: session.outputPath),
           let size = attrs[.size] as? Int64 {
            outputFileSize = size
        }

        let realtimeRatio = finalBuffered / max(totalRemuxTime, 0.001)
        let throughputMBps = Double(outputFileSize) / (1024 * 1024) / max(totalRemuxTime, 0.001)

        print("  Completed: \(remuxComplete ? "YES" : "NO (timeout)")")
        print("  Total remux time: \(String(format: "%.3f", totalRemuxTime))s")
        print("  Content duration: \(String(format: "%.1f", finalBuffered))s")
        print("  Realtime ratio: \(String(format: "%.1f", realtimeRatio))x")
        print("  Output size: \(formatBytes(outputFileSize))")
        print("  Throughput: \(String(format: "%.1f", throughputMBps)) MB/s")
        if inputFileSize > 0 {
            let ratio = Double(outputFileSize) / Double(inputFileSize) * 100
            print("  Size ratio: \(String(format: "%.1f", ratio))% of input")
        }
        print("")

        // --- Phase 4: Seek Latency (optional) ---
        var seekLatency: Double? = nil
        if let seekTo = seekTarget, seekTo < session.duration {
            print("--- Phase 4: Seek Latency ---")
            print("  Seeking to \(String(format: "%.1f", seekTo))s...")

            let tSeekStart = CFAbsoluteTimeGetCurrent()
            session.seekHandle.requestSeek(to: seekTo)

            // Wait for post-seek content to appear
            let preSeekBuffered = session.segmenter.latestTransmuxedTime()
            let seekDeadline = Date().addingTimeInterval(15.0)
            var seekDone = false
            while Date() < seekDeadline {
                let current = session.segmenter.latestTransmuxedTime()
                // Seek is "done" when new content appears near the seek target
                if current != preSeekBuffered {
                    seekLatency = CFAbsoluteTimeGetCurrent() - tSeekStart
                    seekDone = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }

            if seekDone, let lat = seekLatency {
                print("  Seek latency: \(String(format: "%.3f", lat))s")
            } else {
                print("  Seek latency: TIMEOUT (15s)")
            }
            print("")
        }

        // --- Phase 5: Memory ---
        print("--- Phase 5: Memory Usage ---")
        let memInfo = getMemoryUsage()
        print("  Resident memory: \(formatBytes(Int64(memInfo.resident)))")
        print("  Virtual memory: \(formatBytes(Int64(memInfo.virtual)))")
        print("")

        // --- Summary (JSON-like for easy parsing) ---
        print(String(repeating: "=", count: 60))
        print("BENCHMARK RESULTS (v1)")
        print(String(repeating: "=", count: 60))
        print("{")
        print("  \"version\": \"v1.5.0\",")
        print("  \"input\": \"\(inputURL.lastPathComponent)\",")
        print("  \"input_size_bytes\": \(inputFileSize),")
        print("  \"content_duration_s\": \(String(format: "%.1f", session.duration)),")
        print("  \"audio_transcode\": \(transcodeAudio),")
        print("  \"audio_tracks\": \(session.audioTracks.count),")
        print("  \"subtitle_tracks\": \(session.subtitleTracks.count),")
        print("  \"open_time_s\": \(String(format: "%.4f", openTime)),")
        print("  \"first_segment_s\": \(String(format: "%.4f", firstSegTime)),")
        print("  \"total_remux_time_s\": \(String(format: "%.3f", totalRemuxTime)),")
        print("  \"remux_complete\": \(remuxComplete),")
        print("  \"buffered_duration_s\": \(String(format: "%.1f", finalBuffered)),")
        print("  \"realtime_ratio\": \(String(format: "%.2f", realtimeRatio)),")
        print("  \"output_size_bytes\": \(outputFileSize),")
        print("  \"throughput_mbps\": \(String(format: "%.2f", throughputMBps)),")
        if inputFileSize > 0 {
            print("  \"size_ratio_pct\": \(String(format: "%.1f", Double(outputFileSize) / Double(inputFileSize) * 100)),")
        }
        if let lat = seekLatency {
            print("  \"seek_target_s\": \(String(format: "%.1f", seekTarget!)),")
            print("  \"seek_latency_s\": \(String(format: "%.4f", lat)),")
        }
        print("  \"memory_resident_bytes\": \(memInfo.resident),")
        print("  \"memory_virtual_bytes\": \(memInfo.virtual)")
        print("}")
        print("")

        await service.cleanup(sessionID: session.sessionID)
    }

    /// Get current process memory usage via mach task_info
    static func getMemoryUsage() -> (resident: UInt64, virtual: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return (resident: info.resident_size, virtual: info.virtual_size)
        }
        return (resident: 0, virtual: 0)
    }

    /// Format bytes as human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return "\(String(format: "%.1f", kb)) KB" }
        let mb = kb / 1024
        if mb < 1024 { return "\(String(format: "%.1f", mb)) MB" }
        let gb = mb / 1024
        return "\(String(format: "%.2f", gb)) GB"
    }

    // MARK: - DLNA Mode

    /// DLNA mode: transmux input to regular MP4 (non-fragmented, with moov),
    /// serve via TransmuxServer with DLNA headers, send SetAVTransportURI to TV.
    ///
    /// DLNA TVs need a regular MP4 with full moov atom — not fMP4 fragments.
    /// The transmux is fast (no re-encoding), then the completed file is served.
    static func runDLNA(
        inputURL: URL,
        dlnaTarget: String,
        service: TransmuxingService,
        verbose: Bool,
        transcodeAudio: Bool = false
    ) async {
        dlnaPrint("DLNA-CLI", "Starting DLNA mode...")

        // Step 1: Resolve the target device
        let device: DLNADevice
        if dlnaTarget == "discover" {
            dlnaPrint("DLNA-CLI", "Step 1: SSDP discovery for DLNA MediaRenderers...")
            let devices = await discoverDLNADevices(timeout: 5)

            if devices.isEmpty {
                dlnaPrint("DLNA-CLI", "ERROR: No DLNA MediaRenderer devices found on the network")
                return
            }

            if devices.count == 1 {
                device = devices[0]
                dlnaPrint("DLNA-CLI", "Found 1 device: \(device.friendlyName) at \(device.ip):\(device.port)")
            } else {
                print("")
                print("Found \(devices.count) DLNA devices:")
                for (i, d) in devices.enumerated() {
                    print("  [\(i + 1)] \(d.friendlyName) (\(d.modelName ?? "?")) — \(d.ip):\(d.port)")
                }
                print("")
                print("Select device [1-\(devices.count)]: ", terminator: "")
                fflush(stdout)

                guard let choice = readLine(),
                      let idx = Int(choice.trimmingCharacters(in: .whitespaces)),
                      idx >= 1, idx <= devices.count else {
                    dlnaPrint("DLNA-CLI", "Invalid selection — exiting")
                    return
                }
                device = devices[idx - 1]
                dlnaPrint("DLNA-CLI", "Selected: \(device.friendlyName) at \(device.ip):\(device.port)")
            }
            print("")
        } else {
            // Direct IP — try to construct device by fetching description XML
            dlnaPrint("DLNA-CLI", "Step 1: Fetching device description from \(dlnaTarget)...")
            guard let d = await constructDLNADevice(ip: dlnaTarget) else {
                dlnaPrint("DLNA-CLI", "ERROR: Could not find DLNA device at \(dlnaTarget)")
                dlnaPrint("DLNA-CLI", "Make sure the TV is on and try --discover-dlna first")
                return
            }
            device = d
        }

        // Step 2: Determine serving strategy.
        // - Local MP4/M4V/MOV: serve directly (no transmux)
        // - Everything else (MKV, remote URLs): progressive MPEG-TS transmux,
        //   start serving immediately while transmux runs in background
        let sourceExt = inputURL.pathExtension.lowercased()
        let isLocalFile = inputURL.isFileURL
        let isDirectServe = isLocalFile && (sourceExt == "mp4" || sourceExt == "m4v" || sourceExt == "mov")

        if isDirectServe {
            // --- LOCAL MP4: serve the file directly ---
            dlnaPrint("DLNA-CLI", "Step 2: Source is local MP4 — serving directly (no transmux)")
            let localPath = inputURL.path
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
                  let size = attrs[.size] as? Int64 else {
                dlnaPrint("DLNA-CLI", "ERROR: Cannot read file: \(localPath)")
                return
            }
            dlnaPrint("DLNA-CLI", "  File: \(localPath)")
            dlnaPrint("DLNA-CLI", "  Size: \(size / 1_048_576)MB")

            let contentDuration = TransmuxingService.probeDuration(url: inputURL) ?? 0
            if contentDuration > 0 {
                dlnaPrint("DLNA-CLI", "  Duration: \(String(format: "%.1f", contentDuration))s")
            }

            dlnaPrint("DLNA-CLI", "Step 3: Starting HTTP server (DLNA mode)...")
            do {
                let serverSession = try await TransmuxServer.shared.startDLNA(
                    filePath: localPath,
                    expectedSize: size
                )
                dlnaPrint("DLNA-CLI", "Content URL: \(serverSession.localURL)")
                print("")

                await TransmuxServer.shared.setExpectedSize(size)
                await TransmuxServer.shared.setComplete()

                let title = (inputURL.lastPathComponent as NSString).deletingPathExtension
                await runDLNASession(
                    device: device,
                    contentURL: serverSession.localURL,
                    title: title,
                    duration: contentDuration,
                    verbose: verbose
                )

                await TransmuxServer.shared.stop()
                dlnaPrint("DLNA-CLI", "Cleanup complete")
            } catch {
                dlnaPrint("DLNA-CLI", "ERROR: Server start failed: \(error.localizedDescription)")
            }
        } else {
            // --- REMOTE URL / MKV / NON-MP4: progressive MPEG-TS transmux ---
            // Transmux runs in background, server starts after initial buffer,
            // TV receives data in real-time as it's being transmuxed.
            dlnaPrint("DLNA-CLI", "Step 2: Progressive MPEG-TS transmux (real-time streaming)...")
            let session: DLNATransmuxSession
            do {
                session = try await service.startDLNATransmux(from: inputURL, transcodeAudio: transcodeAudio)
            } catch {
                dlnaPrint("DLNA-CLI", "ERROR: Transmux failed: \(error.localizedDescription)")
                return
            }

            dlnaPrint("DLNA-CLI", "Transmux started: \(session.sessionID.prefix(8))")
            dlnaPrint("DLNA-CLI", "  Output: \(session.outputPath)")
            dlnaPrint("DLNA-CLI", "  Duration: \(String(format: "%.1f", session.duration))s")
            dlnaPrint("DLNA-CLI", "  Estimated size: \(session.expectedSize / 1_048_576)MB")

            // Step 3: Wait for initial buffer (2s) then start serving immediately
            dlnaPrint("DLNA-CLI", "Step 3: Buffering initial content...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            dlnaPrint("DLNA-CLI", "Step 4: Starting HTTP server (DLNA streaming mode)...")
            do {
                let serverSession = try await TransmuxServer.shared.startDLNA(
                    filePath: session.outputPath,
                    expectedSize: session.expectedSize
                )
                dlnaPrint("DLNA-CLI", "Content URL: \(serverSession.localURL)")
                print("")

                // Background: monitor transmux completion via sentinel file.
                // Don't use "file stopped growing" — network stalls cause false positives.
                let outputPath = session.outputPath
                let sentinelPath = (outputPath as NSString).deletingLastPathComponent + "/.transmux_complete"
                Task {
                    while true {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if FileManager.default.fileExists(atPath: sentinelPath) {
                            let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
                            let finalSize = (attrs?[.size] as? Int64) ?? 0
                            await TransmuxServer.shared.setExpectedSize(finalSize)
                            await TransmuxServer.shared.setComplete()
                            dlnaPrint("DLNA-CLI", "Transmux complete: \(finalSize / 1_048_576)MB final")
                            break
                        }
                    }
                }

                let title = (inputURL.lastPathComponent as NSString).deletingPathExtension
                await runDLNASession(
                    device: device,
                    contentURL: serverSession.localURL,
                    title: title,
                    duration: session.duration,
                    verbose: verbose,
                    streaming: true
                )

                await TransmuxServer.shared.stop()
                await service.cleanup(sessionID: session.sessionID)
                dlnaPrint("DLNA-CLI", "Cleanup complete")
            } catch {
                dlnaPrint("DLNA-CLI", "ERROR: Server start failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cast Mode (MPEG-TS)

    /// Cast mode using MPEG-TS segments. The Default Media Receiver's MPL only supports
    /// HLS with MPEG-TS containers — fMP4 causes LOADING state forever.
    /// This function uses TransmuxServer.startCast() for simple file serving.
    static func runCastMPEGTS(session: CastTransmuxSession, castIP: String, verbose: Bool) async {
        // Resolve the target IP
        let resolvedIP: String
        if castIP == "discover" {
            castPrint("CAST-CLI", "Running SSDP discovery...")
            let devices = discoverCastDevices(timeout: 5)

            if devices.isEmpty {
                castPrint("CAST-CLI", "ERROR: No Cast devices found on the network")
                return
            }

            if devices.count == 1 {
                let device = devices[0]
                castPrint("CAST-CLI", "Found 1 device: \(device.name) (\(device.model)) at \(device.ip)")
                resolvedIP = device.ip
            } else {
                print("")
                print("Found \(devices.count) Cast devices:")
                for (i, device) in devices.enumerated() {
                    print("  [\(i + 1)] \(device.name) (\(device.model)) — \(device.ip)")
                }
                print("")
                print("Select device [1-\(devices.count)]: ", terminator: "")
                fflush(stdout)

                guard let choice = readLine(),
                      let idx = Int(choice.trimmingCharacters(in: .whitespaces)),
                      idx >= 1, idx <= devices.count else {
                    castPrint("CAST-CLI", "Invalid selection — exiting")
                    return
                }
                resolvedIP = devices[idx - 1].ip
                castPrint("CAST-CLI", "Selected: \(devices[idx - 1].name) at \(resolvedIP)")
            }
            print("")
        } else {
            resolvedIP = castIP
        }

        castPrint("CAST-CLI", "Starting Cast (MPEG-TS) session to \(resolvedIP):8009")

        // Step 1: Wait for initial .ts segments to be written
        castPrint("CAST-CLI", "Step 1: Waiting for MPEG-TS segments...")
        let ready = await waitForCastContent(session: session, minSegments: 2, timeout: 30.0)
        if !ready {
            castPrint("CAST-CLI", "WARNING: Timed out waiting for segments, starting server anyway")
        }

        // Count available segments
        var segCount = 0
        while FileManager.default.fileExists(atPath: (session.outputDir as NSString).appendingPathComponent("seg_\(String(format: "%03d", segCount)).ts")) {
            segCount += 1
        }
        castPrint("CAST-CLI", "\(segCount) segments available")

        // Step 2: Start TransmuxServer in Cast mode
        castPrint("CAST-CLI", "Step 2: Starting TransmuxServer (Cast/MPEG-TS mode)...")
        do {
            let serverSession = try await TransmuxServer.shared.startCast(directory: session.outputDir)

            guard let lanIP = getLANIPAddress() else {
                castPrint("CAST-CLI", "ERROR: Cannot determine LAN IP address")
                return
            }

            let castURLString = serverSession.localURL.absoluteString
                .replacingOccurrences(of: "localhost", with: lanIP)
                .replacingOccurrences(of: "127.0.0.1", with: lanIP)
            guard let castURL = URL(string: castURLString) else {
                castPrint("CAST-CLI", "ERROR: Cannot build Cast URL")
                return
            }

            castPrint("CAST-CLI", "Server URL: \(serverSession.localURL)")
            castPrint("CAST-CLI", "Cast URL:   \(castURL)")
            castPrint("CAST-CLI", "LAN IP:     \(lanIP)")
            castPrint("CAST-CLI", "Format:     HLS + MPEG-TS (Cast compatible)")
            print("")

            // Step 3: Connect to Chromecast
            castPrint("CAST-CLI", "Step 3: Connecting to Chromecast at \(resolvedIP):8009...")
            let socket = CastDebugSocket(host: resolvedIP)
            let channel = CastDebugChannel(socket: socket)

            do {
                try await socket.connect()
                try await channel.connect()
            } catch {
                castPrint("CAST-CLI", "ERROR: Cast connection failed: \(error.localizedDescription)")
                await socket.disconnect()
                await TransmuxServer.shared.stop()
                return
            }

            // Step 4: Send LOAD — HLS with MPEG-TS segments
            castPrint("CAST-CLI", "Step 4: Sending LOAD (HLS + MPEG-TS)...")
            do {
                try await channel.loadMedia(
                    url: castURL,
                    contentType: "application/x-mpegurl",
                    title: "TransmuxCLI Cast",
                    startTime: 0
                )
                castPrint("CAST-CLI", "LOAD succeeded!")
            } catch {
                castPrint("CAST-CLI", "ERROR: LOAD failed: \(error.localizedDescription)")
                castPrint("CAST-CLI", "Continuing in interactive mode to debug...")
            }

            // Step 5: Interactive command loop
            print("")
            print("=========================================")
            print("  Cast Debug Session Active (MPEG-TS)")
            print("  Device: \(resolvedIP):8009")
            print("  Server: \(castURL)")
            print("  Format: HLS + MPEG-TS")
            print("")
            print("  Commands:")
            print("    LOAD [url]     (Re)load media")
            print("    PLAY           Resume playback")
            print("    PAUSE          Pause playback")
            print("    STOP           Stop media")
            print("    SEEK <seconds> Seek to position")
            print("    STATUS         Get media status")
            print("    SEGS           Count available segments")
            print("    QUIT           Disconnect and exit")
            print("=========================================")
            print("")

            signal(SIGINT) { _ in
                print("\n[CAST-CLI] Interrupted — exiting")
                exit(0)
            }

            print("cast> ", terminator: "")
            fflush(stdout)

            while let line = readLine() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    print("cast> ", terminator: "")
                    fflush(stdout)
                    continue
                }

                let parts = trimmed.split(separator: " ", maxSplits: 1)
                let cmd = String(parts[0]).uppercased()

                switch cmd {
                case "QUIT", "EXIT", "Q":
                    castPrint("CAST-CLI", "Disconnecting...")
                    await channel.disconnect()
                    await TransmuxServer.shared.stop()
                    return

                case "LOAD":
                    let loadURL: URL
                    if parts.count > 1, let customURL = URL(string: String(parts[1])) {
                        loadURL = customURL
                    } else {
                        loadURL = castURL
                    }
                    let ct = castContentType(for: loadURL)
                    castPrint("CAST-CLI", "Loading \(loadURL) (\(ct))...")
                    do {
                        try await channel.loadMedia(url: loadURL, contentType: ct, title: "Cast Debug")
                        castPrint("CAST-CLI", "LOAD OK")
                    } catch {
                        castPrint("CAST-CLI", "LOAD FAILED: \(error.localizedDescription)")
                    }

                case "PLAY":
                    do { try await channel.play() }
                    catch { castPrint("CAST-CLI", "PLAY FAILED: \(error.localizedDescription)") }

                case "PAUSE":
                    do { try await channel.pause() }
                    catch { castPrint("CAST-CLI", "PAUSE FAILED: \(error.localizedDescription)") }

                case "STOP":
                    do { try await channel.stop() }
                    catch { castPrint("CAST-CLI", "STOP FAILED: \(error.localizedDescription)") }

                case "SEEK":
                    guard parts.count > 1, let time = Double(parts[1]) else {
                        castPrint("CAST-CLI", "Usage: SEEK <seconds>")
                        break
                    }
                    do { try await channel.seek(to: time) }
                    catch { castPrint("CAST-CLI", "SEEK FAILED: \(error.localizedDescription)") }

                case "STATUS":
                    do { try await channel.getMediaStatus() }
                    catch { castPrint("CAST-CLI", "STATUS FAILED: \(error.localizedDescription)") }

                case "SEGS":
                    var count = 0
                    while FileManager.default.fileExists(atPath: (session.outputDir as NSString).appendingPathComponent("seg_\(String(format: "%03d", count)).ts")) {
                        count += 1
                    }
                    castPrint("CAST-CLI", "\(count) segments on disk")

                case "HELP", "?":
                    print("Commands: LOAD [url] | PLAY | PAUSE | STOP | SEEK <s> | STATUS | SEGS | QUIT")

                default:
                    castPrint("CAST-CLI", "Unknown: \(trimmed). Type HELP.")
                }

                print("cast> ", terminator: "")
                fflush(stdout)
            }

            // stdin closed
            castPrint("CAST-CLI", "stdin closed — disconnecting...")
            await channel.disconnect()
            await TransmuxServer.shared.stop()

        } catch {
            castPrint("CAST-CLI", "ERROR: \(error.localizedDescription)")
        }
    }

    /// Wait for Cast MPEG-TS segments to appear on disk.
    static func waitForCastContent(session: CastTransmuxSession, minSegments: Int, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var count = 0
            while FileManager.default.fileExists(atPath: (session.outputDir as NSString).appendingPathComponent("seg_\(String(format: "%03d", count)).ts")) {
                count += 1
            }
            if count >= minSegments {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    // MARK: - Cast Mode (Legacy fMP4 — kept for reference)

    /// Legacy fMP4 Cast mode — kept for reference but no longer used.
    /// The Default Media Receiver's MPL player only supports HLS with MPEG-TS segments.
    static func runCast(session: ProgressiveTransmuxSession, castIP: String, verbose: Bool) async {
        // Resolve the target IP — either use the provided one or discover
        let resolvedIP: String
        if castIP == "discover" {
            castPrint("CAST-CLI", "Running SSDP discovery...")
            let devices = discoverCastDevices(timeout: 5)

            if devices.isEmpty {
                castPrint("CAST-CLI", "ERROR: No Cast devices found on the network")
                castPrint("CAST-CLI", "Make sure your Chromecast is on and connected to the same WiFi")
                castPrint("CAST-CLI", "Tip: Use --cast <IP> to connect directly if you know the device IP")
                return
            }

            if devices.count == 1 {
                let device = devices[0]
                castPrint("CAST-CLI", "Found 1 device: \(device.name) (\(device.model)) at \(device.ip)")
                resolvedIP = device.ip
            } else {
                // Multiple devices — let user pick
                print("")
                print("Found \(devices.count) Cast devices:")
                for (i, device) in devices.enumerated() {
                    print("  [\(i + 1)] \(device.name) (\(device.model)) — \(device.ip)")
                }
                print("")
                print("Select device [1-\(devices.count)]: ", terminator: "")
                fflush(stdout)

                guard let choice = readLine(),
                      let idx = Int(choice.trimmingCharacters(in: .whitespaces)),
                      idx >= 1, idx <= devices.count else {
                    castPrint("CAST-CLI", "Invalid selection — exiting")
                    return
                }
                resolvedIP = devices[idx - 1].ip
                castPrint("CAST-CLI", "Selected: \(devices[idx - 1].name) at \(resolvedIP)")
            }
            print("")
        } else {
            resolvedIP = castIP
        }

        castPrint("CAST-CLI", "Starting Cast debug session to \(resolvedIP):8009")

        // Step 1: Wait for initial content
        castPrint("CAST-CLI", "Step 1: Waiting for initial content...")
        let ready = await waitForContent(session: session, minSeconds: 12.0, timeout: 20.0)
        if !ready {
            castPrint("CAST-CLI", "WARNING: Timed out waiting for content, starting server anyway")
        }

        // Step 2: Start TransmuxServer
        castPrint("CAST-CLI", "Step 2: Starting TransmuxServer...")
        do {
            let serverSession = try await TransmuxServer.shared.start(
                filePath: session.outputPath,
                playlistPath: session.playlistPath,
                mediaPlaylistPath: session.mediaPlaylistPath,
                expectedSize: session.expectedSize,
                segmenter: session.segmenter,
                initSegmentSize: session.initSegmentSize,
                seekHandle: session.seekHandle
            )

            // Build LAN URL for the Chromecast
            guard let lanIP = getLANIPAddress() else {
                castPrint("CAST-CLI", "ERROR: Cannot determine LAN IP address")
                return
            }

            let serverURL = serverSession.localURL

            // For Cast: use master.m3u8 when available (multi-audio/subtitles).
            // Shaka Player needs the #EXT-X-MEDIA rendition declarations to properly
            // handle multi-track fMP4 content. Without the master playlist, Shaka sees
            // multiple audio tracks in the moov but has no guidance on how to select them,
            // which can cause it to get stuck in LOADING state.
            // For single-audio content, serverURL already points to stream.m3u8.
            let castURLString = serverURL.absoluteString
                .replacingOccurrences(of: "localhost", with: lanIP)
                .replacingOccurrences(of: "127.0.0.1", with: lanIP)
            guard let castURL = URL(string: castURLString) else {
                castPrint("CAST-CLI", "ERROR: Cannot build Cast URL")
                return
            }

            let lanURLString = serverURL.absoluteString
                .replacingOccurrences(of: "localhost", with: lanIP)
                .replacingOccurrences(of: "127.0.0.1", with: lanIP)
            guard let lanURL = URL(string: lanURLString) else {
                castPrint("CAST-CLI", "ERROR: Cannot build LAN URL")
                return
            }

            let castMIME = castContentType(for: castURL)

            castPrint("CAST-CLI", "Server URL (local):  \(serverURL)")
            castPrint("CAST-CLI", "Server URL (LAN):    \(lanURL)")
            castPrint("CAST-CLI", "Cast URL (HLS):      \(castURL)")
            castPrint("CAST-CLI", "Content type:        \(castMIME)")
            castPrint("CAST-CLI", "LAN IP:              \(lanIP)")
            print("")

            // Step 3: Connect to Chromecast
            castPrint("CAST-CLI", "Step 3: Connecting to Chromecast at \(resolvedIP):8009...")
            let socket = CastDebugSocket(host: resolvedIP)
            let channel = CastDebugChannel(socket: socket)

            do {
                try await socket.connect()
                try await channel.connect()
            } catch {
                castPrint("CAST-CLI", "ERROR: Cast connection failed: \(error.localizedDescription)")
                await socket.disconnect()
                await TransmuxServer.shared.stop()
                return
            }

            // Step 4: Send LOAD — HLS with fMP4 segment hints
            castPrint("CAST-CLI", "Step 4: Sending LOAD (HLS + fMP4 hints)...")
            do {
                try await channel.loadMedia(
                    url: castURL,
                    contentType: castMIME,
                    title: "TransmuxCLI Debug",
                    startTime: 0
                )
                castPrint("CAST-CLI", "LOAD succeeded!")
            } catch {
                castPrint("CAST-CLI", "ERROR: LOAD failed: \(error.localizedDescription)")
                castPrint("CAST-CLI", "Continuing in interactive mode to debug...")
            }

            // Step 5: Interactive command loop
            print("")
            print("=========================================")
            print("  Cast Debug Session Active")
            print("  Device: \(resolvedIP):8009")
            print("  Server: \(lanURL)")
            print("")
            print("  Commands:")
            print("    LOAD [url]     (Re)load media (default: server URL)")
            print("    PLAY           Resume playback")
            print("    PAUSE          Pause playback")
            print("    STOP           Stop media")
            print("    SEEK <seconds> Seek to position")
            print("    STATUS         Get media status")
            print("    RSTATUS        Get receiver status")
            print("    QUIT           Disconnect and exit")
            print("=========================================")
            print("")

            signal(SIGINT) { _ in
                print("\n[CAST-CLI] Interrupted — exiting")
                exit(0)
            }

            print("cast> ", terminator: "")
            fflush(stdout)

            while let line = readLine() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    print("cast> ", terminator: "")
                    fflush(stdout)
                    continue
                }

                let parts = trimmed.split(separator: " ", maxSplits: 1)
                let cmd = String(parts[0]).uppercased()

                switch cmd {
                case "QUIT", "EXIT", "Q":
                    castPrint("CAST-CLI", "Disconnecting...")
                    await channel.disconnect()
                    await TransmuxServer.shared.stop()
                    return

                case "LOAD":
                    let loadURL: URL
                    if parts.count > 1, let customURL = URL(string: String(parts[1])) {
                        loadURL = customURL
                    } else {
                        loadURL = lanURL
                    }
                    let ct = castContentType(for: loadURL)
                    castPrint("CAST-CLI", "Loading \(loadURL) (\(ct))...")
                    do {
                        try await channel.loadMedia(url: loadURL, contentType: ct, title: "Debug")
                        castPrint("CAST-CLI", "LOAD OK")
                    } catch {
                        castPrint("CAST-CLI", "LOAD FAILED: \(error.localizedDescription)")
                    }

                case "PLAY":
                    do {
                        try await channel.play()
                    } catch {
                        castPrint("CAST-CLI", "PLAY FAILED: \(error.localizedDescription)")
                    }

                case "PAUSE":
                    do {
                        try await channel.pause()
                    } catch {
                        castPrint("CAST-CLI", "PAUSE FAILED: \(error.localizedDescription)")
                    }

                case "STOP":
                    do {
                        try await channel.stop()
                    } catch {
                        castPrint("CAST-CLI", "STOP FAILED: \(error.localizedDescription)")
                    }

                case "SEEK":
                    guard parts.count > 1, let time = Double(parts[1]) else {
                        castPrint("CAST-CLI", "Usage: SEEK <seconds>")
                        break
                    }
                    do {
                        try await channel.seek(to: time)
                    } catch {
                        castPrint("CAST-CLI", "SEEK FAILED: \(error.localizedDescription)")
                    }

                case "STATUS":
                    do {
                        try await channel.getMediaStatus()
                    } catch {
                        castPrint("CAST-CLI", "STATUS FAILED: \(error.localizedDescription)")
                    }

                case "RSTATUS":
                    castPrint("CAST-CLI", "Receiver status not available in debug channel (use STATUS)")

                case "HELP", "?":
                    print("Commands: LOAD [url] | PLAY | PAUSE | STOP | SEEK <s> | STATUS | QUIT")

                default:
                    castPrint("CAST-CLI", "Unknown: \(trimmed). Type HELP.")
                }

                print("cast> ", terminator: "")
                fflush(stdout)
            }

            // stdin closed
            castPrint("CAST-CLI", "stdin closed — disconnecting...")
            await channel.disconnect()
            await TransmuxServer.shared.stop()

        } catch {
            castPrint("CAST-CLI", "ERROR: \(error.localizedDescription)")
        }
    }
}
