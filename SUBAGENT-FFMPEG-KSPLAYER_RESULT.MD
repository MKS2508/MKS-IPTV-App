# KSPlayer Algorithm Deep Dive

## 1. A/V Sync Algorithm

### Location: `Sources/KSPlayer/AVPlayer/KSOptions.swift` (Lines 356-398)

### Core Implementation: `videoClockSync` Method

```swift
open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: Int) -> (Double, ClockProcessType) {
    let desire = main.getTime() - videoDelay
    let diff = nextVideoTime - desire
    if diff >= 1 / fps / 2 {
        // Frame is ahead - wait (remain)
        videoClockDelayCount = 0
        return (diff, .remain)
    } else {
        if diff < -4 / fps {
            // Frame is behind - escalation needed
            videoClockDelayCount += 1
            if frameCount == 1 {
                // Single frame buffered - aggressive drop
                if diff < -1, videoClockDelayCount % 10 == 0 {
                    return (diff, .dropGOPPacket)  // Drop to next keyframe
                } else if videoClockDelayCount % 5 == 0 {
                    return (diff, .dropNextFrame)  // Drop single frame
                } else {
                    return (diff, .next)           // Continue
                }
            } else {
                // Multiple frames buffered - escalate based on severity
                if diff < -8, videoClockDelayCount % 100 == 0 {
                    return (diff, .seek)           // Seek to sync
                }
                if diff < -1, videoClockDelayCount % 10 == 0 {
                    return (diff, .flush)          // Flush decode queue
                }
                if videoClockDelayCount % 2 == 0 {
                    return (diff, .dropNextFrame)  // Drop every other frame
                } else {
                    return (diff, .next)
                }
            }
        } else {
            // Within tolerance
            videoClockDelayCount = 0
            return (diff, .next)
        }
    }
}
```

### Frame Drop Escalation Strategy

| Delay Level | Threshold | Count Trigger | Action |
|------------|-----------|---------------|--------|
| Normal | `diff >= 1/(2*fps)` | N/A | `.remain` (wait) |
| Minor | `diff < -4/fps` | Every call | Increment `videoClockDelayCount` |
| Moderate (1 frame) | `diff < -1` | Every 10 counts | `.dropGOPPacket` |
| Minor (1 frame) | `diff < -4/fps` | Every 5 counts | `.dropNextFrame` |
| Severe (multi) | `diff < -8` | Every 100 counts | `.seek` |
| Moderate (multi) | `diff < -1` | Every 10 counts | `.flush` |
| Light (multi) | `diff < -4/fps` | Every 2 counts | `.dropNextFrame` |

### KSClock Implementation (`Model.swift` Lines 667-679)

```swift
public struct KSClock {
    public private(set) var lastMediaTime = CACurrentMediaTime()
    public internal(set) var position = Int64(0)
    public internal(set) var time = CMTime.zero {
        didSet {
            lastMediaTime = CACurrentMediaTime()
        }
    }

    func getTime() -> TimeInterval {
        time.seconds + CACurrentMediaTime() - lastMediaTime
    }
}
```

**Clock Design:**
- Uses `CACurrentMediaTime()` for monotonic timing
- `lastMediaTime` tracks when clock was last updated
- `getTime()` interpolates current position between updates
- Thread-safe via value semantics (struct)

### Audio vs Video Master Clock (`MEPlayerItem.swift` Lines 772-774)

```swift
func mainClock() -> KSClock {
    isAudioStalled ? videoClock : audioClock
}
```

**Logic:**
- **Audio master** (default): Uses `audioClock` when audio is playing
- **Video master** (fallback): Uses `videoClock` when audio stalls or is absent
- `isAudioStalled` is set to `true` when audio track finishes or doesn't exist

---

## 2. Buffering Algorithm

### Location: `KSOptions.swift` (Lines 163-197)

### Core Implementation: `playable` Method

```swift
open func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
    let packetCount = capacitys.map(\.packetCount).min() ?? 0
    let frameCount = capacitys.map(\.frameCount).min() ?? 0
    let isEndOfFile = capacitys.allSatisfy(\.isEndOfFile)
    let loadedTime = capacitys.map(\.loadedTime).min() ?? 0
    let progress = preferredForwardBufferDuration == 0 ? 100 : loadedTime * 100.0 / preferredForwardBufferDuration
    
    let isPlayable = capacitys.allSatisfy { capacity in
        // EOF with no packets - playable (nothing left)
        if capacity.isEndOfFile && capacity.packetCount == 0 {
            return true
        }
        // Need at least 2 frames
        guard capacity.frameCount >= 2 else {
            return false
        }
        // EOF with frames - playable
        if capacity.isEndOfFile {
            return true
        }
        // Sync decode modes - always playable
        if (syncDecodeVideo && capacity.mediaType == .video) || 
           (syncDecodeAudio && capacity.mediaType == .audio) {
            return true
        }
        // First load or seek - special handling
        if isFirst || isSeek {
            if capacity.mediaType == .audio || isSecondOpen {
                if isFirst {
                    return true  // Instant start for audio/secondOpen
                } else {
                    return capacity.loadedTime >= self.preferredForwardBufferDuration / 2
                }
            }
        }
        // Normal playback - need full buffer
        return capacity.loadedTime >= self.preferredForwardBufferDuration
    }
    return LoadingState(loadedTime: loadedTime, progress: progress, ...)
}
```

### Buffer Thresholds

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `preferredForwardBufferDuration` | 3.0s | Minimum buffer to start playback |
| `maxBufferDuration` | 30.0s | Maximum buffer before pausing read |

### Buffering State Machine (`MEPlayerItem.swift` Lines 698-715)

```swift
func codecDidChangeCapacity() {
    let loadingState = options.playable(capacitys: videoAudioTracks, isFirst: isFirst, isSeek: isSeek)
    delegate?.sourceDidChange(loadingState: loadingState)
    if loadingState.isPlayable {
        isFirst = false
        isSeek = false
        if loadingState.loadedTime > options.maxBufferDuration {
            // Buffer full - pause reading
            adaptableVideo(loadingState: loadingState)
            pause()
        } else if loadingState.loadedTime < options.maxBufferDuration / 2 {
            // Buffer low - resume reading
            resume()
        }
    } else {
        resume()  // Always read when not playable
        adaptableVideo(loadingState: loadingState)
    }
}
```

### Rebuffering Logic

**Trigger conditions:**
- `frameCount == 0 && packetCount == 0 && preferredForwardBufferDuration != 0`
- Transitions from `loadState = .playable` to `.loading`

**Recovery:**
- Reads resume automatically
- `isPlayable` becomes true when buffer fills to threshold

---

## 3. Adaptive Bitrate Algorithm

### Location: `KSOptions.swift` (Lines 199-217) + `PlayerDefines.swift` (Lines 148-161)

### Data Structure

```swift
public struct VideoAdaptationState {
    public struct BitRateState {
        let bitRate: Int64
        let time: TimeInterval
    }
    public let bitRates: [Int64]          // Sorted list of available bitrates
    public let duration: TimeInterval
    public internal(set) var fps: Float
    public internal(set) var bitRateStates: [BitRateState]  // History
    public internal(set) var currentPlaybackTime: TimeInterval = 0
    public internal(set) var isPlayable: Bool = false
    public internal(set) var loadedCount: Int = 0  // packets + frames
}
```

### Switching Decision (`adaptable` method)

```swift
open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)? {
    guard let state, 
          let last = state.bitRateStates.last,
          CACurrentMediaTime() - last.time > maxBufferDuration / 2,  // Cooldown
          let index = state.bitRates.firstIndex(of: last.bitRate)
    else { return nil }
    
    // Calculate buffer health
    let isUp = state.loadedCount > Int(Double(state.fps) * maxBufferDuration / 2)
    
    // Must agree with playability
    if isUp != state.isPlayable {
        return nil  // Indeterminate state
    }
    
    if isUp {
        // Buffer healthy - try higher bitrate
        if index < state.bitRates.endIndex - 1 {
            return (last.bitRate, state.bitRates[index + 1])
        }
    } else {
        // Buffer starved - drop bitrate
        if index > state.bitRates.startIndex {
            return (last.bitRate, state.bitRates[index - 1])
        }
    }
    return nil
}
```

### Switching Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| Cooldown | `maxBufferDuration / 2` (15s) | Minimum time between switches |
| Up-switch buffer | `fps * maxBufferDuration / 2` frames | Buffer must exceed this |
| Down-switch | `isPlayable == false` | When buffer runs low |

