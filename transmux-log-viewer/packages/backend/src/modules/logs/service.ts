import { stat, writeFile } from "node:fs/promises";
import logger from "@mks2508/better-logger";
import type { IErrorResponse, ILogEntry, ILogHistory, ISuccessResponse, LogLevel } from "./model";

const serviceLog = logger.component("LogService");

/**
 * Service for managing TransmuxCore log file operations
 *
 * Handles:
 * - Real-time log streaming via SSE
 * - Log file parsing and filtering
 * - Log history retrieval
 * - Log file clearing
 *
 * @example
 * ```typescript
 * const service = new LogService();
 *
 * // Stream logs
 * const stream = service.streamLogs();
 *
 * // Get history
 * const history = await service.getHistory();
 *
 * // Clear logs
 * await service.clearLogs();
 * ```
 */
export class LogService {
  private readonly LOG_FILE = "/tmp/mks-iptv-transmux.log";

  /**
   * Stream log file changes via SSE
   *
   * Polls the log file for changes and yields new lines as they appear.
   * Each line is parsed into a structured LogEntry object.
   *
   * @returns AsyncGenerator yielding SSE-formatted log entries
   */
  async *streamLogs(): AsyncGenerator<string, void, unknown> {
    let lastSize = 0;
    const running = true;

    // Get initial file size
    try {
      const stats = await stat(this.LOG_FILE);
      lastSize = stats.size;
      serviceLog.info(`Initial log file size: ${lastSize} bytes`);
    } catch (_error) {
      serviceLog.warn("Log file not found, waiting for creation...");
      yield this.formatSSE({
        type: "error",
        message: "Log file not found. Start transmux-cli to create it.",
      });
    }

    // Send initial connection message
    yield this.formatSSE({
      type: "connected",
      message: "Connected to log stream",
      timestamp: new Date().toISOString(),
    });

    // Poll for file changes
    while (running) {
      try {
        const stats = await stat(this.LOG_FILE);
        const currentSize = stats.size;

        // Only read new content
        if (currentSize > lastSize) {
          const file = Bun.file(this.LOG_FILE);
          const content = await file.text();
          const newContent = content.slice(lastSize);
          lastSize = currentSize;

          // Split by lines and parse each
          const lines = newContent.split("\n").filter((line) => line.trim());

          for (const line of lines) {
            const parsed = this.parseLogLine(line);
            yield this.formatSSE(parsed);
          }
        }
      } catch (_error) {
        // File doesn't exist yet, just continue polling
      }

      // Poll every 500ms
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
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
   * Expected format:
   * [TIMESTAMP] [TAG] Message
   *
   * Examples:
   * - [2026-03-02 21:00:00] [SERVICE] Transmux started: session abc123
   * - [2026-03-02 21:00:01] [AC3    ] AC3 init phase reset complete
   * - [2026-03-02 21:00:02] [ERROR  ] Non-monotonic DTS detected
   *
   * @param line - Raw log line to parse
   * @returns Parsed log entry with metadata
   */
  private parseLogLine(line: string): ILogEntry {
    // Extract timestamp
    const timestampMatch = line.match(/\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/);
    const timestamp = timestampMatch ? timestampMatch[1] : new Date().toISOString();

    // Extract tag (second bracketed value)
    const tagMatch = line.match(/\[([A-Z]+\s*)\]/g);
    let tag = "UNKNOWN";
    let message = line;

    if (tagMatch && tagMatch.length > 1) {
      tag = tagMatch[1].replace(/[[\]]/g, "").trim();
      message = line.split(tagMatch[1])[1]?.trim() || line;
    }

    // Determine log level based on keywords
    let level: LogLevel = "INFO";

    if (line.includes("ERROR") || line.includes("error") || line.includes("failed")) {
      level = "ERROR";
    } else if (line.includes("WARN") || line.includes("warning")) {
      level = "WARN";
    } else if (line.includes("DEBUG")) {
      level = "DEBUG";
    }

    return {
      timestamp,
      tag,
      level,
      message,
      raw: line,
    };
  }

  /**
   * Format data as SSE message
   *
   * @param data - Data to send via SSE
   * @returns SSE-formatted string
   */
  private formatSSE(data: unknown): string {
    return `data: ${JSON.stringify(data)}\n\n`;
  }
}
