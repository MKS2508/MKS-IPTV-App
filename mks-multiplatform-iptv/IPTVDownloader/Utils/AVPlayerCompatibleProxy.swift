import Foundation
import AVFoundation

/// HTTP proxy specifically designed for AVPlayer compatibility
class AVPlayerCompatibleProxy: NSObject {
    #if os(macOS)
    private var pythonProcess: Process?
    #endif
    private let port: Int
    private var isRunning = false
    
    init(port: Int = 8892) {
        self.port = port
        super.init()
    }
    
    func start(mkvURL: URL) -> Bool {
        #if os(macOS)
        stop()
        
        print("[AVPlayerCompatibleProxy] Starting on port \(port) for: \(mkvURL)")
        
        // Python script that properly handles AVPlayer's requirements
        let pythonScript = """
#!/usr/bin/env python3
import http.server
import subprocess
import os
import threading
import time
import tempfile

PORT = \(port)
MKV_URL = "\(mkvURL.absoluteString)"

# Create a temporary file for the transmuxed content
temp_file = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
temp_path = temp_file.name
temp_file.close()

# Start ffmpeg conversion in background
print(f"[Proxy] Starting conversion to {temp_path}")
ffmpeg_cmd = [
    '/opt/homebrew/bin/ffmpeg',
    '-i', MKV_URL,
    '-c:v', 'copy',
    '-c:a', 'aac',
    '-b:a', '192k',
    '-movflags', '+faststart',
    '-y',
    temp_path
]

ffmpeg_process = subprocess.Popen(ffmpeg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

# Monitor conversion progress
def monitor_conversion():
    while ffmpeg_process.poll() is None:
        time.sleep(1)
    if ffmpeg_process.returncode == 0:
        print(f"[Proxy] ✅ Conversion complete: {temp_path}")
    else:
        print(f"[Proxy] ❌ Conversion failed with code {ffmpeg_process.returncode}")

monitor_thread = threading.Thread(target=monitor_conversion)
monitor_thread.daemon = True
monitor_thread.start()

class StreamHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[Proxy] {format % args}")
    
    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Access-Control-Allow-Origin', '*')
        
        # Wait for file to exist
        max_wait = 30
        waited = 0
        while not os.path.exists(temp_path) and waited < max_wait:
            time.sleep(0.5)
            waited += 0.5
        
        if os.path.exists(temp_path):
            file_size = os.path.getsize(temp_path)
            self.send_header('Content-Length', str(file_size))
        
        self.end_headers()
    
    def do_GET(self):
        if self.path != '/stream.mp4':
            self.send_error(404)
            return
        
        # Wait for conversion to start creating the file
        max_wait = 30
        waited = 0
        while not os.path.exists(temp_path) and waited < max_wait:
            time.sleep(0.5)
            waited += 0.5
        
        if not os.path.exists(temp_path):
            self.send_error(503, "Conversion not ready")
            return
        
        # Handle range requests
        range_header = self.headers.get('Range')
        
        if range_header:
            # Parse range header
            try:
                range_str = range_header.replace('bytes=', '')
                range_parts = range_str.split('-')
                start = int(range_parts[0]) if range_parts[0] else 0
                
                # Get current file size
                file_size = os.path.getsize(temp_path)
                end = int(range_parts[1]) if range_parts[1] else file_size - 1
                
                # Ensure we don't go beyond file size
                end = min(end, file_size - 1)
                
                # Send partial content response
                self.send_response(206)
                self.send_header('Content-Type', 'video/mp4')
                self.send_header('Content-Length', str(end - start + 1))
                self.send_header('Content-Range', f'bytes {start}-{end}/{file_size}')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                
                # Send the requested range
                with open(temp_path, 'rb') as f:
                    f.seek(start)
                    remaining = end - start + 1
                    while remaining > 0:
                        chunk_size = min(65536, remaining)
                        chunk = f.read(chunk_size)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                
            except Exception as e:
                print(f"[Proxy] Range request error: {e}")
                self.send_error(416, "Invalid range")
        else:
            # Full file request
            file_size = os.path.getsize(temp_path)
            
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp4')
            self.send_header('Content-Length', str(file_size))
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            # Stream the file
            with open(temp_path, 'rb') as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

def cleanup():
    if ffmpeg_process.poll() is None:
        ffmpeg_process.terminate()
    try:
        os.unlink(temp_path)
        print(f"[Proxy] Cleaned up temporary file: {temp_path}")
    except:
        pass

try:
    with http.server.HTTPServer(('', PORT), StreamHandler) as httpd:
        print(f"[Proxy] Server running at http://localhost:{PORT}/stream.mp4")
        httpd.serve_forever()
except KeyboardInterrupt:
    print("[Proxy] Shutting down...")
finally:
    cleanup()
"""
        
        // Write script
        let scriptPath = "/tmp/avplayer_proxy_\(port).py"
        do {
            try pythonScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            
            // Start server
            pythonProcess = Process()
            pythonProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            pythonProcess?.arguments = [scriptPath]
            
            let pipe = Pipe()
            pythonProcess?.standardOutput = pipe
            pythonProcess?.standardError = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("[AVPlayerCompatibleProxy] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            
            pythonProcess?.terminationHandler = { [weak self] _ in
                print("[AVPlayerCompatibleProxy] Process terminated")
                self?.isRunning = false
                try? FileManager.default.removeItem(atPath: scriptPath)
            }
            
            try pythonProcess?.run()
            
            // Give it time to start
            Thread.sleep(forTimeInterval: 2.0)
            
            if pythonProcess?.isRunning == true {
                isRunning = true
                print("[AVPlayerCompatibleProxy] ✅ Started on http://localhost:\(port)/stream.mp4")
                return true
            }
            
        } catch {
            print("[AVPlayerCompatibleProxy] ❌ Error: \(error)")
        }
        
        return false
        #else
        // On iOS, we can't run Process or Python scripts
        print("[AVPlayerCompatibleProxy] ⚠️ Proxy not available on iOS - returning original URL")
        return false
        #endif
    }
    
    func stop() {
        #if os(macOS)
        if isRunning {
            print("[AVPlayerCompatibleProxy] Stopping...")
            pythonProcess?.terminate()
            pythonProcess = nil
            isRunning = false
        }
        #endif
    }
    
    deinit {
        stop()
    }
}