### ABR Execution (`MEPlayerItem.swift` Lines 736-757)

```swift
private func adaptableVideo(loadingState: LoadingState) {
    guard !options.videoDisable, videoAdaptation != nil, 
          !loadingState.isEndOfFile, !loadingState.isSeek, state != .seeking
    else { return }
    
    videoAdaptation?.loadedCount = track.packetCount + track.frameCount
    videoAdaptation?.currentPlaybackTime = currentPlaybackTime
    videoAdaptation?.isPlayable = loadingState.isPlayable
    
    guard let (oldBitRate, newBitrate) = options.adaptable(state: videoAdaptation),
          oldBitRate != newBitrate,
          let newFFmpegAssetTrack = assetTracks.first(where: { $0.bitRate == newBitrate })
    else { return }
    
    // Switch tracks
    assetTracks.first { $0.bitRate == oldBitRate }?.isEnabled = false
    newFFmpegAssetTrack.isEnabled = true
    findBestAudio(videoTrack: newFFmpegAssetTrack)
    
    // Record switch
    let bitRateState = VideoAdaptationState.BitRateState(bitRate: newBitrate, time: CACurrentMediaTime())
    videoAdaptation?.bitRateStates.append(bitRateState)
    delegate?.sourceDidChange(oldBitRate: oldBitRate, newBitrate: newBitrate)
}
```

---

## 4. Memory Management Patterns

### CircularBuffer Backpressure (`CircularBuffer.swift` Lines 43-82)

```swift
public func push(_ value: Item) {
    condition.lock()
    defer { condition.unlock() }
    if destroyed { return }
    
    _buffer[Int(tailIndex & mask)] = value
    
    // Insertion sort for sorted buffers
    if sorted {
        var index = tailIndex
        while index > headIndex {
            guard let item = _buffer[Int((index - 1) & mask)] else { break }
            if item.timestamp <= _buffer[Int(index & mask)]!.timestamp { break }
            _buffer.swapAt(Int((index - 1) & mask), Int(index & mask))
            index -= 1
        }
    }
    
    tailIndex &+= 1
    
    if _count >= maxCount {
        if expanding {
            _doubleCapacity()  // Grow buffer
        } else {
            condition.wait()    // Block producer (backpressure)
        }
    } else if _count == 1 {
        condition.signal()      // Wake consumer
    }
}
```

**Backpressure Strategy:**
- **Expanding mode** (default): Doubles capacity when full
- **Fixed mode** (`expanding=false`): Blocks producer on `condition.wait()`

### CVPixelBufferPool Usage (`Resample.swift` Lines 72, 96-118)

```swift
class VideoSwresample: FrameChange {
    private var pool: CVPixelBufferPool?
    
    private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize: Int32) {
        if self.format == format, self.width == width, self.height == height {
            return  // Reuse pool if format unchanged
        }
        // ... format setup ...
        
        pool = CVPixelBufferPool.create(
            width: dstWidth, 
            height: dstHeight, 
            bytesPerRowAlignment: linesize, 
            pixelFormatType: pixelFormatType
        )
    }
    
    func transfer(frame: AVFrame) -> PixelBufferProtocol? {
        // ...
        return autoreleasepool {
            var pbuf: CVPixelBuffer?
            let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbuf)
            // ... copy data ...
            return pbuf
        }
    }
}
```

**Pool Benefits:**
- Reuses pixel buffer allocations
- Format-specific pool cached per `setup()` call
- `autoreleasepool` ensures timely release

### MTLBuffer Allocation (`PixelBufferProtocol.swift` Lines 215-243)

```swift
init(frame: AVFrame) {
    // ...
    for i in 0 ..< planeCount {
        let alignment = MetalRender.device.minimumLinearTextureAlignment(for: formats[i])
        lineSize.append(bytesPerRow[i].alignment(value: alignment))
        
        let buffer: MTLBuffer?
        let size = lineSize[i]
        let byteCount = bytesPerRow[i]
        
        if byteCount == size {
            // Zero-copy: aligned, direct allocation
            buffer = MetalRender.device.makeBuffer(bytes: bytes[i]!, length: height * size)
        } else {
            // Copy required: misaligned data
            buffer = MetalRender.device.makeBuffer(length: heights[i] * lineSize[i])
            let contents = buffer?.contents()
            // Row-by-row copy for alignment
            var j = 0
            while j < height {
                contents?.advanced(by: j * size).copyMemory(
                    from: source.advanced(by: j * byteCount), 
                    byteCount: byteCount
                )
                j += 1
            }
        }
        buffers.append(buffer)
    }
}
```

### AudioFrame Manual Memory Management (`Model.swift` Lines 244-295)

```swift
public final class AudioFrame: MEFrame {
    public let dataSize: Int
    public var data: [UnsafeMutablePointer<UInt8>?]
    
    public init(dataSize: Int, audioFormat: AVAudioFormat) {
        self.dataSize = dataSize
        self.audioFormat = audioFormat
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
    }
    
    deinit {
        for i in 0 ..< data.count {
            data[i]?.deinitialize(count: dataSize)
            data[i]?.deallocate()
        }
        data.removeAll()
    }
}
```

---

## 5. Thread Synchronization

### NSCondition Wait/Signal Pattern (`CircularBuffer.swift`)

**Producer (push):**
```swift
public func push(_ value: Item) {
    condition.lock()
    defer { condition.unlock() }
    
    // ... add item ...
    
    if _count >= maxCount && !expanding {
        condition.wait()        // BLOCK until space available
    } else if _count == 1 {
        condition.signal()      // WAKE one consumer
    }
}
```

**Consumer (pop):**
```swift
public func pop(wait: Bool = false, where predicate: ((Item, Int) -> Bool)? = nil) -> Item? {
    condition.lock()
    defer { condition.unlock() }
    
    if destroyed { return nil }
    
    if headIndex == tailIndex {
        if wait {
            condition.wait()    // BLOCK until data available
            if destroyed || headIndex == tailIndex { return nil }
        } else {
            return nil
        }
    }
    
    // ... remove item ...
    
    if _count == maxCount >> 1 {
        condition.signal()      // WAKE producer at 50% capacity
    }
    return item
}
```

**Shutdown pattern:**
```swift
public func shutdown() {
    destroyed = true
    flush()  // Resets indices, broadcasts to all waiters
}

public func flush() {
    condition.lock()
    defer { condition.unlock() }
    headIndex = 0
    tailIndex = 0
    _buffer.removeAll(keepingCapacity: !destroyed)
    condition.broadcast()  // WAKE ALL waiters
}
```

### OperationQueue Configuration

**Read Thread (`MEPlayerItem.swift` Lines 421-433):**
```swift
private func read() {
    readOperation = BlockOperation { [weak self] in
        Thread.current.name = (self.operationQueue.name ?? "") + "_read"
        Thread.current.stackSize = KSOptions.stackSize  // 65536 bytes
        self.readThread()
    }
    readOperation?.queuePriority = .veryHigh
    readOperation?.qualityOfService = .userInteractive
    operationQueue.addOperation(readOperation)
}
```

**Decode Thread (`MEPlayerItemTrack.swift` Lines 219-231):**
```swift
override func decode() {
    decodeOperation = BlockOperation { [weak self] in
        Thread.current.name = self.operationQueue.name
        Thread.current.stackSize = KSOptions.stackSize
        self.decodeThread()
    }
    decodeOperation.queuePriority = .veryHigh
    decodeOperation.qualityOfService = .userInteractive
    operationQueue.addOperation(decodeOperation)
}
```

### Deadlock Avoidance

1. **Lock ordering:** Always acquire `condition.lock()` before modifying queue state
2. **Single lock per queue:** Each `CircularBuffer` has its own `NSCondition`
3. **Shutdown flag:** `destroyed` checked after wait returns to abort cleanly
4. **Broadcast on flush:** All waiters wake to see `destroyed=true` or empty queue

---

## 6. Error Recovery Patterns

### VideoToolbox Session Recovery (`VideoToolboxDecode.swift` Lines 30-93)

```swift
private var needReconfig = false

func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
    if needReconfig {
        // Rebuild session (e.g., foreground resume)
        session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
        doFlushCodec()
        needReconfig = false
    }
    
    // ... decode attempt ...
    
    let status = VTDecompressionSessionDecodeFrame(...)
    
    // Error handling in callback:
    guard status == noErr else {
        if status == kVTInvalidSessionErr || 
           status == kVTVideoDecoderMalfunctionErr || 
           status == kVTVideoDecoderBadDataErr {
            if packet.isKeyFrame {
                completionHandler(.failure(error))  // Fatal on keyframe
            } else {
                needReconfig = true  // Defer to next call
            }
        }
        return
    }
}
```

