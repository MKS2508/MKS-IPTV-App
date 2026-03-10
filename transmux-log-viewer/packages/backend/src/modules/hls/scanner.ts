import logger from "@mks2508/better-logger";

const scanLog = logger.component("SegmentScanner");

/**
 * Scanned fMP4 segment descriptor
 *
 * @property byteOffset - Start of the moof box in stream.mp4
 * @property byteLength - Combined length of moof + mdat
 * @property durationTicks - Segment duration in timescale ticks (derived from gap between consecutive tfdt values)
 * @property decodeTicks - baseMediaDecodeTime from tfdt box
 */
export interface IScannedSegment {
  byteOffset: number;
  byteLength: number;
  durationTicks: number;
  decodeTicks: number;
}

/**
 * Cached scan state for a session's stream.mp4
 *
 * @property segments - Previously scanned segments
 * @property lastFileSize - File size at last scan
 * @property initSize - Size of ftyp + moov (init segment)
 * @property timescale - Media timescale from moov > trak > mdia > mdhd
 */
interface IScanCache {
  segments: IScannedSegment[];
  lastFileSize: number;
  initSize: number;
  timescale: number;
}

/**
 * Read a 32-bit unsigned big-endian integer from a buffer
 *
 * @param buf - Source buffer
 * @param offset - Byte offset to read from
 * @returns The 32-bit value
 */
function readU32(buf: Buffer, offset: number): number {
  return buf.readUInt32BE(offset);
}

/**
 * Read a 64-bit unsigned big-endian integer from a buffer
 *
 * JavaScript loses precision above 2^53 but for byte offsets and
 * decode timestamps in practice this is fine.
 *
 * @param buf - Source buffer
 * @param offset - Byte offset to read from
 * @returns The 64-bit value as a number
 */
function readU64(buf: Buffer, offset: number): number {
  const hi = buf.readUInt32BE(offset);
  const lo = buf.readUInt32BE(offset + 4);
  return hi * 0x100000000 + lo;
}

/**
 * Read a 4-character box type string from a buffer
 *
 * @param buf - Source buffer
 * @param offset - Byte offset to read from
 * @returns ASCII box type (e.g. "moof", "mdat", "moov")
 */
function readBoxType(buf: Buffer, offset: number): string {
  return buf.toString("ascii", offset, offset + 4);
}

/**
 * Parse the timescale from a moov box
 *
 * Walks moov > trak > mdia > mdhd to find the timescale field.
 * Only reads the first video track found.
 *
 * @param moovData - Buffer containing the full moov box content (after size+type header)
 * @returns Timescale value (e.g. 90000) or 90000 as default
 */
function parseTimescaleFromMoov(moovData: Buffer): number {
  let pos = 0;

  while (pos + 8 <= moovData.length) {
    const boxSize = readU32(moovData, pos);
    const boxType = readBoxType(moovData, pos + 4);

    if (boxSize < 8 || pos + boxSize > moovData.length) break;

    if (boxType === "trak") {
      // Search inside trak for mdia > mdhd
      const trakContent = moovData.subarray(pos + 8, pos + boxSize);
      const timescale = parseMdhdInTrak(trakContent);
      if (timescale > 0) return timescale;
    }

    pos += boxSize;
  }

  scanLog.warn("Could not find mdhd timescale, defaulting to 90000");
  return 90000;
}

/**
 * Search trak content for mdia > mdhd and extract timescale
 *
 * @param trakData - Buffer of trak box content (after size+type)
 * @returns Timescale or 0 if not found
 */
function parseMdhdInTrak(trakData: Buffer): number {
  let pos = 0;

  while (pos + 8 <= trakData.length) {
    const boxSize = readU32(trakData, pos);
    const boxType = readBoxType(trakData, pos + 4);

    if (boxSize < 8 || pos + boxSize > trakData.length) break;

    if (boxType === "mdia") {
      const mdiaContent = trakData.subarray(pos + 8, pos + boxSize);
      return parseMdhdInMdia(mdiaContent);
    }

    pos += boxSize;
  }

  return 0;
}

