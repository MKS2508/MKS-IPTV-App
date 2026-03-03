/**
 * Log level for parsed log entries
 */
export type LogLevel = "ERROR" | "WARN" | "INFO" | "DEBUG";

/**
 * Known log tags from TransmuxCore CLI
 */
export type LogTag =
  | "SERVICE"
  | "REMUX"
  | "SEGMENTER"
  | "AC3"
  | "SEEK"
  | "OFFSET"
  | "DTS"
  | "ERROR"
  | "UNKNOWN";

/**
 * Parsed log entry from SSE stream
 *
 * @property timestamp - ISO timestamp string
 * @property tag - Log tag (SERVICE, REMUX, AC3, etc.)
 * @property level - Log severity level
 * @property message - Log message content
 * @property raw - Original raw log line
 */
export interface ILogEntry {
  timestamp: string;
  tag: string;
  level: LogLevel;
  message: string;
  raw: string;
}

/**
 * Aggregated log statistics
 *
 * @property total - Total number of log lines
 * @property errors - Number of ERROR level entries
 * @property warns - Number of WARN level entries
 * @property seeks - Number of SEEK tag entries
 * @property packets - Approximate packet count from log messages
 */
export interface ILogStats {
  total: number;
  errors: number;
  warns: number;
  seeks: number;
  packets: number;
}

/**
 * Session status
 */
export type SessionStatus = "running" | "completed" | "failed" | "killed";

/**
 * Active session info from backend
 *
 * @property sessionId - Unique session identifier
 * @property pid - Process ID of the CLI
 * @property input - Input file path or URL
 * @property outputPath - Path to output stream.mp4
 * @property playlistPath - Path to output stream.m3u8
 * @property initSegmentSize - Size of init segment in bytes
 * @property duration - Duration in seconds
 * @property status - Current session status
 * @property startedAt - ISO timestamp when session started
 */
export interface ISessionInfo {
  sessionId: string;
  pid: number;
  input: string;
  outputPath: string;
  playlistPath: string;
  initSegmentSize: number;
  duration: number;
  status: SessionStatus;
  startedAt: string;
}