### Decoder Fallback: VT → FFmpeg (`MEPlayerItemTrack.swift` Lines 160-166)

```swift
fileprivate func doDecode(packet: Packet) {
    let decoder = decoderMap.value(for: packet.assetTrack.trackID, 
                                   default: makeDecode(assetTrack: packet.assetTrack))
    
    decoder.decodeFrame(from: packet) { [weak self] result in
        do {
            let frame = try result.get()
            // ... success path ...
        } catch {
            if decoder is VideoToolboxDecode {
                // Fallback: VT failed, try FFmpeg software
                decoder.shutdown()
                self?.decoderMap[packet.assetTrack.trackID] = FFmpegDecode(
                    assetTrack: packet.assetTrack, 
                    options: self?.options
                )
                KSLog("VideoCodec switch to software decompression")
                self?.doDecode(packet: packet)  // Retry with new decoder
            } else {
                self?.state = .failed  // Software decoder also failed
            }
        }
    }
}
```

### Corrupt Packet Handling (`FFmpegDecode.swift` Lines 173-185)

```swift
while true {
    let result = avcodec_receive_frame(codecContext, coreFrame)
    if result == 0, let inputFrame = coreFrame {
        // ... process frame ...
    } else {
        if result == AVError.eof.code {
            avcodec_flush_buffers(codecContext)
            break
        } else if result == AVError.tryAgain.code {
            break  // Need more packets
        } else {
            // Corrupt data or decode error
            let error = NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: result)
            KSLog(error)
            completionHandler(.failure(error))
        }
    }
}
```

### Network Error Recovery (`MEPlayerItem.swift` Lines 111-113, formatContextOptions)

```swift
// Reconnection settings (set in init())
formatContextOptions["reconnect"] = 1
formatContextOptions["reconnect_streamed"] = 1
```

---

## 7. Performance Optimizations

### Zero-Copy Paths

**1. VideoToolbox Direct Output (`Resample.swift` Lines 86-93):**
```swift
func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
    let frame = VideoVTBFrame(fps: fps, isDovi: isDovi)
    if avframe.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
        // Direct CVPixelBuffer from hardware decoder - NO COPY
        frame.corePixelBuffer = unsafeBitCast(avframe.pointee.data.3, to: CVPixelBuffer.self)
    } else {
        frame.corePixelBuffer = transfer(frame: avframe.pointee)
    }
    return frame
}
```

**2. MTLBuffer Aligned Copy (`PixelBufferProtocol.swift` Lines 226-228):**
```swift
if byteCount == size {
    // Aligned - single copy
    buffer = MetalRender.device.makeBuffer(bytes: bytes[i]!, length: height * size)
}
```

### sws_scale Bypass (`Resample.swift` Lines 96-118)

```swift
private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize: Int32) {
    if self.format == format, self.width == width, self.height == height {
        return  // Skip reconfig
    }
    
    if format.osType() != nil {
        // Native format - NO sws_scale needed
        sws_freeContext(imgConvertCtx)
        imgConvertCtx = nil
    } else {
        // Non-native - setup conversion
        imgConvertCtx = sws_getCachedContext(...)
    }
}
```

### CVPixelBuffer IOSurface Texture (`MetalRender.swift` Lines 158-169)

```swift
static func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture] {
    guard let iosurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
        return []
    }
    let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
    return (0 ..< pixelBuffer.planeCount).compactMap { index in
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(...)
        // Direct IOSurface binding - NO CPU copy
        return device.makeTexture(descriptor: descriptor, iosurface: iosurface, plane: index)
    }
}
```

### Frame Reuse (`MEPlayerItemTrack.swift` Lines 145-152)

```swift
// Seek filtering - frames before seek time are silently dropped
if self.seekTime > 0 {
    let timestamp = frame.timestamp + frame.duration
    if timestamp <= 0 || frame.timebase.cmtime(for: timestamp).seconds < self.seekTime {
        return  // Drop frame without decode
    } else {
        self.seekTime = 0.0
    }
}
```

---

## 8. Filter Graph Management

### MEFilter Dynamic Changes (`Filter.swift` Lines 105-149)

```swift
public func filter(options: KSOptions, inputFrame: UnsafeMutablePointer<AVFrame>, 
                   completionHandler: (UnsafeMutablePointer<AVFrame>) -> Void) {
    let filters: String = isAudio ? 
        options.audioFilters.joined(separator: ",") : 
        options.videoFilters.joined(separator: ",")
    
    guard !filters.isEmpty else {
        completionHandler(inputFrame)  // Passthrough
        return
    }
    
    var params = AVBufferSrcParameters()
    params.format = inputFrame.pointee.format
    params.time_base = timebase.rational
    params.width = inputFrame.pointee.width
    params.height = inputFrame.pointee.height
    // ... more params ...
    
    // Rebuild graph if parameters changed
    if self.params != params || self.filters != filters {
        self.params = params
        self.filters = filters
        if !setup(filters: filters) {
            completionHandler(inputFrame)  // Fallback passthrough
            return
        }
    }
    
    let ret = av_buffersrc_add_frame_flags(bufferSrcContext, inputFrame, 0)
    if ret < 0 { return }
    
    while av_buffersink_get_frame_flags(bufferSinkContext, inputFrame, 0) >= 0 {
        completionHandler(inputFrame)
        av_frame_unref(inputFrame)  // MUST unref to prevent leak
    }
}
```

### Deinterlace Auto-Detection (`KSOptions.swift` Lines 271-301)

```swift
private var idetTypeMap = [VideoInterlacingType: UInt]()

open func filter(log: String) {
    if log.starts(with: "Repeated Field:"), autoDeInterlace {
        for str in log.split(separator: ",") {
            let map = str.split(separator: ":")
            if map.count >= 2, String(map[0].trimmingCharacters(in: .whitespaces)) == "Multi frame" {
                if let type = VideoInterlacingType(rawValue: map[1].trimmingCharacters(...)) {
                    idetTypeMap[type] = (idetTypeMap[type] ?? 0) + 1
                    
                    let tff = idetTypeMap[.tff] ?? 0
                    let bff = idetTypeMap[.bff] ?? 0
                    let progressive = idetTypeMap[.progressive] ?? 0
                    let undetermined = idetTypeMap[.undetermined] ?? 0
                    
                    // Threshold: 100 frames majority
                    if progressive - tff - bff > 100 {
                        videoInterlacingType = .progressive
                        autoDeInterlace = false
                    } else if bff - progressive > 100 {
                        videoInterlacingType = .bff
                        autoDeInterlace = false
                    } else if tff - progressive > 100 {
                        videoInterlacingType = .tff
                        autoDeInterlace = false
                    }
                }
            }
        }
    }
}
```

### Auto Deinterlace Filter Insertion (`KSOptions.swift` Lines 310-336)

```swift
open func process(assetTrack: some MediaPlayerTrack) {
    if assetTrack.mediaType == .video {
        if [FFmpegFieldOrder.bb, .bt, .tt, .tb].contains(assetTrack.fieldOrder) {
            // Interlaced content detected
            hardwareDecode = false  // Force software for yadif
            asynchronousDecompression = false
            
            let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
            var yadifMode = KSOptions.yadifMode  // 1 = double framerate
            
            if KSOptions.deInterlaceAddIdet {
                videoFilters.append("idet")  // Detection filter
            }
            videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")
            
            if yadifMode == 1 || yadifMode == 3 {
                assetTrack.nominalFrameRate = assetTrack.nominalFrameRate * 2
            }
        }
    }
}
```

### Audio Filter Graph Setup (`Filter.swift` Lines 26-32, 68-103)

```swift
public init(timebase: Timebase, isAudio: Bool, nominalFrameRate: Float, options: KSOptions) {
    graph = avfilter_graph_alloc()
    graph?.pointee.opaque = Unmanaged.passUnretained(options).toOpaque()  // For log callback
    self.timebase = timebase
    self.isAudio = isAudio
    self.nominalFrameRate = nominalFrameRate
}

// Uses "abuffer" -> filters -> "abuffersink" topology for audio
```

---

