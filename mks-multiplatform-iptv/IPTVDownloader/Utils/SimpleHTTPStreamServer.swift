import Foundation
import Network

/// Simplified HTTP server for debugging MKV to MP4 streaming
class SimpleHTTPStreamServer {
    private let port: Int
    private var listener: NWListener?
    #if os(macOS)
    private var ffmpegProcess: Process?
    #endif
    private let queue = DispatchQueue(label: "SimpleHTTPStreamServer")
    
    init(port: Int = 8890) {
        self.port = port
        print("[SimpleHTTPStreamServer] Created on port \(port)")
    }
    
    func start(mkvURL: URL) {
        print("[SimpleHTTPStreamServer] Starting server for: \(mkvURL)")
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
            
            listener?.stateUpdateHandler = { state in
                print("[SimpleHTTPStreamServer] State: \(state)")
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection, mkvURL: mkvURL)
            }
            
            listener?.start(queue: queue)
            print("[SimpleHTTPStreamServer] ✅ Listening on http://localhost:\(port)/stream.mp4")
            
        } catch {
            print("[SimpleHTTPStreamServer] ❌ Failed to start: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection, mkvURL: URL) {
        print("[SimpleHTTPStreamServer] 📥 New connection")
        
        connection.stateUpdateHandler = { state in
            print("[SimpleHTTPStreamServer] Connection state: \(state)")
        }
        
        connection.start(queue: queue)
        
        // Read request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let request = String(data: data, encoding: .utf8) {
                    print("[SimpleHTTPStreamServer] Request:\n\(request)")
                    
                    if request.contains("GET /stream.mp4") {
                        self?.streamVideo(to: connection, from: mkvURL)
                    } else {
                        self?.send404(to: connection)
                    }
                }
            }
            
            if let error = error {
                print("[SimpleHTTPStreamServer] ❌ Receive error: \(error)")
                connection.cancel()
            }
        }
    }
    
    private func streamVideo(to connection: NWConnection, from mkvURL: URL) {
        print("[SimpleHTTPStreamServer] 🎬 Starting video stream")
        
        // Send HTTP headers
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: video/mp4\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r
        
        """
        
        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[SimpleHTTPStreamServer] ❌ Header send error: \(error)")
                connection.cancel()
                return
            }
            
            print("[SimpleHTTPStreamServer] ✅ Headers sent")
            
            #if os(macOS)
            // Start FFmpeg process
            self?.startFFmpeg(mkvURL: mkvURL, connection: connection)
            #else
            // On iOS, we can't run FFmpeg process
            print("[SimpleHTTPStreamServer] ⚠️ FFmpeg not available on iOS")
            connection.cancel()
            #endif
        })
    }
    
    #if os(macOS)
    private func startFFmpeg(mkvURL: URL, connection: NWConnection) {
        print("[SimpleHTTPStreamServer] 🎥 Starting FFmpeg")
        
        ffmpegProcess = Process()
        ffmpegProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ffmpegProcess?.arguments = [
            "-i", mkvURL.absoluteString,
            "-c:v", "copy",
            "-c:a", "aac",
            "-b:a", "192k",
            "-movflags", "frag_keyframe+empty_moov+default_base_moof",
            "-f", "mp4",
            "-"
        ]
        
        let pipe = Pipe()
        ffmpegProcess?.standardOutput = pipe
        ffmpegProcess?.standardError = FileHandle.nullDevice
        
        let fileHandle = pipe.fileHandleForReading
        
        // Read FFmpeg output and send to connection
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                print("[SimpleHTTPStreamServer] FFmpeg finished")
                connection.cancel()
                return
            }
            
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("[SimpleHTTPStreamServer] ❌ Send error: \(error)")
                    handle.readabilityHandler = nil
                    self.ffmpegProcess?.terminate()
                }
            })
        }
        
        ffmpegProcess?.terminationHandler = { process in
            print("[SimpleHTTPStreamServer] FFmpeg terminated with status: \(process.terminationStatus)")
            fileHandle.readabilityHandler = nil
            connection.cancel()
        }
        
        do {
            try ffmpegProcess?.run()
            print("[SimpleHTTPStreamServer] ✅ FFmpeg started")
        } catch {
            print("[SimpleHTTPStreamServer] ❌ Failed to start FFmpeg: \(error)")
            connection.cancel()
        }
    }
    #endif
    
    private func send404(to connection: NWConnection) {
        let response = """
        HTTP/1.1 404 Not Found\r
        Content-Type: text/plain\r
        Content-Length: 9\r
        \r
        Not Found
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    func stop() {
        print("[SimpleHTTPStreamServer] Stopping...")
        listener?.cancel()
        listener = nil
        #if os(macOS)
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        #endif
    }
    
    deinit {
        stop()
    }
}