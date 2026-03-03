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
                print("❌ Invalid URL: \(inputPath)")
                exit(1)
            }
            inputURL = url
        } else {
            inputURL = URL(fileURLWithPath: inputPath)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                print("❌ File not found: \(inputPath)")
                exit(1)
            }
        }

        // Parse options
        let doSeek = args.contains("--seek")
        let seekTime = doSeek ? getArgValue(for: "--seek") ?? 0.0 : 0.0
        let duration = getArgValue(for: "--duration") ?? 10.0
        let verbose = args.contains("--verbose")

        if verbose {
            print("🎬 TransmuxCore CLI v1.0.0")
            print("📥 Input: \(inputURL)")
            if doSeek {
                print("⏩ Will seek to \(String(format: "%.1f", seekTime))s for \(String(format: "%.1f", duration))s")
            }
        }

        let service = TransmuxingService()

        do {
            let session = try await service.startTransmux(from: inputURL)
            print("✅ Transmux started: \(session.sessionID)")
            print("   📦 Output: \(session.outputPath)")
            print("   📋 Playlist: \(session.playlistPath)")
            print("   🎞️  Init segment: \(session.initSegmentSize) bytes")
            print("   ⏱️  Duration: \(String(format: "%.1f", session.duration))s")

            if doSeek {
                // Wait a bit for initial segments to be generated
                try await Task.sleep(for: .seconds(2))

                print("⏩ Seeking to \(String(format: "%.1f", seekTime))s...")
                session.seekHandle.requestSeek(to: seekTime)

                // Wait for seek to complete and generate segments
                try await Task.sleep(for: .seconds(duration))

                let latestTime = session.segmenter.latestTransmuxedTime()
                print("✅ Seek test complete. Latest transmuxed time: \(String(format: "%.1f", latestTime))s")
            } else {
                print("⏳ Transmuxing... (press Ctrl+C to stop)")
                print("   💡 Tip: Monitor logs with: tail -f /tmp/mks-iptv-transmux.log")

                // Wait for user interrupt or completion
                signal(SIGINT) { _ in
                    print("\n⚠️  Interrupted by user")
                    exit(0)
                }

                // Wait for a long time (or until interrupted)
                try await Task.sleep(for: .seconds(3600))
            }

            await service.cleanup(sessionID: session.sessionID)
            print("🧹 Cleanup complete")

        } catch {
            print("❌ Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        TransmuxCore CLI - FFmpeg-based container transmuxing without re-encoding

        USAGE:
            transmux-cli <input> [options]

        ARGUMENTS:
            <input>                 Input file path or HTTP(S) URL

        OPTIONS:
            --seek TIME             Seek to TIME seconds and test seeking functionality
            --duration SECONDS      Duration to test after seek (default: 10 seconds)
            --verbose               Enable verbose output

        EXAMPLES:
            # Basic transmux
            transmux-cli movie.mkv

            # Test seeking at 5 minutes
            transmux-cli movie.mkv --seek 300 --duration 20

            # Remote URL with verbose output
            transmux-cli http://example.com/stream.mkv --verbose

            # Monitor logs in another terminal
            tail -f /tmp/mks-iptv-transmux.log | grep -E "SEEK|OFFSET|DTS"

        OUTPUT:
            Transmuxed files are written to /tmp/mks-iptv-transmux-<sessionID>/
            - stream.mp4: Progressive fMP4 output (growing file)
            - stream.m3u8: HLS VOD playlist (all segments declared upfront)

        NOTES:
            - No re-encoding: video and audio streams are copied as-is
            - AC3/EAC3 audio: automatically handles delay_moov requirement
            - HTTPS URLs: require StreamProxyProvider for FFmpeg compatibility
            - Seeking: tests timestamp rebasing and A/V sync preservation

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