## Summary of Key Constants

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `preferredForwardBufferDuration` | 3.0s | `KSOptions.swift:461` | Min buffer to start |
| `maxBufferDuration` | 30.0s | `KSOptions.swift:463` | Max buffer before pause |
| `stackSize` | 65536 | `Model.swift:83` | Thread stack size |
| ABR cooldown | `maxBufferDuration/2` (15s) | `KSOptions.swift:200` | Time between switches |
| Deinterlace threshold | 100 frames | `KSOptions.swift:283-291` | Detection confidence |
| Drop trigger | `diff < -4/fps` | `KSOptions.swift:364` | Frame late threshold |
| Seek trigger | `diff < -8` | `KSOptions.swift:378` | Severe desync |
| `videoClockDelayCount` modulo | 2, 5, 10, 100 | `KSOptions.swift:368-391` | Escalation intervals |

---

## Key Algorithm Pseudocode

### A/V Sync Algorithm (Simplified)

```
function videoClockSync(mainClock, nextVideoTime, fps, frameCount):
    desiredTime = mainClock.getTime() - videoDelay
    diff = nextVideoTime - desiredTime
    
    if diff >= 1/(2*fps):
        // Frame is early - wait
        videoClockDelayCount = 0
        return (diff, REMAIN)
    
    if diff < -4/fps:
        videoClockDelayCount++
        
        if frameCount == 1:
            // Low buffer - conservative
            if diff < -1 AND videoClockDelayCount % 10 == 0:
                return (diff, DROP_GOP)
            if videoClockDelayCount % 5 == 0:
                return (diff, DROP_FRAME)
            return (diff, NEXT)
        else:
            // Full buffer - aggressive
            if diff < -8 AND videoClockDelayCount % 100 == 0:
                return (diff, SEEK)
            if diff < -1 AND videoClockDelayCount % 10 == 0:
                return (diff, FLUSH)
            if videoClockDelayCount % 2 == 0:
                return (diff, DROP_FRAME)
            return (diff, NEXT)
    
    // Within tolerance
    videoClockDelayCount = 0
    return (diff, NEXT)
```

### Buffering Algorithm (Simplified)

```
function isPlayable(capacities, isFirst, isSeek):
    for each capacity in capacities:
        if capacity.isEOF AND capacity.packetCount == 0:
            continue  // Nothing left to buffer
        
        if capacity.frameCount < 2:
            return false  // Need minimum frames
        
        if capacity.isEOF:
            continue  // Have frames, EOF reached
        
        if syncDecodeMode(capacity):
            continue  // Sync decode always playable
        
        if isFirst OR isSeek:
            if capacity.mediaType == AUDIO:
                if isFirst:
                    return true  // Quick start
                if capacity.loadedTime < bufferDuration/2:
                    return false
            else:
                if capacity.loadedTime < bufferDuration:
                    return false
        
        if capacity.loadedTime < bufferDuration:
            return false
    
    return true
```

### ABR Algorithm (Simplified)

```
function adaptable(state):
    if state == null OR state.bitRateStates.empty:
        return null
    
    lastSwitch = state.bitRateStates.last
    timeSinceSwitch = currentTime - lastSwitch.time
    
    if timeSinceSwitch < maxBufferDuration/2:
        return null  // Cooldown
    
    currentIndex = state.bitRates.indexOf(lastSwitch.bitRate)
    if currentIndex == null:
        return null
    
    bufferHealth = state.loadedCount > fps * maxBufferDuration/2
    
    if bufferHealth != state.isPlayable:
        return null  // Indeterminate
    
    if bufferHealth:
        // Try higher quality
        if currentIndex < state.bitRates.length - 1:
            return (lastSwitch.bitRate, state.bitRates[currentIndex + 1])
    else:
        // Drop quality
        if currentIndex > 0:
            return (lastSwitch.bitRate, state.bitRates[currentIndex - 1])
    
    return null
```

---

## Patterns to Adopt

1. **Clock Interpolation**: Use `CACurrentMediaTime()` with interpolation for smooth timing
2. **Escalation Ladders**: Multi-level frame drop strategy based on severity
3. **Buffer State Machine**: Clear transitions between loading/playable/full states
4. **ABR Cooldown**: Prevent bitrate thrashing with time-based cooldowns
5. **Zero-Copy Paths**: Leverage IOSurface and hardware decoder direct output
6. **Decoder Fallback Chain**: VT → FFmpeg software with automatic retry
7. **Backpressure via NSCondition**: Block producers when queues full
8. **Broadcast Shutdown**: Wake all waiters when destroying queues

---

## Análisis: ¿Son fácilmente superables?

### **Fáciles de superar:**

#### 1. ABR Algorithm - Muy básico
- Solo usa buffer level (no considera throughput, latencia, CPU)
- Cooldown de 15s es arbitrario y lento
- No hay predicción de bandwidth
- **Mejora sugerida**: ABR basado en throughput + buffer hybrid (como BOLA o dynamic algorithms)

```swift
// ABR mejorado - considerar múltiples factores
func adaptableEnhanced(state: VideoAdaptationState, throughput: Double) -> (Int64, Int64)? {
    let bufferHealth = state.loadedCount / state.fps  // segundos de buffer
    let safeBitrate = throughput * 0.8  // 80% del throughput estimado
    
    // Seleccionar bitrate más alto que sea seguro
    let candidates = state.bitRates.filter { $0 <= safeBitrate }
    if let target = candidates.last, target != currentBitrate {
        return (currentBitrate, target)
    }
    return nil
}
```

#### 2. Deinterlace Detection - Simplón
- Threshold de 100 frames = ~4 segundos de contenido mal renderizado
- Solo detecta TFF/BFF/progressive
- **Mejora sugerida**: Detección más agresiva (20-30 frames) o machine learning

```swift
// Mejora: threshold adaptativo
let detectionThreshold: Int = {
    if nominalFrameRate >= 50 { return 50 }   // High FPS = faster detection
    return 30  // Standard content
}()
```

#### 3. Network Recovery - Minimal
- Solo `reconnect=1, reconnect_streamed=1` en FFmpeg options
- Sin exponential backoff
- Sin circuit breaker pattern
- **Mejora sugerida**: Retry con jitter y health checks

```swift
// Network recovery mejorado
class NetworkRecovery {
    private var attemptCount = 0
    private let maxAttempts = 5
    private let baseDelay: TimeInterval = 1.0
    
    func shouldRetry() -> Bool {
        attemptCount < maxAttempts
    }
    
    func nextDelay() -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attemptCount))
        let jitter = Double.random(in: 0...0.3) * exponential
        attemptCount += 1
        return exponential + jitter
    }
    
    func reset() {
        attemptCount = 0
    }
}
```

### **Competitivos pero mejorables:**

#### 4. A/V Sync - Buen diseño base
- Escalación por niveles es sólida
- Pero los thresholds son hardcoded (`-8`, `-4/fps`)
- **Mejora sugerida**: Adaptive thresholds según content type

```swift
// Thresholds adaptativos
struct SyncThresholds {
    let dropFrame: TimeInterval      // -4/fps por defecto
    let flushQueue: TimeInterval     // -1s por defecto
    let seekRecovery: TimeInterval   // -8s por defecto
    
    static func forContent(isLive: Bool, fps: Double) -> SyncThresholds {
        if isLive {
            // Live: más agresivo para mantener latencia baja
            return SyncThresholds(
                dropFrame: -2/fps,
                flushQueue: -0.5,
                seekRecovery: -3
            )
        } else {
            // VOD: más tolerante para smoother playback
            return SyncThresholds(
                dropFrame: -4/fps,
                flushQueue: -1,
                seekRecovery: -8
            )
        }
    }
}
```

#### 5. Buffering - Funcional pero estático
- 3s start buffer, 30s max son conservadores
- No adapta a network conditions
- **Mejora sugerida**: Buffer dinámico según bandwidth estimado

```swift
// Buffer adaptativo
func calculateBufferDuration(throughput: Double, bitrate: Int64) -> (start: TimeInterval, max: TimeInterval) {
    let safetyFactor = 1.5
    let estimatedDownloadTime = Double(bitrate) / throughput
    
    if throughput > Double(bitrate) * 2 {
        // Bandwidth holgada - buffers pequeños
        return (start: 2.0, max: 15.0)
    } else if throughput > Double(bitrate) * 1.2 {
        // Bandwidth ajustada - buffers moderados
        return (start: 3.0, max: 30.0)
    } else {
        // Bandwidth crítica - buffers grandes
        return (start: 5.0, max: 60.0)
    }
}
```

### **Difíciles de superar (sólidos):**

