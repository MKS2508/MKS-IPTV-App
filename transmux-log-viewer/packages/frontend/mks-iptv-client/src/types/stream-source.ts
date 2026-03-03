/**
 * Stream source types for IPTV test data
 *
 * Represents the available test sources for the TransmuxCore CLI.
 * Sources can be local files or remote IPTV URLs.
 */

/**
 * IPTV stream source from data.json
 *
 * @property category - Content category (e.g., "ESTRENOS (BDRip 1080 dual AC3)")
 * @property containerExtension - File extension (mkv, mp4)
 * @property id - Unique identifier (e.g., "movie_311368")
 * @property name - Display name
 * @property streamId - Numeric stream ID
 * @property type - Content type (movie, series)
 * @property url - HTTP stream URL
 */
export interface IStreamSource {
  category: string;
  containerExtension: "mkv" | "mp4" | "avi" | "m4v";
  id: string;
  name: string;
  streamId: number;
  type: "movie" | "series";
  url: string;
}

/**
 * Local file source from /Volumes/KODAK1TB/
 *
 * @property path - Absolute file path
 * @property name - Display name (filename)
 * @property size - File size in bytes
 * @property extension - File extension
 */
export interface ILocalFileSource {
  path: string;
  name: string;
  size: number;
  extension: string;
}

/**
 * Union type for all test sources
 */
export type TestSource = IStreamSource | ILocalFileSource;

/**
 * Type guard to check if source is an IPTV stream
 */
export function isStreamSource(source: TestSource): source is IStreamSource {
  return "url" in source;
}

/**
 * Type guard to check if source is a local file
 */
export function isLocalFileSource(source: TestSource): source is ILocalFileSource {
  return "path" in source;
}

/**
 * CLI execution options
 *
 * @property input - Input file path or URL
 * @property seek - Seek time in seconds (optional)
 * @property duration - Duration to test after seek (default: 10)
 * @property verbose - Enable verbose logging
 */
export interface ICLIOptions {
  input: string;
  seek?: number;
  duration?: number;
  verbose?: boolean;
}

/**
 * CLI execution result
 *
 * @property sessionId - Transmux session ID
 * @property outputPath - Path to output stream.mp4
 * @property playlistPath - Path to output stream.m3u8
 * @property initSegmentSize - Size of init segment in bytes
 * @property duration - Total duration in seconds
 */
export interface ICLIResult {
  sessionId: string;
  outputPath: string;
  playlistPath: string;
  initSegmentSize: number;
  duration: number;
}
