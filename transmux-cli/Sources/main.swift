import Foundation
import Libavformat
import Libavcodec
import Libavutil
import Network

// MARK: - CLI Entry

guard CommandLine.arguments.count >= 2 else {
    print("Usage: transmux-cli <url> [--proxy] [--transmux]")
    print("  <url>        Remote stream URL (http/https)")
    print("  --proxy      Start local proxy and test through it")
    print("  --transmux   Actually transmux to HLS/MP4 (default: probe only)")
    exit(1)
}

let inputURL = CommandLine.arguments[1]
let useProxy = CommandLine.arguments.contains("--proxy")
let doTransmux = CommandLine.arguments.contains("--transmux")

print("=== TransmuxCLI ===")
print("Input: \(inputURL)")
print("Proxy: \(useProxy)")
print("Transmux: \(doTransmux)")
print()

// MARK: - Minimal HTTP Proxy (NWListener)

class MiniProxy {
    let backendURL: URL
    let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mini-proxy")
    private var connections: [NWConnection] = []

    init(backendURL: URL, port: UInt16 = 9200) {
        self.backendURL = backendURL
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                print("[Proxy] Listening on port \(self.port)")
            } else if case .failed(let err) = state {
                print("[Proxy] Listener failed: \(err)")
            }
        }
        listener.start(queue: queue)

        // Wait for listener to be ready
        Thread.sleep(forTimeInterval: 0.2)
    }

    func stop() {
        listener?.cancel()
        for c in connections { c.cancel() }
        connections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            guard let request = String(data: data, encoding: .ascii) else {
                connection.cancel()
                return
            }

            let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
            guard let firstLine = lines.first else { connection.cancel(); return }
            let parts = firstLine.split(separator: " ")
            let method = String(parts.first ?? "GET")

            // Extract Range header
            var rangeHeader: String? = nil
            for line in lines {
                if line.lowercased().hasPrefix("range:") {
                    rangeHeader = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                }
            }

            print("[Proxy] \(method) Range: \(rangeHeader ?? "none")")

            if method == "HEAD" {
                self.handleHEAD(connection: connection)
            } else {
                self.handleGET(connection: connection, rangeHeader: rangeHeader)
            }
        }
    }

    private func handleHEAD(connection: NWConnection) {
        var request = URLRequest(url: backendURL)
        request.httpMethod = "HEAD"
        request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard let httpResp = response as? HTTPURLResponse else {
                connection.cancel()
                return
            }
            var headers = "HTTP/1.1 \(httpResp.statusCode) OK\r\n"
            if let ct = httpResp.value(forHTTPHeaderField: "Content-Type") {
                headers += "Content-Type: \(ct)\r\n"
            }
            if let cl = httpResp.value(forHTTPHeaderField: "Content-Length") {
                headers += "Content-Length: \(cl)\r\n"
            }
            headers += "Accept-Ranges: bytes\r\n"
            headers += "Connection: close\r\n"
            headers += "\r\n"

            print("[Proxy] HEAD -> \(httpResp.statusCode)")

            connection.send(content: headers.data(using: .ascii), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }.resume()
    }

    private func handleGET(connection: NWConnection, rangeHeader: String?) {
        var request = URLRequest(url: backendURL)
        request.httpMethod = "GET"
        request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
        if let range = rangeHeader {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        let forwarder = StreamForwarder(connection: connection, range: rangeHeader)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: forwarder, delegateQueue: nil)
        forwarder.session = session
        let task = session.dataTask(with: request)
        forwarder.task = task
        task.resume()
    }
}

// Bridges URLSession streaming data to NWConnection
class StreamForwarder: NSObject, URLSessionDataDelegate {
    let connection: NWConnection
    let range: String?
    var session: URLSession?
    var task: URLSessionDataTask?
    private var bytesSent: Int64 = 0
    private var headerSent = false
    private let backpressure = DispatchSemaphore(value: 4)