#### 6. Thread Sync (CircularBuffer) - Bien diseñado
- NSCondition con broadcast shutdown es correcto
- Backpressure con expansión dinámica
- Insertion sort para sorted buffers es O(n) pero acceptable
- **Veredicto**: Copiar el patrón, difícil mejorar sin complejidad innecesaria

#### 7. Zero-Copy Paths - Optimizado
- IOSurface directo a Metal texture
- CVPixelBufferPool reuse
- sws_scale bypass cuando formato coincide
- **Veredicto**: Difícil mejorar sin acceso a APIs privadas de Apple

#### 8. Decoder Fallback - Robusto
- VT → FFmpeg con retry automático
- `needReconfig` pattern para recovery de sesión
- Manejo de errores diferenciado por tipo
- **Veredicto**: Patrón correcto, solo ajustar timeouts si es necesario

---

## Matriz de Prioridad de Mejoras

| Área | Facilidad | ROI | Prioridad | Esfuerzo |
|------|-----------|-----|-----------|----------|
| ABR Algorithm | ⭐⭐⭐⭐⭐ Muy fácil | Alto | **P1** | 2-3 días |
| Network Recovery | ⭐⭐⭐⭐ Fácil | Medio-Alto | **P1** | 1-2 días |
| Buffering Adaptivo | ⭐⭐⭐ Moderado | Medio | **P2** | 3-4 días |
| A/V Sync Tuning | ⭐⭐ Moderado | Bajo | **P3** | 1-2 días |
| Deinterlace Detection | ⭐⭐⭐ Fácil | Bajo | **P3** | 1 día |
| Thread Sync | ⭐ Difícil | Bajo | P4 (no cambiar) | N/A |
| Zero-Copy | ⭐ Difícil | Bajo | P4 (no cambiar) | N/A |
| Decoder Fallback | ⭐ Difícil | Bajo | P4 (no cambiar) | N/A |

---

## Recomendación de Implementación

### Fase 1: Quick Wins (1 semana)
1. **ABR mejorado**: Throughput-based selection + buffer hybrid
2. **Network recovery**: Exponential backoff con jitter

### Fase 2: Optimización (2 semanas)
3. **Buffering adaptativo**: Ajustar según bandwidth
4. **Deinterlace más rápido**: Reducir threshold de detección

### Fase 3: Fine Tuning (1 semana)
5. **A/V Sync adaptativo**: Thresholds por tipo de contenido

### No tocar (ya están bien)
- CircularBuffer synchronization
- Zero-copy paths
- Decoder fallback chain

---

## Conclusión

KSPlayer tiene una base sólida en las áreas críticas de threading y memory management, pero las capas de alto nivel (ABR, buffering, recovery) son relativamente básicas y ofrecen oportunidades claras de mejora.

**El 80% del valor está en mejorar ABR + Network Recovery**. El resto es optimization fine-tuning que puede hacerse iterativamente.

---

## Sección Avanzada: Superando lo "Difícil"

Las siguientes áreas fueron marcadas como "difíciles de superar" pero con repensamiento arquitectónico pueden mejorarse significativamente.

---

## 6. Thread Sync - Supperando CircularBuffer

### Problemas del diseño actual de KSPlayer

1. **NSCondition es heavyweight** - Cada wait/signal involucra kernel syscall
2. **Lock único global** - Productor y consumidor compiten por el mismo lock
3. **Sin prioridad de threads** - Un consumidor lento puede bloquear todo
4. **Broadcast innecesario** - En shutdown despierta todos los threads

### Solución: Lock-Free Ring Buffer con MPMC

#### Estructura de Archivos Propuesta

```
Sources/
├── Core/
│   ├── Synchronization/           # Thread sync primitives
│   │   ├── include/
│   │   │   └── ks_ring_buffer.h   # C header - lock-free ring buffer
│   │   ├── KSRingBuffer.swift     # Swift wrapper
│   │   └── KSSyncTypes.swift      # Type aliases y helpers
│   │
│   ├── Memory/                    # Memory management
│   │   ├── include/
│   │   │   └── ks_hazard_ptr.h    # C header - hazard pointers
│   │   ├── KSBufferPool.swift     # Buffer pool manager
│   │   ├── KSFrameBuffer.swift    # Frame buffer wrapper
│   │   └── KSMetalAllocator.swift # Metal-specific allocation
│   │
│   └── Rendering/                 # GPU rendering
│       ├── KSTextureFactory.swift # Texture creation
│       └── KSZeroCopyPath.swift   # Zero-copy pipelines
│
├── Decoder/
│   ├── Backends/
│   │   ├── KSDecoderBackend.swift      # Protocol
│   │   ├── KSVideoToolboxDecoder.swift # Hardware (standard)
│   │   ├── KSVideoToolboxLiveDecoder.swift # Hardware (low-latency)
│   │   ├── KSFFmpegSoftDecoder.swift   # Software fallback
│   │   └── KSFFmpegHWDecoder.swift     # FFmpeg + hardware
│   │
│   ├── KSDecoderOrchestra.swift    # Multi-backend coordinator
│   ├── KSDecoderMetrics.swift      # Performance tracking
│   └── KSDecoderSelection.swift    # Adaptive selection logic
│
└── include/
    └── ks_core.h                   # Umbrella header
```

---

```c
// ks_ring_buffer.h - Lock-Free Multi-Producer Multi-Consumer Ring Buffer
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void **buffer;
    size_t capacity;
    size_t element_size;
    _Atomic size_t head;  // Consumer index
    _Atomic size_t tail;  // Producer index
    _Atomic bool shutdown_flag;
} MPMCRingBuffer;

// Crear buffer
MPMCRingBuffer* mpmc_create(size_t capacity, size_t element_size) {
    MPMCRingBuffer *rb = aligned_alloc(64, sizeof(MPMCRingBuffer));  // Cache-line aligned
    rb->buffer = aligned_alloc(64, capacity * sizeof(void*));
    rb->capacity = capacity;
    rb->element_size = element_size;
    atomic_init(&rb->head, 0);
    atomic_init(&rb->tail, 0);
    atomic_init(&rb->shutdown_flag, false);
    
    // Pre-allocate elements
    for (size_t i = 0; i < capacity; i++) {
        rb->buffer[i] = aligned_alloc(64, element_size);
    }
    return rb;
}

// Push non-blocking - retorna true si éxito
bool mpmc_push(MPMCRingBuffer *rb, void *data) {
    if (atomic_load(&rb->shutdown_flag)) return false;
    
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_relaxed);
    size_t next_tail = (tail + 1) % rb->capacity;
    
    // Check if full
    size_t head = atomic_load_explicit(&rb->head, memory_order_acquire);
    if (next_tail == head) {
        return false;  // Buffer full - backpressure
    }
    
    // Copy data
    memcpy(rb->buffer[tail], data, rb->element_size);
    
    // Publish - release semantics ensures data is visible before index update
    atomic_store_explicit(&rb->tail, next_tail, memory_order_release);
    return true;
}

// Pop non-blocking - retorna true si éxito
bool mpmc_pop(MPMCRingBuffer *rb, void *out_data) {
    if (atomic_load(&rb->shutdown_flag)) return false;
    
    size_t head = atomic_load_explicit(&rb->head, memory_order_relaxed);
    
    // Check if empty
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);
    if (head == tail) {
        return false;  // Buffer empty
    }
    
    // Copy data
    memcpy(out_data, rb->buffer[head], rb->element_size);
    
    // Advance head
    size_t next_head = (head + 1) % rb->capacity;
    atomic_store_explicit(&rb->head, next_head, memory_order_release);
    return true;
}

// Peek sin remover
bool mpmc_peek(MPMCRingBuffer *rb, size_t offset, void *out_data) {
    size_t head = atomic_load_explicit(&rb->head, memory_order_acquire);
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);
    
    if (head == tail) return false;
    
    size_t count = (tail - head + rb->capacity) % rb->capacity;
    if (offset >= count) return false;
    
    size_t index = (head + offset) % rb->capacity;
    memcpy(out_data, rb->buffer[index], rb->element_size);
    return true;
}

// Shutdown instantáneo sin broadcast
void mpmc_shutdown(MPMCRingBuffer *rb) {
    atomic_store(&rb->shutdown_flag, true);
    // No broadcast needed - each thread checks flag on next operation
}

// Obtener count sin lock
size_t mpmc_count(MPMCRingBuffer *rb) {
    size_t head = atomic_load_explicit(&rb->head, memory_order_acquire);
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);
    return (tail - head + rb->capacity) % rb->capacity;
}
```

