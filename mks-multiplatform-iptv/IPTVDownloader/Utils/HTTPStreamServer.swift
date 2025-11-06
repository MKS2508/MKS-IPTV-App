import Foundation
import Network

// Extension to make FileHandle non-blocking
extension FileHandle {
    func setNonBlocking() throws {
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags < 0 {
            throw NSError(domain: "FileHandle", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get file flags"])
        }
        
        let result = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        if result < 0 {
            throw NSError(domain: "FileHandle", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to set non-blocking mode"])
        }
    }
}

/// HTTP server that streams transmuxed MKV to MP4 for AVPlayer compatibility
class HTTPStreamServer {
    private let port: Int
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "HTTPStreamServer", attributes: .concurrent)
    private var isRunning = false
    private var currentMKVURL: URL?
    
    /// Initialize server with specified port
    /// - Parameter port: Port number to listen on
    init(port: Int) {
        self.port = port
        print("[HTTPStreamServer] Initialized on port \(port)")
    }
    
    /// Start streaming from MKV URL
    /// - Parameter mkvURL: Source MKV stream URL
    func startStreaming(from mkvURL: URL) {
        guard !isRunning else {
            print("[HTTPStreamServer] Server already running")
            return
        }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Store the MKV URL for later use
            self.currentMKVURL = mkvURL
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)))
            
            listener?.stateUpdateHandler = { state in
                print("[HTTPStreamServer] Listener state: \(state)")
                switch state {
                case .ready:
                    print("[HTTPStreamServer] ✅ Listener is ready on port \(self.port)")
                case .failed(let error):
                    print("[HTTPStreamServer] ❌ Listener failed: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                print("[HTTPStreamServer] 📥 New connection received")
                self?.handleConnection(connection, mkvURL: mkvURL)
            }
            
            listener?.start(queue: queue)
            isRunning = true
            print("[HTTPStreamServer] ✅ Server started on http://localhost:\(port)/stream.mp4")
            
        } catch {
            print("[HTTPStreamServer] ❌ Failed to start server: \(error)")
        }
    }
    
    /// Shutdown the server
    func shutdown() {
        print("[HTTPStreamServer] Shutting down...")
        
        listener?.cancel()
        listener = nil
        
        // Close all connections
        queue.sync(flags: .barrier) {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        
        isRunning = false
        print("[HTTPStreamServer] ✅ Server stopped")
    }
    
    // MARK: - Private Methods
    
    private func handleConnection(_ connection: NWConnection, mkvURL: URL) {
        queue.sync(flags: .barrier) {
            connections.append(connection)
        }
        
        connection.start(queue: queue)
        
        // Read HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[HTTPStreamServer] ❌ Connection error: \(error)")
                self.closeConnection(connection)
                return
            }
            
            guard let data = data,
                  let request = String(data: data, encoding: .utf8) else {
                self.closeConnection(connection)
                return
            }
            
            let firstLine = request.split(separator: "\n").first ?? ""
            print("[HTTPStreamServer] Received request: \(firstLine)")
            
            // Check if it's a GET request for /stream.mp4
            if request.contains("GET /stream.mp4") || request.contains("GET / ") {
                print("[HTTPStreamServer] ✅ Valid stream request detected")
                self.handleStreamRequest(connection: connection, mkvURL: mkvURL)
            } else {
                print("[HTTPStreamServer] ❌ Invalid request, sending 404")
                self.send404(to: connection)
            }
        }
    }
    
    private func handleStreamRequest(connection: NWConnection, mkvURL: URL) {
        print("[HTTPStreamServer] Handling stream request for \(mkvURL)")
        
        // Send HTTP headers
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: video/mp4\r
        Transfer-Encoding: chunked\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r\n
        """
        
        guard let headerData = headers.data(using: .utf8) else {
            closeConnection(connection)
            return
        }
        
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[HTTPStreamServer] ❌ Failed to send headers: \(error)")
                self?.closeConnection(connection)
                return
            }
            
            // Start transmuxing
            self?.startTransmuxing(from: mkvURL, to: connection)
        })
    }
    
    private func startTransmuxing(from mkvURL: URL, to connection: NWConnection) {
        print("[HTTPStreamServer] 🎬 Starting transmuxing from: \(mkvURL)")
        
        Task {
            do {
                // Create a pipe for transmuxing
                let pipe = Pipe()
                let readHandle = pipe.fileHandleForReading
                let writeHandle = pipe.fileHandleForWriting
                
                // Make read handle non-blocking
                if #available(macOS 10.15.4, *) {
                    try readHandle.setNonBlocking()
                }
                
                var totalBytesSent = 0
                
                // Start reading from pipe and sending to connection
                let readTask = Task {
                    while !Task.isCancelled {
                        autoreleasepool {
                            let data = readHandle.availableData
                            if data.isEmpty {
                                // Sleep briefly to avoid busy waiting
                                Thread.sleep(forTimeInterval: 0.01)
                                return
                            }
                            
                            totalBytesSent += data.count
                            
                            // Send as chunked encoding
                            let chunkSize = String(format: "%X\r\n", data.count)
                            var chunkData = Data()
                            chunkData.append(chunkSize.data(using: .utf8)!)
                            chunkData.append(data)
                            chunkData.append("\r\n".data(using: .utf8)!)
                            
                            connection.send(content: chunkData, completion: .contentProcessed { error in
                                if let error = error {
                                    print("[HTTPStreamServer] ❌ Send error: \(error)")
                                    Task { @MainActor in
                                        readHandle.closeFile()
                                    }
                                } else {
                                    print("[HTTPStreamServer] 📤 Sent chunk: \(data.count) bytes (total: \(totalBytesSent))")
                                }
                            })
                        }
                    }
                }
                
                // Start transmuxing in background
                print("[HTTPStreamServer] 🔄 Starting FFmpeg transmuxing...")
                Task.detached {
                    do {
                        try await FFmpegTransmuxer.transmuxMKVToMP4Stream(from: mkvURL, to: writeHandle)
                        print("[HTTPStreamServer] ✅ FFmpeg transmuxing completed")
                    } catch {
                        print("[HTTPStreamServer] ❌ FFmpeg error: \(error)")
                    }
                }
                
                // Keep connection alive until closed
                try await Task.sleep(nanoseconds: 3600_000_000_000) // 1 hour timeout
                
            } catch {
                print("[HTTPStreamServer] ❌ Transmuxing error: \(error)")
                
                // Send error response
                let errorResponse = """
                HTTP/1.1 500 Internal Server Error\r
                Content-Type: text/plain\r
                Connection: close\r
                \r
                Transmuxing error: \(error.localizedDescription)
                """
                
                if let data = errorResponse.data(using: .utf8) {
                    connection.send(content: data, completion: .contentProcessed { _ in
                        self.closeConnection(connection)
                    })
                }
            }
        }
    }
    
    private func send404(to connection: NWConnection) {
        let response = """
        HTTP/1.1 404 Not Found\r
        Content-Type: text/plain\r
        Content-Length: 9\r
        \r
        Not Found
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
    
    private func closeConnection(_ connection: NWConnection) {
        queue.sync(flags: .barrier) {
            connections.removeAll { $0 === connection }
        }
        connection.cancel()
        print("[HTTPStreamServer] Connection closed")
    }
}