import { stat, writeFile } from "node:fs/promises";
import logger from "@mks2508/better-logger";
import type { IErrorResponse, ILogEntry, ILogHistory, ISuccessResponse, LogLevel } from "./model";

const serviceLog = logger.component("LogService");

/**
 * Service for managing TransmuxCore log file operations
 *
 * Handles:
 * - Real-time log streaming via SSE (yields parsed entries)
 * - Log file parsing and filtering
 * - Log history retrieval
 * - Log file clearing
 *
 * @example
 * ```typescript
 * const service = new LogService();
 * for await (const entry of service.streamEntries(signal)) {
 *   console.log(entry.message);
 * }
 * ```
 */
export class LogService {
  private readonly LOG_FILE = "/tmp/mks-iptv-transmux.log";

  /**
   * Stream parsed log entries from the log file
   *
   * Polls the log file for changes and yields new lines as parsed
   * ILogEntry objects. The route handler wraps these with Elysia's
   * sse() for proper SSE formatting.
   *
   * @param signal - AbortSignal for client disconnect detection
   * @returns AsyncGenerator yielding parsed log entries
   */
  async *streamEntries(signal?: AbortSignal): AsyncGenerator<ILogEntry, void, unknown> {
    let lastSize = 0;

    // Get initial file size
    try {
      const stats = await stat(this.LOG_FILE);
      lastSize = stats.size;
      serviceLog.info(`SSE connected — log file size: ${lastSize} bytes`);
    } catch (_error) {
      serviceLog.warn("Log file not found, waiting for creation...");
    }

    // Poll for file changes until client disconnects
    while (!signal?.aborted) {
      try {
        const stats = await stat(this.LOG_FILE);
        const currentSize = stats.size;

        // File was truncated (e.g. log clear) — reset
        if (currentSize < lastSize) {
          lastSize = 0;
        }

        // Only read new content
        if (currentSize > lastSize) {
          const file = Bun.file(this.LOG_FILE);
          const content = await file.text();
          const newContent = content.slice(lastSize);
          lastSize = currentSize;

          const lines = newContent.split("\n").filter((line) => line.trim());

          for (const line of lines) {
            if (signal?.aborted) return;
            yield this.parseLogLine(line);
          }
        }
      } catch (_error) {
        // File doesn't exist yet, just continue polling
      }

      // Interruptible 500ms sleep
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, 500);
        if (signal) {
          const onAbort = () => {
            clearTimeout(timer);
            resolve();
          };
          signal.addEventListener("abort", onAbort, { once: true });
        }
      });
    }

    serviceLog.info("SSE stream closed (client disconnected)");
  }

  /**
   * Get full log file history
   *
   * Reads the entire log file and parses all lines into structured entries.
   *
   * @returns Promise resolving to log history or error response
   */
  async getHistory(): Promise<ILogHistory | IErrorResponse> {
    try {
      const file = Bun.file(this.LOG_FILE);
      const content = await file.text();
      const lines = content.split("\n").filter((line) => line.trim());

      const logs = lines.map((line) => this.parseLogLine(line));

      serviceLog.info(`Retrieved ${logs.length} log entries`);

      return {
        logs,
        count: logs.length,
      };
    } catch (error) {
      serviceLog.error("Failed to read log history", { error });

      return {
        error: "Failed to read log file",
        message: error instanceof Error ? error.message : String(error),
      };
    }
  }

  /**
   * Clear the log file
   *
   * Truncates the log file to zero bytes.
   *
   * @returns Promise resolving to success or error response
   */
  async clearLogs(): Promise<ISuccessResponse | IErrorResponse> {
    try {
      await writeFile(this.LOG_FILE, "");
      serviceLog.info("Log file cleared successfully");

      return {
        success: true,
        message: "Log file cleared",
      };
    } catch (error) {
      serviceLog.error("Failed to clear log file", { error });

      return {
        error: "Failed to clear log file",
        message: error instanceof Error ? error.message : String(error),
      };
    }
  }

  /**
   * Parse a raw log line into a structured LogEntry
   *
   * Supports two formats:
   * 1. TransmuxCore log: [HH:mm:ss.SSS] [LEVEL] [TAG] message
   * 2. Session header:   ========== TRANSMUX SESSION <id> @ HH:mm:ss.SSS ==========
   *
   * @param line - Raw log line to parse
   * @returns Parsed log entry with metadata
   */
  private parseLogLine(line: string): ILogEntry {
    // Format: [HH:mm:ss.SSS] [LEVEL] [TAG] message
    const logMatch = line.match(
      /\[(\d{2}:\d{2}:\d{2}\.\d{3})\]\s+\[(DBG|INF|WRN|ERR)\]\s+\[(\w+)\]\s+(.*)/
    );

    if (logMatch) {
      const [, timestamp, levelCode, tag, message] = logMatch;
      const levelMap: Record<string, LogLevel> = {
        DBG: "DEBUG",
        INF: "INFO",
        WRN: "WARN",
        ERR: "ERROR",
      };

      return {
        timestamp,
        tag: tag.toUpperCase(),
        level: levelMap[levelCode] ?? "INFO",
        message,
        raw: line,
      };
    }

    // Session header line
    const sessionMatch = line.match(/=+\s+TRANSMUX SESSION\s+(\S+)\s+@\s+(\S+)\s+=+/);
    if (sessionMatch) {
      return {
        timestamp: sessionMatch[2],
        tag: "SESSION",
        level: "INFO",
        message: `Session started: ${sessionMatch[1]}`,
        raw: line,
      };
    }

    // Fallback: unstructured line
    return {
      timestamp: new Date().toISOString(),
      tag: "UNKNOWN",
      level: "INFO",
      message: line.trim(),
      raw: line,
    };
  }
}