### Wrapper Swift con Semaphore para blocking semantics

```swift
// KSRingBuffer.swift - Swift wrapper
import Foundation

final class LockFreeRingBuffer<T> {
    private let buffer: UnsafeMutableRawPointer
    private let capacity: Int
    private let elementSize: Int
    private var head: UInt64 = 0  // Packed: index + epoch
    private var tail: UInt64 = 0
    private let semaphore = DispatchSemaphore(value: 0)
    private var shutdown = false
    
    init(capacity: Int) {
        self.capacity = capacity
        self.elementSize = MemoryLayout<T>.stride
        self.buffer = .allocate(byteCount: capacity * elementSize, alignment: 64)
    }
    
    // Blocking push con timeout
    func push(_ element: T, timeout: TimeInterval = .infinity) -> Bool {
        guard !shutdown else { return false }
        
        let deadline = timeout == .infinity ? .distantFuture : DispatchTime.now() + timeout
        
        while true {
            if tryPush(element) {
                semaphore.signal()  // Wake one consumer
                return true
            }
            
            // Backpressure - wait for space
            if semaphore.wait(timeout: deadline) == .timedOut {
                return false
            }
        }
    }
    
    // Non-blocking push
    private func tryPush(_ element: T) -> Bool {
        let tailIdx = Int(tail & 0xFFFFFFFF)
        let nextTail = (tailIdx + 1) % capacity
        let headIdx = Int(head & 0xFFFFFFFF)
        
        guard nextTail != headIdx else { return false }
        
        buffer.advanced(by: tailIdx * elementSize)
              .assumingMemoryBound(to: T.self)
              .pointee = element
        
        tail &+= 1
        return true
    }
    
    // Blocking pop con timeout
    func pop(timeout: TimeInterval = .infinity) -> T? {
        guard !shutdown else { return nil }
        
        let deadline = timeout == .infinity ? .distantFuture : DispatchTime.now() + timeout
        
        while true {
            if let element = tryPop() {
                return element
            }
            
            if semaphore.wait(timeout: deadline) == .timedOut {
                return nil
            }
        }
    }
    
    // Non-blocking pop
    private func tryPop() -> T? {
        let headIdx = Int(head & 0xFFFFFFFF)
        let tailIdx = Int(tail & 0xFFFFFFFF)
        
        guard headIdx != tailIdx else { return nil }
        
        let element = buffer.advanced(by: headIdx * elementSize)
                          .assumingMemoryBound(to: T.self)
                          .pointee
        
        head &+= 1
        return element
    }
    
    // Peek sin remover - para A/V sync lookahead
    func peek(offset: Int = 0) -> T? {
        let headIdx = Int(head & 0xFFFFFFFF)
        let tailIdx = Int(tail & 0xFFFFFFFF)
        let count = (tailIdx - headIdx + capacity) % capacity
        
        guard offset < count else { return nil }
        
        let index = (headIdx + offset) % capacity
        return buffer.advanced(by: index * elementSize)
                    .assumingMemoryBound(to: T.self)
                    .pointee
    }
    
    func shutdown() {
        shutdown = true
        // Wake all waiters
        for _ in 0..<capacity {
            semaphore.signal()
        }
    }
}
```

### Ventajas sobre KSPlayer

| Aspecto | KSPlayer | Nuestra versión |
|---------|----------|-----------------|
| Lock contention | NSCondition global | Lock-free atomic ops |
| Kernel syscalls | Cada wait/signal | Solo en semaphore (raro) |
| Peek capability | No | Sí, para lookahead |
| Cache efficiency | Buffer disperso | Cache-line aligned |
| Shutdown | Broadcast a todos | Flag atómico instantáneo |

---

## 7. Zero-Copy - Superando IOSurface/MTLBuffer

### Problemas del diseño actual de KSPlayer

1. **CVPixelBufferPool es opaco** - No control de allocation strategy
2. **MTLBuffer creation es sync** - Puede bloquear en allocation
3. **Sin reuse pool inteligente** - Buffers se crean/destruyen constantemente
4. **Format conversion overhead** - sws_scale aunque sea mínimo

### Solución: Buffer Pool con Hazard Pointers

```c
// ks_hazard_ptr.h - Zero-copy buffer pool con hazard pointers
#include <stdatomic.h>
#include <stdbool.h>

typedef struct {
    void *data;
    size_t size;
    size_t capacity;
    _Atomic int refcount;
    _Atomic bool in_hazard;  // Being accessed by thread
    uint64_t frame_id;
    int format;  // AVPixelFormat
    int width;
    int height;
} FrameBuffer;

typedef struct {
    FrameBuffer *buffers;
    size_t pool_size;
    _Atomic size_t *hazard_pointers;  // Per-thread hazard slots
    size_t num_threads;
    _Atomic uint64_t next_frame_id;
} BufferPool;

// Crear pool
BufferPool* buffer_pool_create(size_t pool_size, size_t buffer_capacity, size_t num_threads) {
    BufferPool *pool = malloc(sizeof(BufferPool));
    pool->buffers = aligned_alloc(64, pool_size * sizeof(FrameBuffer));
    pool->pool_size = pool_size;
    pool->hazard_pointers = calloc(num_threads, sizeof(_Atomic size_t));
    pool->num_threads = num_threads;
    atomic_init(&pool->next_frame_id, 0);
    
    for (size_t i = 0; i < pool_size; i++) {
        pool->buffers[i].data = aligned_alloc(64, buffer_capacity);
        pool->buffers[i].capacity = buffer_capacity;
        pool->buffers[i].size = 0;
        atomic_init(&pool->buffers[i].refcount, 0);
        atomic_init(&pool->buffers[i].in_hazard, false);
        pool->buffers[i].frame_id = 0;
    }
    return pool;
}

// Acquire buffer para escritura (decoder thread)
FrameBuffer* buffer_pool_acquire(BufferPool *pool, int format, int width, int height) {
    for (size_t i = 0; i < pool->pool_size; i++) {
        FrameBuffer *buf = &pool->buffers[i];
        
        // Try to claim unused buffer
        int expected = 0;
        if (atomic_compare_exchange_strong(&buf->refcount, &expected, 1)) {
            // Check if being read (hazard)
            if (atomic_load(&buf->in_hazard)) {
                atomic_store(&buf->refcount, 0);
                continue;
            }
            
            buf->format = format;
            buf->width = width;
            buf->height = height;
            buf->frame_id = atomic_fetch_add(&pool->next_frame_id, 1);
            return buf;
        }
    }
    return NULL;  // Pool exhausted
}

// Retain buffer para lectura (render thread)
bool buffer_pool_retain(BufferPool *pool, FrameBuffer *buf, size_t thread_id) {
    // Set hazard pointer
    size_t index = buf - pool->buffers;
    atomic_store(&pool->hazard_pointers[thread_id], index + 1);  // +1 porque 0 = NULL
    
    // Validate buffer still valid
    if (atomic_load(&buf->refcount) == 0) {
        atomic_store(&pool->hazard_pointers[thread_id], 0);
        return false;
    }
    
    atomic_fetch_add(&buf->refcount, 1);
    atomic_store(&buf->in_hazard, true);
    return true;
}

// Release buffer después de lectura
void buffer_pool_release(BufferPool *pool, FrameBuffer *buf, size_t thread_id) {
    atomic_store(&buf->in_hazard, false);
    atomic_store(&pool->hazard_pointers[thread_id], 0);
    
    if (atomic_fetch_sub(&buf->refcount, 1) == 1) {
        // Last reference - buffer returned to pool
        buf->size = 0;
    }
}

// Check if safe to reclaim (no hazard pointers pointing to buffer)
bool buffer_pool_can_reclaim(BufferPool *pool, FrameBuffer *buf) {
    size_t index = buf - pool->buffers;
    for (size_t i = 0; i < pool->num_threads; i++) {
        if (atomic_load(&pool->hazard_pointers[i]) == index + 1) {
            return false;
        }
    }
    return true;
}
```

### Metal Buffer Pool con Async Allocation