/**
 * Search mdia content for mdhd and extract timescale
 *
 * @param mdiaData - Buffer of mdia box content (after size+type)
 * @returns Timescale or 0 if not found
 */
function parseMdhdInMdia(mdiaData: Buffer): number {
  let pos = 0;

  while (pos + 8 <= mdiaData.length) {
    const boxSize = readU32(mdiaData, pos);
    const boxType = readBoxType(mdiaData, pos + 4);

    if (boxSize < 8 || pos + boxSize > mdiaData.length) break;

    if (boxType === "mdhd") {
      // mdhd: 8 header + 1 version + 3 flags + ...
      const version = mdiaData[pos + 8];
      if (version === 0) {
        // v0: 4 creation + 4 modification + 4 timescale + 4 duration
        return readU32(mdiaData, pos + 8 + 4 + 4 + 4);
      }
      // v1: 8 creation + 8 modification + 4 timescale + 8 duration
      return readU32(mdiaData, pos + 8 + 4 + 8 + 8);
    }

    pos += boxSize;
  }

  return 0;
}

/**
 * Extract baseMediaDecodeTime from a moof box buffer
 *
 * Walks moof > traf > tfdt to find the decode timestamp.
 *
 * @param moofData - Buffer of the full moof box (including size+type header)
 * @returns baseMediaDecodeTime or -1 if not found
 */
function parseTfdt(moofData: Buffer): number {
  // Skip moof header (8 bytes)
  let pos = 8;

  while (pos + 8 <= moofData.length) {
    const boxSize = readU32(moofData, pos);
    const boxType = readBoxType(moofData, pos + 4);

    if (boxSize < 8 || pos + boxSize > moofData.length) break;

    if (boxType === "traf") {
      const trafContent = moofData.subarray(pos + 8, pos + boxSize);
      return parseTfdtInTraf(trafContent);
    }

    pos += boxSize;
  }

  return -1;
}

/**
 * Search traf content for tfdt box and extract baseMediaDecodeTime
 *
 * @param trafData - Buffer of traf content (after size+type)
 * @returns baseMediaDecodeTime or -1 if not found
 */
function parseTfdtInTraf(trafData: Buffer): number {
  let pos = 0;

  while (pos + 8 <= trafData.length) {
    const boxSize = readU32(trafData, pos);
    const boxType = readBoxType(trafData, pos + 4);

    if (boxSize < 8 || pos + boxSize > trafData.length) break;

    if (boxType === "tfdt") {
      // tfdt: 8 header + 1 version + 3 flags + baseMediaDecodeTime
      const version = trafData[pos + 8];
      if (version === 0) {
        return readU32(trafData, pos + 12);
      }
      return readU64(trafData, pos + 12);
    }

    pos += boxSize;
  }

  return -1;
}

/**
 * fMP4 segment scanner for TransmuxCore output
 *
 * Scans a growing stream.mp4 file for moof/mdat segment boundaries.
 * Reads only box headers (8 bytes) and moof content (~200-400 bytes),
 * skipping mdat payloads for efficiency.
 *
 * Caches scan results per session — re-scans only when file size grows.
 *
 * @example
 * ```typescript
 * const scanner = new SegmentScanner();
 * const result = scanner.scan("session-123", "/tmp/mks-iptv-transmux-session-123");
 * // result.segments: IScannedSegment[]
 * // result.initSize: number (bytes)
 * // result.timescale: number
 * ```
 */
export class SegmentScanner {
  private cache: Map<string, IScanCache> = new Map();

