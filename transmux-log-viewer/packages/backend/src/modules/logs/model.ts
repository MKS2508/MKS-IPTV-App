import { t } from "elysia";

/**
 * Log level enumeration
 */
export type LogLevel = "ERROR" | "WARN" | "INFO" | "DEBUG";

/**
 * Parsed log entry structure
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
 * Log history response structure
 *
 * @property logs - Array of parsed log entries
 * @property count - Total number of logs
 */
export interface ILogHistory {
  logs: ILogEntry[];
  count: number;
}

/**
 * Generic success response
 *
 * @property success - Success flag
 * @property message - Success message
 */
export interface ISuccessResponse {
  success: boolean;
  message: string;
}

/**
 * Generic error response
 *
 * @property error - Error title
 * @property message - Error details
 */
export interface IErrorResponse {
  error: string;
  message: string;
}

/**
 * TypeBox models for validation
 */
export const logModels = {
  LogEntry: t.Object({
    timestamp: t.String(),
    tag: t.String(),
    level: t.Union([t.Literal("ERROR"), t.Literal("WARN"), t.Literal("INFO"), t.Literal("DEBUG")]),
    message: t.String(),
    raw: t.String(),
  }),

  LogHistory: t.Object({
    logs: t.Array(t.Ref("LogEntry")),
    count: t.Number(),
  }),

  SuccessResponse: t.Object({
    success: t.Boolean(),
    message: t.String(),
  }),

  ErrorResponse: t.Object({
    error: t.String(),
    message: t.String(),
  }),
};
