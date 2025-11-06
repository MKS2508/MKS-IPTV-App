import Foundation
import AVFoundation

/// Simple HTTP proxy that directly runs ffmpeg for streaming
class DirectHTTPProxy: NSObject {
    #if os(macOS)
    private var ffmpegProcess: Process?
    private var pythonProcess: Process?
    #endif
    private let port: Int
    private var isRunning = false
    
    init(port: Int = 8891) {
        self.port = port
        super.init()
    }
    
    func start(mkvURL: URL) -> Bool {
        #if os(macOS)
        stop() // Clean up any existing process
        
        // Kill any existing process on this port
        let killCmd = Process()
        killCmd.executableURL = URL(fileURLWithPath: "/bin/sh")
        killCmd.arguments = ["-c", "lsof -ti:\(port) | xargs kill -9 2>/dev/null || true"]
        try? killCmd.run()
        killCmd.waitUntilExit()
        
        // Also kill any existing Python script
        let killPythonCmd = Process()
        killPythonCmd.executableURL = URL(fileURLWithPath: "/bin/sh")
        killPythonCmd.arguments = ["-c", "pkill -f 'direct_proxy_\(port).py' 2>/dev/null || true"]
        try? killPythonCmd.run()
        killPythonCmd.waitUntilExit()
        
        // Give it a moment to release the port
        Thread.sleep(forTimeInterval: 1.0)
        
        print("[DirectHTTPProxy] Starting on port \(port) for: \(mkvURL)")
        
        // Create a simple Python HTTP server that pipes ffmpeg output
        let pythonScript = """
#!/usr/bin/env python3
import http.server
import subprocess
import sys
import os

PORT = \(port)
MKV_URL = "\(mkvURL.absoluteString)"

class StreamHandler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == '/stream.mp4':
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp4')
            self.send_header('Accept-Ranges', 'none')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
        else:
            self.send_error(404)
    
    def do_GET(self):
        if self.path == '/stream.mp4':
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp4')
            self.send_header('Accept-Ranges', 'none')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            
            # Start ffmpeg process
            cmd = [
                '/opt/homebrew/bin/ffmpeg',
                '-i', MKV_URL,
                '-c:v', 'copy',
                '-c:a', 'aac',
                '-b:a', '192k',
                '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
                '-f', 'mp4',
                '-'
            ]
            
            print(f"Starting ffmpeg with command: {' '.join(cmd)}")
            
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
                # Read and send data in chunks
                while True:
                    chunk = proc.stdout.read(65536)  # 64KB chunks
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                        self.wfile.flush()
                    except BrokenPipeError:
                        print("Client disconnected")
                        break
                
                proc.wait()
                
                # Check for errors
                if proc.returncode != 0:
                    stderr = proc.stderr.read().decode('utf-8', errors='ignore')
                    print(f"FFmpeg error (code {proc.returncode}): {stderr}")
                    
            except Exception as e:
                print(f"Error during streaming: {e}")
                if 'proc' in locals():
                    proc.kill()
        else:
            self.send_error(404)
    
    def log_message(self, format, *args):
        # Log to console
        print(f"[{self.client_address[0]}] {format % args}")

print(f"Starting server on port {PORT}...")
print(f"Source URL: {MKV_URL}")

try:
    server = http.server.HTTPServer(('', PORT), StreamHandler)
    print(f"Server ready at http://localhost:{PORT}/stream.mp4")
    server.serve_forever()
except Exception as e:
    print(f"Server error: {e}")
"""
        
        // Write script to temp file
        let scriptPath = "/tmp/direct_proxy_\(port).py"
        do {
            try pythonScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            
            // Make it executable
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()
            
            // Start Python server
            pythonProcess = Process()
            pythonProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            pythonProcess?.arguments = [scriptPath]
            
            // Redirect output for debugging
            let pipe = Pipe()
            pythonProcess?.standardOutput = pipe
            pythonProcess?.standardError = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("[DirectHTTPProxy] \(output)")
                }
            }
            
            try pythonProcess?.run()
            
            // Give it a moment to start
            Thread.sleep(forTimeInterval: 1.0)
            
            if pythonProcess?.isRunning == true {
                isRunning = true
                print("[DirectHTTPProxy] ✅ Started on http://localhost:\(port)/stream.mp4")
                return true
            } else {
                print("[DirectHTTPProxy] ❌ Failed to start")
                return false
            }
            
        } catch {
            print("[DirectHTTPProxy] ❌ Error: \(error)")
            return false
        }
        #else
        // On iOS, we can't run Process or Python scripts
        print("[DirectHTTPProxy] ⚠️ Proxy not available on iOS - returning original URL")
        return false
        #endif
    }
    
    func stop() {
        #if os(macOS)
        if isRunning {
            print("[DirectHTTPProxy] Stopping...")
            pythonProcess?.terminate()
            pythonProcess = nil
            isRunning = false
            
            // Clean up script file
            try? FileManager.default.removeItem(atPath: "/tmp/direct_proxy_\(port).py")
        }
        #endif
    }
    
    deinit {
        stop()
    }
}