```swift
// MetalBufferPool.swift
import Metal

final class MetalBufferPool {
    private let device: MTLDevice
    private var pools: [MTLPixelFormat: [MTLBuffer]] = [:]
    private let lock = NSLock()
    private var allocationQueue = DispatchQueue(label: "buffer.alloc", qos: .userInteractive)
    
    struct BufferKey: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }
    
    private var availableBuffers: [BufferKey: [MTLBuffer]] = [:]
    private var inUseBuffers: [BufferKey: [MTLBuffer]] = [:]
    
    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        self.device = device
    }
    
    // Acquire buffer - async para no bloquear
    func acquire(key: BufferKey, completion: @escaping (MTLBuffer?) -> Void) {
        lock.lock()
        
        // Try reuse
        if var available = availableBuffers[key], !available.isEmpty {
            let buffer = available.removeLast()
            availableBuffers[key] = available
            
            if inUseBuffers[key] == nil { inUseBuffers[key] = [] }
            inUseBuffers[key]?.append(buffer)
            
            lock.unlock()
            completion(buffer)
            return
        }
        
        lock.unlock()
        
        // Allocate async
        allocationQueue.async { [weak self] in
            guard let self = self else { return }
            
            let bytesPerRow = self.alignedBytesPerRow(width: key.width, format: key.pixelFormat)
            let totalSize = bytesPerRow * key.height
            
            let buffer = self.device.makeBuffer(length: totalSize, options: .storageModeShared)
            
            self.lock.lock()
            if self.inUseBuffers[key] == nil { self.inUseBuffers[key] = [] }
            self.inUseBuffers[key]?.append(buffer!)
            self.lock.unlock()
            
            completion(buffer)
        }
    }
    
    // Return buffer al pool
    func release(buffer: MTLBuffer, key: BufferKey) {
        lock.lock()
        defer { lock.unlock() }
        
        inUseBuffers[key]?.removeAll { $0 === buffer }
        
        if availableBuffers[key] == nil { availableBuffers[key] = [] }
        availableBuffers[key]?.append(buffer)
    }
    
    // Pre-warm pool
    func prewarm(key: BufferKey, count: Int) {
        let bytesPerRow = alignedBytesPerRow(width: key.width, format: key.pixelFormat)
        let totalSize = bytesPerRow * key.height
        
        lock.lock()
        if availableBuffers[key] == nil { availableBuffers[key] = [] }
        
        for _ in 0..<count {
            if let buffer = device.makeBuffer(length: totalSize, options: .storageModeShared) {
                availableBuffers[key]?.append(buffer)
            }
        }
        lock.unlock()
    }
    
    private func alignedBytesPerRow(width: Int, format: MTLPixelFormat) -> Int {
        let bytesPerPixel: Int
        switch format {
        case .bgra8Unorm, .rgba8Unorm: bytesPerPixel = 4
        case .r16Float: bytesPerPixel = 2
        case .rg8Unorm: bytesPerPixel = 2
        case .r8Unorm: bytesPerPixel = 1
        default: bytesPerPixel = 4
        }
        
        let alignment = device.minimumLinearTextureAlignment(for: format)
        let rawBytesPerRow = width * bytesPerPixel
        return ((rawBytesPerRow + alignment - 1) / alignment) * alignment
    }
}
```

### Zero-Copy Path: AVFrame → CVPixelBuffer → MTLTexture

```swift
// ZeroCopyTextureProvider.swift
import Metal
import AVFoundation

final class ZeroCopyTextureProvider {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private let bufferPool: MetalBufferPool
    
    init() {
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        self.bufferPool = MetalBufferPool(device: device)
    }
    
    // Zero-copy: IOSurface → MTLTexture
    func textureFromIOSurface(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = MTLPixelFormat(CVPixelBufferGetPixelFormatType(pixelBuffer))
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let cvTexture = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    // Zero-copy path completo: AVFrame → Texture
    func processAVFrame(_ frame: UnsafeMutablePointer<AVFrame>) -> MTLTexture? {
        let avFrame = frame.pointee
        
        // Path 1: VideoToolbox ya nos dio CVPixelBuffer
        if avFrame.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            let pixelBuffer = unsafeBitCast(avFrame.data.3, to: CVPixelBuffer.self)
            return textureFromIOSurface(pixelBuffer)
        }
        
        // Path 2: Frame en GPU memory (CUDA/OpenGL interop)
        if avFrame.hw_frames_ctx != nil {
            return textureFromHWFrame(avFrame)
        }
        
        // Path 3: Software frame - necesitamos copy, pero a buffer pool
        return textureFromSoftwareFrame(avFrame)
    }
    
    private func textureFromHWFrame(_ avFrame: AVFrame) -> MTLTexture? {
        // TODO: Implementar CUDA/OpenGL → Metal interop
        return nil
    }
    
    private func textureFromSoftwareFrame(_ avFrame: AVFrame) -> MTLTexture? {
        let width = Int(avFrame.width)
        let height = Int(avFrame.height)
        
        let key = MetalBufferPool.BufferKey(
            width: width,
            height: height,
            pixelFormat: .rgba8Unorm
        )
        
        var resultTexture: MTLTexture?
        let semaphore = DispatchSemaphore(value: 0)
        
        bufferPool.acquire(key: key) { [weak self] buffer in
            guard let self = self, let buffer = buffer else {
                semaphore.signal()
                return
            }
            
            // Copy frame data to buffer (unavoidable for software decode)
            let dest = buffer.contents()
            for plane in 0..<3 {
                let src = avFrame.data[plane]
                let linesize = Int(avFrame.linesize[plane])
                let planeHeight = plane == 0 ? height : height / 2
                
                for row in 0..<planeHeight {
                    memcpy(
                        dest.advanced(by: row * linesize),
                        src!.advanced(by: row * linesize),
                        linesize
                    )
                }
            }
            
            // Create texture from buffer (zero-copy view)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            descriptor.storageMode = .shared
            
            resultTexture = buffer.makeTexture(
                descriptor: descriptor,
                offset: 0,
                bytesPerRow: self.bufferPool.alignedBytesPerRow(width: width, format: .rgba8Unorm)
            )
            
            semaphore.signal()
        }
        
        semaphore.wait()
        return resultTexture
    }
}
```

### Ventajas sobre KSPlayer

| Aspecto | KSPlayer | Nuestra versión |
|---------|----------|-----------------|
| Buffer allocation | On-demand, sync | Pool pre-warmed, async |
| Reuse | CVPixelBufferPool opaco | Hazard pointers explícitos |
| Thread safety | Implicit | Hazard pointers garantizan safety |
| Memory fragmentation | Alto (alloc/free constantes) | Bajo (pool fijo) |
| Async allocation | No | Sí, no bloquea decode |

---

## 8. Decoder Fallback - Superando VT → FFmpeg

### Problemas del diseño actual de KSPlayer

1. **Fallback solo 2 niveles** - VT → FFmpeg, sin más opciones
2. **Sin profiling de performance** - No aprende cuál decoder es mejor
3. **Recovery manual** - `needReconfig` flag es reactivo
4. **Sin codec negotiation** - No prueba codecs alternativos

### Solución: Decoder Orchestra con Adaptive Selection