    init(connection: NWConnection, range: String?) {
        self.connection = connection
        self.range = range
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResp = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        let status = httpResp.statusCode
        var headers = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"

        if let ct = httpResp.value(forHTTPHeaderField: "Content-Type") {
            headers += "Content-Type: \(ct)\r\n"
        }
        if let cl = httpResp.value(forHTTPHeaderField: "Content-Length") {
            headers += "Content-Length: \(cl)\r\n"
        }
        if let cr = httpResp.value(forHTTPHeaderField: "Content-Range") {
            headers += "Content-Range: \(cr)\r\n"
        }
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"

        print("[Proxy] GET -> HTTP \(status) Content-Length: \(httpResp.value(forHTTPHeaderField: "Content-Length") ?? "?")")

        connection.send(content: headers.data(using: .ascii), completion: .contentProcessed { _ in })
        headerSent = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        backpressure.wait()
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.backpressure.signal()
            if error != nil {
                // Client disconnected (seeking) - cancel backend
                self?.task?.cancel()
                self?.session?.invalidateAndCancel()
            }
        })
        bytesSent += Int64(data.count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let cancelled = (error as? URLError)?.code == .cancelled
        if !cancelled {
            print("[Proxy] Transfer complete (\(bytesSent) bytes)")
        } else {
            print("[Proxy] Connection closed by client (\(bytesSent) bytes sent)")
        }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            self.connection.cancel()
        })
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Follow redirects
        var req = request
        req.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
        completionHandler(req)
    }

    static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}

// MARK: - Probe Function

func probeStream(url: String, label: String) {
    print("--- [\(label)] Probing: \(url) ---")

    var inputCtx: UnsafeMutablePointer<AVFormatContext>?

    var opts: OpaquePointer?
    av_dict_set(&opts, "user_agent", "VLC/3.0.18 LibVLC/3.0.18", 0)
    av_dict_set(&opts, "timeout", "30000000", 0)
    av_dict_set(&opts, "reconnect", "1", 0)
    av_dict_set(&opts, "reconnect_streamed", "1", 0)
    av_dict_set(&opts, "reconnect_delay_max", "5", 0)
    av_dict_set(&opts, "probesize", "33554432", 0)
    av_dict_set(&opts, "analyzeduration", "30000000", 0)

    print("  Calling avformat_open_input...")
    var ret = avformat_open_input(&inputCtx, url, nil, &opts)
    av_dict_free(&opts)

    guard ret >= 0, let ctx = inputCtx else {
        print("  FAILED: avformat_open_input returned \(ret)")
        return
    }
    defer {
        var mctx: UnsafeMutablePointer<AVFormatContext>? = ctx
        avformat_close_input(&mctx)
    }

    print("  avformat_open_input OK, nb_streams=\(ctx.pointee.nb_streams)")

    print("  Calling avformat_find_stream_info...")
    ret = avformat_find_stream_info(ctx, nil)
    print("  avformat_find_stream_info returned \(ret), nb_streams=\(ctx.pointee.nb_streams)")
    guard ret >= 0 else {
        print("  FAILED: avformat_find_stream_info")
        return
    }

    print()
    print("  === av_dump_format (C code) ===")
    av_dump_format(ctx, 0, url, 0)
    print("  === end av_dump_format ===")
    print()

    let bestVideo = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
    let bestAudio = av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
    print("  av_find_best_stream: video=\(bestVideo) audio=\(bestAudio)")
    print()

    let streamCount = Int(ctx.pointee.nb_streams)
    print("  === Swift struct access ===")
    print("  MemoryLayout<AVStream>.size = \(MemoryLayout<AVStream>.size)")
    print("  MemoryLayout<AVStream>.stride = \(MemoryLayout<AVStream>.stride)")

    for i in 0..<streamCount {
        print("  --- Stream \(i) ---")

        guard let stream = ctx.pointee.streams[i] else {
            print("    stream pointer = nil")
            continue
        }
        print("    stream pointer = \(stream)")
        print("    .index = \(stream.pointee.index)")
        print("    .id = \(stream.pointee.id)")

        let codecpar = stream.pointee.codecpar
        print("    .codecpar (Swift) = \(String(describing: codecpar))")

        if let cp = codecpar {
            let codecType = cp.pointee.codec_type
            let codecId = cp.pointee.codec_id
            print("    .codecpar.codec_type = \(codecType.rawValue)")
            print("    .codecpar.codec_id = \(codecId.rawValue)")
            print("    .codecpar.width = \(cp.pointee.width)")
            print("    .codecpar.height = \(cp.pointee.height)")

            if let desc = avcodec_descriptor_get(codecId), let name = desc.pointee.name {
                print("    codec name = \(String(cString: name))")
            }
        } else {
            print("    *** codecpar is nil! Raw memory inspection: ***")
            let rawStream = UnsafeRawPointer(stream)

            // Expected: offset 0=av_class(8), 8=index(4), 12=id(4), 16=codecpar(8)
            let rawCodecpar = rawStream.load(fromByteOffset: 16, as: UnsafeRawPointer?.self)
            print("    RAW offset 16: \(String(describing: rawCodecpar))")

            if let ptr = rawCodecpar {
                let cp = ptr.assumingMemoryBound(to: AVCodecParameters.self)
                print("    RAW codecpar -> codec_type=\(cp.pointee.codec_type.rawValue) codec_id=\(cp.pointee.codec_id.rawValue) \(cp.pointee.width)x\(cp.pointee.height)")
            }

            // Dump first 48 bytes
            print("    Raw bytes:")
            for offset in stride(from: 0, to: 48, by: 8) {
                let val = rawStream.load(fromByteOffset: offset, as: UInt64.self)
                print("      +\(String(format: "%2d", offset)): 0x\(String(format: "%016llx", val))")
            }
        }

        print("    .time_base = \(stream.pointee.time_base.num)/\(stream.pointee.time_base.den)")
        print()
    }

    print("  === End Swift struct access ===")
    print()
}