  /**
   * Scan a session's stream.mp4 for fMP4 segments
   *
   * Incrementally scans from last known position when the file has grown.
   * Returns cached results if file size hasn't changed.
   *
   * @param sessionId - Session identifier for caching
   * @param outputDir - Path to session output directory (e.g. /tmp/mks-iptv-transmux-xxx)
   * @returns Scan result with segments, initSize, and timescale
   */
  async scan(
    sessionId: string,
    outputDir: string
  ): Promise<{
    segments: IScannedSegment[];
    initSize: number;
    timescale: number;
  }> {
    const filePath = `${outputDir}/stream.mp4`;
    const file = Bun.file(filePath);

    if (!(await file.exists())) {
      return { segments: [], initSize: 0, timescale: 90000 };
    }

    const fileSize = file.size;
    const cached = this.cache.get(sessionId);

    // Return cached if file hasn't grown
    if (cached && cached.lastFileSize === fileSize) {
      return {
        segments: cached.segments,
        initSize: cached.initSize,
        timescale: cached.timescale,
      };
    }

    // Determine where to start scanning
    const scanFrom = cached ? cached.lastFileSize : 0;
    const initSize = cached ? cached.initSize : 0;
    const timescale = cached ? cached.timescale : 0;
    const existingSegments = cached ? [...cached.segments] : [];

    try {
      const buf = Buffer.from(await file.arrayBuffer());
      let result: IScanCache;

      if (scanFrom === 0) {
        // Full scan from beginning
        result = this.fullScan(buf, fileSize);
      } else {
        // Incremental scan from last position
        result = this.incrementalScan(buf, fileSize, scanFrom, existingSegments, initSize, timescale);
      }

      this.cache.set(sessionId, result);
      return {
        segments: result.segments,
        initSize: result.initSize,
        timescale: result.timescale,
      };
    } catch (error) {
      scanLog.error(
        `Scan failed for ${sessionId}: ${error instanceof Error ? error.message : String(error)}`
      );
      return cached
        ? { segments: cached.segments, initSize: cached.initSize, timescale: cached.timescale }
        : { segments: [], initSize: 0, timescale: 90000 };
    }
  }

  /**
   * Full scan of stream.mp4 from byte 0
   *
   * Reads top-level boxes sequentially: ftyp, moov, then moof/mdat pairs.
   * Extracts timescale from moov and decode timestamps from each moof.
   *
   * @param buf - Full file buffer
   * @param fileSize - Current file size
   * @returns Complete scan cache
   */
  private fullScan(buf: Buffer, fileSize: number): IScanCache {
    let pos = 0;
    let initSize = 0;
    let timescale = 90000;
    const segments: IScannedSegment[] = [];
    let moofOffset = -1;
    let currentDecodeTicks = -1;

    while (pos + 8 <= fileSize) {
      // Prevent reading beyond buffer
      if (pos + 8 > buf.length) break;

      const boxSize = readU32(buf, pos);
      const boxType = readBoxType(buf, pos + 4);

      // Handle extended size (size == 1 means 64-bit size follows)
      let actualSize = boxSize;
      if (boxSize === 1 && pos + 16 <= buf.length) {
        actualSize = readU64(buf, pos + 8);
      }

      if (actualSize < 8) break;

      // Don't read past file boundary (file may still be growing)
      if (pos + actualSize > fileSize) break;

      switch (boxType) {
        case "ftyp":
        case "moov": {
          if (boxType === "moov") {
            // Parse timescale from moov
            const moovContent = buf.subarray(pos + 8, pos + actualSize);
            timescale = parseTimescaleFromMoov(moovContent);
            scanLog.info(`Parsed timescale: ${timescale}`);
          }
          // initSize = everything before first moof
          if (segments.length === 0 && moofOffset < 0) {
            initSize = pos + actualSize;
          }
          break;
        }

        case "moof": {
          // If we had a previous moof waiting for its mdat, something is off — skip it
          if (moofOffset >= 0) {
            scanLog.warn(`Found moof without preceding mdat at offset ${pos}`);
          }
          moofOffset = pos;

          // Parse tfdt from this moof
          if (pos + actualSize <= buf.length) {
            const moofBuf = buf.subarray(pos, pos + actualSize);
            currentDecodeTicks = parseTfdt(moofBuf);
          }
          break;
        }

        case "mdat": {
          if (moofOffset >= 0) {
            const segmentByteOffset = moofOffset;
            const segmentByteLength = (pos + actualSize) - moofOffset;

            segments.push({
              byteOffset: segmentByteOffset,
              byteLength: segmentByteLength,
              durationTicks: 0, // Filled in below
              decodeTicks: currentDecodeTicks,
            });

            moofOffset = -1;
            currentDecodeTicks = -1;
          }
          break;
        }
      }

      pos += actualSize;
    }

    // Fill in durationTicks from gaps between consecutive segments
    this.computeDurations(segments);

    scanLog.info(
      `Full scan: ${segments.length} segments, initSize=${initSize}, timescale=${timescale}`
    );

    return { segments, lastFileSize: fileSize, initSize, timescale };
  }