```swift
// DecoderOrchestra.swift - Multiple decoder backends con adaptive selection

enum DecoderBackend: Int, CaseIterable {
    case videoToolbox = 0      // Hardware, Apple
    case videoToolboxLowLatency = 1  // VT con low-latency config
    case ffmpegSoftware = 2    // Software, FFmpeg
    case ffmpegHardware = 3    // FFmpeg + VAAPI/VideoToolbox
    case metalCompute = 4      // Metal-based (custom)
}

struct DecoderMetrics {
    var framesDecoded: Int = 0
    var totalDecodeTime: TimeInterval = 0
    var errors: Int = 0
    var avgDecodeTime: TimeInterval { framesDecoded > 0 ? totalDecodeTime / Double(framesDecoded) : 0 }
    var errorRate: Double { framesDecoded > 0 ? Double(errors) / Double(framesDecoded) : 0 }
}

protocol DecoderBackendProtocol {
    var backend: DecoderBackend { get }
    var metrics: DecoderMetrics { get }
    
    func canDecode(track: MediaPlayerTrack) -> Bool
    func decode(packet: Packet) async throws -> MEFrame
    func flush()
    func shutdown()
}

final class DecoderOrchestra {
    private var backends: [DecoderBackend: DecoderBackendProtocol] = [:]
    private var activeBackend: DecoderBackend = .videoToolbox
    private var metrics: [DecoderBackend: DecoderMetrics] = [:]
    private let selectionQueue = DispatchQueue(label: "decoder.selection")
    
    // Learning: cuál backend funciona mejor para cada content type
    private var preferenceCache: [ContentType: DecoderBackend] = [:]
    
    enum ContentType: Hashable {
        case h264(profile: Int, level: Int)
        case hevc(profile: Int, level: Int)
        case av1
        case vp9
        case other(String)
    }
    
    init() {
        // Register all backends
        register(VideoToolboxDecoder())
        register(VideoToolboxLowLatencyDecoder())
        register(FFmpegSoftwareDecoder())
        // register(FFmpegHardwareDecoder())
        // register(MetalComputeDecoder())  // Future
    }
    
    private func register(_ decoder: DecoderBackendProtocol) {
        backends[decoder.backend] = decoder
        metrics[decoder.backend] = DecoderMetrics()
    }
    
    // Decode con fallback cascade
    func decode(packet: Packet, contentType: ContentType) async throws -> MEFrame {
        let candidates = prioritizeBackends(for: contentType)
        
        for backend in candidates {
            guard let decoder = backends[backend] else { continue }
            
            do {
                let startTime = CFAbsoluteTimeGetCurrent()
                let frame = try await decoder.decode(packet: packet)
                let decodeTime = CFAbsoluteTimeGetCurrent() - startTime
                
                updateMetrics(backend: backend, decodeTime: decodeTime, error: false)
                activeBackend = backend
                
                return frame
            } catch {
                updateMetrics(backend: backend, decodeTime: 0, error: true)
                
                // Try next backend
                continue
            }
        }
        
        throw DecoderError.allBackendsFailed
    }
    
    private func prioritizeBackends(for contentType: ContentType) -> [DecoderBackend] {
        selectionQueue.sync {
            // Check cache first
            if let cached = preferenceCache[contentType] {
                return buildFallbackChain(preferred: cached)
            }
            
            // Default priority based on content
            let defaults: [DecoderBackend]
            switch contentType {
            case .h264, .hevc:
                defaults = [.videoToolbox, .videoToolboxLowLatency, .ffmpegSoftware]
            case .av1, .vp9:
                defaults = [.ffmpegSoftware, .videoToolbox]  // VT support limited
            default:
                defaults = DecoderBackend.allCases
            }
            
            // Sort by historical performance
            return defaults.sorted { a, b in
                let mA = metrics[a] ?? DecoderMetrics()
                let mB = metrics[b] ?? DecoderMetrics()
                
                // Prefer lower error rate, then faster decode
                if mA.errorRate != mB.errorRate {
                    return mA.errorRate < mB.errorRate
                }
                return mA.avgDecodeTime < mB.avgDecodeTime
            }
        }
    }
    
    private func buildFallbackChain(preferred: DecoderBackend) -> [DecoderBackend] {
        var chain = [preferred]
        
        // Add alternatives based on type
        switch preferred {
        case .videoToolbox:
            chain.append(.videoToolboxLowLatency)
            chain.append(.ffmpegSoftware)
        case .videoToolboxLowLatency:
            chain.append(.videoToolbox)
            chain.append(.ffmpegSoftware)
        case .ffmpegSoftware:
            chain.append(.videoToolbox)
        default:
            chain.append(contentsOf: DecoderBackend.allCases.filter { $0 != preferred })
        }
        
        return chain
    }
    
    private func updateMetrics(backend: DecoderBackend, decodeTime: TimeInterval, error: Bool) {
        selectionQueue.sync {
            var m = metrics[backend] ?? DecoderMetrics()
            if !error {
                m.framesDecoded += 1
                m.totalDecodeTime += decodeTime
            } else {
                m.errors += 1
            }
            metrics[backend] = m
            
            // Update preference cache after 100 frames
            if m.framesDecoded > 100 {
                let bestBackend = metrics
                    .filter { $0.value.framesDecoded > 50 }
                    .min { a, b in
                        let scoreA = a.value.avgDecodeTime * (1 + a.value.errorRate * 10)
                        let scoreB = b.value.avgDecodeTime * (1 + b.value.errorRate * 10)
                        return scoreA < scoreB
                    }
                
                if let best = bestBackend {
                    // Cache the best performer for this content type
                    // preferenceCache[contentType] = best.key
                }
            }
        }
    }
    
    // Proactive health check
    func performHealthCheck() async {
        for (backend, decoder) in backends {
            let m = metrics[backend] ?? DecoderMetrics()
            
            // If error rate > 20%, deprioritize
            if m.framesDecoded > 20 && m.errorRate > 0.2 {
                // Force reinitialize decoder
                decoder.shutdown()
                // Re-initialize lazily on next decode
            }
        }
    }
}

enum DecoderError: Error {
    case allBackendsFailed
    case decoderNotAvailable
    case corruptedPacket
}
```

### VideoToolbox con Low-Latency Config

```swift
// VideoToolboxLowLatencyDecoder.swift
import VideoToolbox

final class VideoToolboxLowLatencyDecoder: DecoderBackendProtocol {
    let backend: DecoderBackend = .videoToolboxLowLatency
    var metrics: DecoderMetrics = DecoderMetrics()
    
    private var session: VTDecompressionSession?
    private let callbackQueue = DispatchQueue(label: "vt.lowlatency.callback")
    
    func canDecode(track: MediaPlayerTrack) -> Bool {
        // Low-latency mode works best for live content
        return track.mediaType == .video && isCodecSupported(track.codecId)
    }
    
    private func isCodecSupported(_ codecId: AVCodecID) -> Bool {
        switch codecId {
        case AV_CODEC_ID_H264, AV_CODEC_ID_HEVC:
            return true
        default:
            return false
        }
    }
    
    func createSession(track: MediaPlayerTrack, options: KSOptions) -> VTDecompressionSession? {
        var session: VTDecompressionSession?
        
        // Low-latency configuration
        let decoderConfig = [
            kVTDecompressionPropertyKey_RealTime: kCFBooleanTrue!,
            // Don't wait for reference frames
            kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder: kCFBooleanTrue!,
        ] as CFDictionary
        
        var outputConfig = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            // Enable GPU direct rendering
            kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue!,
        ] as [CFString: Any] as CFDictionary
        
        // Create session with low-latency flags
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: track.formatDescription,
            decoderSpecification: decoderConfig,
            imageBufferAttributes: outputConfig,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        
        guard status == noErr else { return nil }
        
        // Set low-latency properties
        VTSessionSetProperty(
            session!,
            kVTSessionPropertyKey_RealTime,
            kCFBooleanTrue
        )
        
        // Disable frame reordering for lower latency
        if #available(macOS 12.0, iOS 15.0, *) {
            VTSessionSetProperty(
                session!,
                kVTSessionPropertyKey_PermitLowLatencyFrameReordering,
                kCFBooleanTrue
            )
        }
        
        return session
    }
    
    func decode(packet: Packet) async throws -> MEFrame {
        guard let session = session else {
            throw DecoderError.decoderNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var flags: VTDecodeFrameFlags = UInt32(kVTDecodeFrame_EnableAsynchronousDecompression)
            flags |= UInt32(kVTDecodeFrame_1xRealTimePlayback)  // Real-time priority
            
            let info = Unmanaged.passRetained(DecodeInfo(continuation: continuation))
            
            let status = VTDecompressionSessionDecodeFrame(
                session,
                packet.sampleBuffer,
                flags,
                info.toOpaque(),
                nil
            )
            
            if status != noErr {
                info.release()
                continuation.resume(throwing: DecoderError.corruptedPacket)
            }
        }
    }
    
    func flush() {
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }
    
    func shutdown() {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }
}

private class DecodeInfo {
    let continuation: CheckedContinuation<MEFrame, Error>
    init(continuation: CheckedContinuation<MEFrame, Error>) {
        self.continuation = continuation
    }
}
```

### Ventajas sobre KSPlayer

| Aspecto | KSPlayer | Nuestra versión |
|---------|----------|-----------------|
| Fallback levels | 2 (VT → FFmpeg) | N (configurable) |
| Performance tracking | No | Sí, por backend |
| Learning | No | Cache de preferencias |
| Low-latency mode | No | Sí, dedicado |
| Health checks | Reactivo | Proactivo |
| Codec negotiation | No | Sí, mejor backend por codec |

---

## Resumen de Mejoras "Difíciles"

| Área | Mejora Principal | Ganancia Esperada |
|------|------------------|-------------------|
| Thread Sync | Lock-free MPMC ring buffer | -50% lock contention, mejor latencia |
| Zero-Copy | Hazard pointers + async pool | -30% allocation overhead, pool reuse |
| Decoder Fallback | Orchestra con learning | Mejor recovery, auto-tuning |

**Tiempo estimado de implementación**: 3-4 semanas para las tres áreas.