// MARK: - Transmux Function

func transmuxStream(url: String) {
    print("--- Transmuxing: \(url) ---")

    var inputCtx: UnsafeMutablePointer<AVFormatContext>?
    var outputCtx: UnsafeMutablePointer<AVFormatContext>?

    var opts: OpaquePointer?
    av_dict_set(&opts, "user_agent", "VLC/3.0.18 LibVLC/3.0.18", 0)
    av_dict_set(&opts, "timeout", "30000000", 0)
    av_dict_set(&opts, "reconnect", "1", 0)
    av_dict_set(&opts, "reconnect_streamed", "1", 0)
    av_dict_set(&opts, "reconnect_delay_max", "5", 0)
    av_dict_set(&opts, "probesize", "33554432", 0)
    av_dict_set(&opts, "analyzeduration", "30000000", 0)

    var ret = avformat_open_input(&inputCtx, url, nil, &opts)
    av_dict_free(&opts)
    guard ret >= 0, let inCtx = inputCtx else {
        print("  FAILED: avformat_open_input returned \(ret)")
        return
    }
    defer {
        var mctx: UnsafeMutablePointer<AVFormatContext>? = inCtx
        avformat_close_input(&mctx)
    }

    ret = avformat_find_stream_info(inCtx, nil)
    guard ret >= 0 else {
        print("  FAILED: avformat_find_stream_info returned \(ret)")
        return
    }

    av_dump_format(inCtx, 0, url, 0)

    let streamCount = Int(inCtx.pointee.nb_streams)

    // Helper: get codecpar via raw pointer if Swift binding fails
    func getCodecpar(streamIndex: Int) -> UnsafeMutablePointer<AVCodecParameters>? {
        guard let stream = inCtx.pointee.streams[streamIndex] else { return nil }
        if let cp = stream.pointee.codecpar { return cp }
        // Fall back to raw offset 16
        let raw = UnsafeRawPointer(stream)
        guard let ptr = raw.load(fromByteOffset: 16, as: UnsafeRawPointer?.self) else { return nil }
        print("  [WORKAROUND] Using raw pointer at offset 16 for stream \(streamIndex)")
        return UnsafeMutablePointer<AVCodecParameters>(mutating: ptr.assumingMemoryBound(to: AVCodecParameters.self))
    }

    let outputDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("transmux-cli-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let mp4Path = outputDir.appendingPathComponent("stream.mp4").path

    // Use MP4 directly (HLS muxer not available in this build)
    ret = avformat_alloc_output_context2(&outputCtx, nil, "mp4", mp4Path)
    guard ret >= 0, let outCtx = outputCtx else {
        print("  FAILED: couldn't create output context (\(ret))")
        return
    }
    defer {
        if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
        avformat_free_context(outCtx)
    }

    var streamMapping = [Int](repeating: -1, count: streamCount)
    var outIdx: Int32 = 0

    for i in 0..<streamCount {
        guard let cp = getCodecpar(streamIndex: i) else {
            print("  Stream \(i): no codecpar, skipping")
            continue
        }
        let codecType = cp.pointee.codec_type
        guard codecType == AVMEDIA_TYPE_VIDEO || codecType == AVMEDIA_TYPE_AUDIO else { continue }

        if let stream = inCtx.pointee.streams[i],
           stream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC != 0 {
            print("  Stream \(i): attached pic, skipping")
            continue
        }

        streamMapping[i] = Int(outIdx)
        outIdx += 1

        guard let outStream = avformat_new_stream(outCtx, nil) else {
            print("  FAILED: avformat_new_stream")
            return
        }
        ret = avcodec_parameters_copy(outStream.pointee.codecpar, cp)
        guard ret >= 0 else {
            print("  FAILED: avcodec_parameters_copy returned \(ret)")
            return
        }
        outStream.pointee.codecpar.pointee.codec_tag = 0

        let typeName = codecType == AVMEDIA_TYPE_VIDEO ? "video" : "audio"
        print("  Mapped stream \(i) (\(typeName)) -> output \(outIdx - 1)")
    }

    guard outIdx > 0 else {
        print("  FAILED: no streams mapped")
        return
    }

    // MP4 fragmented options
    var muxOpts: OpaquePointer?
    av_dict_set(&muxOpts, "movflags", "frag_keyframe+empty_moov+default_base_moof", 0)

    if outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
        ret = avio_open(&outCtx.pointee.pb, mp4Path, AVIO_FLAG_WRITE)
        guard ret >= 0 else {
            av_dict_free(&muxOpts)
            print("  FAILED: avio_open returned \(ret)")
            return
        }
    }

    ret = avformat_write_header(outCtx, &muxOpts)
    av_dict_free(&muxOpts)
    guard ret >= 0 else {
        print("  FAILED: avformat_write_header returned \(ret)")
        return
    }

    var packet = av_packet_alloc()
    defer { av_packet_free(&packet) }

    var packetCount = 0
    let maxPackets = 500

    while packetCount < maxPackets {
        ret = av_read_frame(inCtx, packet)
        if ret < 0 { break }

        guard let pkt = packet else { break }
        let si = Int(pkt.pointee.stream_index)
        guard si < streamCount, streamMapping[si] >= 0 else {
            av_packet_unref(pkt)
            continue
        }

        guard let inStream = inCtx.pointee.streams[si] else {
            av_packet_unref(pkt)
            continue
        }
        let outStreamIdx = Int32(streamMapping[si])
        guard let outStream = outCtx.pointee.streams[Int(outStreamIdx)] else {
            av_packet_unref(pkt)
            continue
        }

        pkt.pointee.stream_index = outStreamIdx
        av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
        pkt.pointee.pos = -1

        ret = av_interleaved_write_frame(outCtx, pkt)
        packetCount += 1

        if packetCount % 100 == 0 {
            print("  Written \(packetCount) packets...")
        }
    }

    av_write_trailer(outCtx)

    print()
    print("  Transmux complete! \(packetCount) packets written")
    print("  Output: \(outputDir.path)")

    if let files = try? FileManager.default.contentsOfDirectory(atPath: outputDir.path) {
        for f in files.sorted() {
            let path = outputDir.appendingPathComponent(f).path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = attrs?[.size] as? Int ?? 0
            print("    \(f) (\(size) bytes)")
        }
    }
}

// MARK: - Run

// Always probe direct first
probeStream(url: inputURL, label: "Direct")

if useProxy {
    guard let backendURL = URL(string: inputURL) else {
        print("Invalid URL")
        exit(1)
    }

    print()
    print("=== Starting proxy on port 9200 ===")
    let proxy = MiniProxy(backendURL: backendURL, port: 9200)
    do {
        try proxy.start()
    } catch {
        print("Failed to start proxy: \(error)")
        exit(1)
    }

    // Give listener time to bind
    Thread.sleep(forTimeInterval: 0.5)

    let proxyURL = "http://localhost:9200/0"
    print()
    probeStream(url: proxyURL, label: "Proxy")

    if doTransmux {
        print()
        transmuxStream(url: proxyURL)
    }

    proxy.stop()
} else if doTransmux {
    print()
    transmuxStream(url: inputURL)
}

print()
print("=== Done ===")
