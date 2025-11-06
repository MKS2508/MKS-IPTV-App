import Foundation
import AVFoundation

/// HTTP proxy server that handles MKV to MP4 transmuxing for AVPlayer
class HTTPStreamProxyServer: NSObject {
    #if os(macOS)
    private var server: Process?
    #endif
    private var currentPort: Int
    private let basePort: Int
    private var isRunning = false
    private var tempScriptFile: URL?
    private let maxRetries = 5
    
    init(port: Int = 8890) {
        self.basePort = port
        self.currentPort = port
        super.init()
    }
    
    /// Check if a port is available
    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        if socketFD == -1 {
            return false
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = in_addr_t(0)
        
        let addrSize = socklen_t(MemoryLayout.size(ofValue: addr))
        let bind_result = withUnsafePointer(to: &addr) {
            Darwin.bind(socketFD, UnsafePointer<sockaddr>(OpaquePointer($0)), addrSize)
        }
        
        close(socketFD)
        return bind_result == 0
    }
    
    /// Find an available port starting from the base port
    private func findAvailablePort() -> Int? {
        for offset in 0..<maxRetries {
            let port = basePort + offset
            if isPortAvailable(port) {
                return port
            }
        }
        return nil
    }
    
    /// Start the proxy server for the given MKV URL
    func start(mkvURL: URL) -> Bool {
        #if os(macOS)
        stop() // Ensure clean state
        
        print("[HTTPStreamProxyServer] Starting proxy for: \(mkvURL)")
        
        // Find available port
        guard let availablePort = findAvailablePort() else {
            print("[HTTPStreamProxyServer] ❌ No available ports found (tried \(basePort) to \(basePort + maxRetries - 1))")
            return false
        }
        
        currentPort = availablePort
        print("[HTTPStreamProxyServer] Using port: \(currentPort)")
        
        // Use Python's built-in HTTP server with a custom handler
        let pythonScript = """
        import http.server
        import socketserver
        import subprocess
        import threading
        import os
        import signal
        import sys
        import time
        
        PORT = \(currentPort)
        MKV_URL = "\(mkvURL.absoluteString)"
        
        class StreamHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/stream.mp4':
                    self.send_response(200)
                    self.send_header('Content-Type', 'video/mp4')
                    self.send_header('Accept-Ranges', 'bytes')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    
                    # Handle range requests
                    range_header = self.headers.get('Range')
                    if range_header and range_header.startswith('bytes=0-1'):
                        # AVPlayer is just checking, send a small response
                        self.wfile.write(b'\\x00\\x00\\x00\\x20ftypmp42')
                        return
                    
                    # Full stream request
                    cmd = [
                        '/opt/homebrew/bin/ffmpeg',
                        '-i', MKV_URL,
                        '-c:v', 'copy',
                        '-c:a', 'aac',  # Convert AC3 to AAC for better compatibility
                        '-b:a', '192k',
                        '-movflags', 'frag_keyframe+empty_moov+faststart',
                        '-f', 'mp4',
                        '-'
                    ]
                    
                    try:
                        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                        while True:
                            data = proc.stdout.read(4096)
                            if not data:
                                break
                            try:
                                self.wfile.write(data)
                            except:
                                proc.terminate()
                                break
                    except Exception as e:
                        print(f"FFmpeg error: {e}")
                else:
                    self.send_error(404)
            
            def log_message(self, format, *args):
                print(f"[HTTPProxy] {format % args}")
        
        try:
            # Test if port is available before starting
            test_socket = socketserver.TCPServer(("", PORT), None)
            test_socket.server_close()
            
            with socketserver.TCPServer(("", PORT), StreamHandler) as httpd:
                httpd.allow_reuse_address = True
                print(f"[HTTPProxy] Serving on http://localhost:{PORT}/stream.mp4")
                sys.stdout.flush()
                httpd.serve_forever()
        except OSError as e:
            print(f"[HTTPProxy] ERROR: Failed to bind to port {PORT}: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"[HTTPProxy] ERROR: Unexpected error: {e}")
            sys.exit(2)
        """
        
        // Create temporary Python script
        tempScriptFile = FileManager.default.temporaryDirectory.appendingPathComponent("stream_proxy_\(UUID().uuidString).py")
        
        do {
            try pythonScript.write(to: tempScriptFile!, atomically: true, encoding: .utf8)
            
            // Create pipes to capture output
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Start Python server
            server = Process()
            server?.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            server?.arguments = [tempScriptFile!.path]
            server?.standardOutput = outputPipe
            server?.standardError = errorPipe
            
            // Set up output monitoring
            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            var serverStarted = false
            let startTimeout = 2.0 // seconds
            let startTime = Date()
            
            // Monitor output for startup confirmation
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("[HTTPStreamProxyServer Output] \(output)")
                    if output.contains("Serving on http://localhost:") {
                        serverStarted = true
                    }
                }
            }
            
            errorHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if let error = String(data: data, encoding: .utf8), !error.isEmpty {
                    print("[HTTPStreamProxyServer Error] \(error)")
                }
            }
            
            server?.terminationHandler = { [weak self] process in
                print("[HTTPStreamProxyServer] Server terminated with status: \(process.terminationStatus)")
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                if let scriptFile = self?.tempScriptFile {
                    try? FileManager.default.removeItem(at: scriptFile)
                }
                self?.isRunning = false
                self?.tempScriptFile = nil
            }
            
            try server?.run()
            
            // Wait for server to start or timeout
            while !serverStarted && Date().timeIntervalSince(startTime) < startTimeout {
                Thread.sleep(forTimeInterval: 0.1)
                
                // Check if process is still running
                if server?.isRunning == false {
                    print("[HTTPStreamProxyServer] ❌ Server process terminated early")
                    break
                }
            }
            
            if serverStarted {
                isRunning = true
                print("[HTTPStreamProxyServer] ✅ Server started on http://localhost:\(currentPort)/stream.mp4")
                return true
            } else {
                print("[HTTPStreamProxyServer] ❌ Server failed to start within timeout")
                stop()
                return false
            }
            
        } catch {
            print("[HTTPStreamProxyServer] ❌ Failed to start: \(error)")
            return false
        }
        #else
        // On iOS, we can't run Process or Python scripts
        print("[HTTPStreamProxyServer] ⚠️ Proxy not available on iOS - returning original URL")
        return false
        #endif
    }
    
    /// Get the current proxy URL
    func getProxyURL() -> URL? {
        guard isRunning else { return nil }
        return URL(string: "http://localhost:\(currentPort)/stream.mp4")
    }
    
    /// Stop the proxy server
    func stop() {
        #if os(macOS)
        if isRunning {
            print("[HTTPStreamProxyServer] Stopping...")
            server?.terminate()
            server = nil
            isRunning = false
        }
        #endif
    }
    
    deinit {
        stop()
    }
}