  /**
   * Incremental scan from a known offset
   *
   * Starts scanning from where the previous scan left off.
   * Appends new segments to the existing array.
   *
   * @param buf - Full file buffer
   * @param fileSize - Current file size
   * @param scanFrom - Byte offset to start scanning
   * @param existingSegments - Previously scanned segments
   * @param initSize - Known init segment size
   * @param timescale - Known timescale
   * @returns Updated scan cache
   */
  private incrementalScan(
    buf: Buffer,
    fileSize: number,
    scanFrom: number,
    existingSegments: IScannedSegment[],
    initSize: number,
    timescale: number
  ): IScanCache {
    // Start scanning from the last known segment boundary
    // Back up to the last segment end in case the previous scan ended mid-segment
    let pos = scanFrom;

    // If we have segments, start from after the last complete segment
    if (existingSegments.length > 0) {
      const last = existingSegments[existingSegments.length - 1];
      pos = last.byteOffset + last.byteLength;
    }

    let moofOffset = -1;
    let currentDecodeTicks = -1;
    const newSegments = [...existingSegments];

    while (pos + 8 <= fileSize && pos + 8 <= buf.length) {
      const boxSize = readU32(buf, pos);
      const boxType = readBoxType(buf, pos + 4);

      let actualSize = boxSize;
      if (boxSize === 1 && pos + 16 <= buf.length) {
        actualSize = readU64(buf, pos + 8);
      }

      if (actualSize < 8) break;
      if (pos + actualSize > fileSize) break;

      if (boxType === "moof") {
        moofOffset = pos;

        if (pos + actualSize <= buf.length) {
          const moofBuf = buf.subarray(pos, pos + actualSize);
          currentDecodeTicks = parseTfdt(moofBuf);
        }
      } else if (boxType === "mdat" && moofOffset >= 0) {
        newSegments.push({
          byteOffset: moofOffset,
          byteLength: (pos + actualSize) - moofOffset,
          durationTicks: 0,
          decodeTicks: currentDecodeTicks,
        });

        moofOffset = -1;
        currentDecodeTicks = -1;
      }

      pos += actualSize;
    }

    // Recompute durations for all segments (cheap — just gaps between tfdt values)
    this.computeDurations(newSegments);

    if (newSegments.length > existingSegments.length) {
      scanLog.info(
        `Incremental scan: ${newSegments.length - existingSegments.length} new segments (total: ${newSegments.length})`
      );
    }

    return { segments: newSegments, lastFileSize: fileSize, initSize, timescale };
  }

  /**
   * Compute durationTicks for each segment from tfdt gaps
   *
   * Duration of segment N = tfdt(N+1) - tfdt(N).
   * Last segment gets the same duration as the previous one (or a default).
   *
   * @param segments - Segments array to mutate
   */
  private computeDurations(segments: IScannedSegment[]): void {
    for (let i = 0; i < segments.length; i++) {
      if (i < segments.length - 1) {
        const gap = segments[i + 1].decodeTicks - segments[i].decodeTicks;
        segments[i].durationTicks = gap > 0 ? gap : 0;
      } else if (i > 0) {
        // Last segment: use previous segment's duration as estimate
        segments[i].durationTicks = segments[i - 1].durationTicks;
      } else {
        // Single segment: assume ~4s at 90000 timescale
        segments[i].durationTicks = 360000;
      }
    }
  }

  /**
   * Clear cached scan data for a session
   *
   * @param sessionId - Session to clear
   */
  clearCache(sessionId: string): void {
    this.cache.delete(sessionId);
  }
}
