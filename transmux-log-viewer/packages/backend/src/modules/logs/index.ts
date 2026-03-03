import { Elysia } from "elysia";
import { logModels } from "./model";
import { LogService } from "./service";

/**
 * Logs module - Handles real-time log streaming and history
 *
 * Endpoints:
 * - GET /logs/stream - SSE endpoint for real-time log streaming
 * - GET /logs/history - Retrieve full log history
 * - POST /logs/clear - Clear the log file
 *
 * @example
 * ```typescript
 * // Stream logs via SSE
 * const eventSource = new EventSource('/logs/stream');
 * eventSource.onmessage = (e) => {
 *   const log = JSON.parse(e.data);
 *   console.log(log.message);
 * };
 *
 * // Get history
 * const response = await fetch('/logs/history');
 * const { logs } = await response.json();
 * ```
 */
export const logsModule = new Elysia({ prefix: "/logs" })
  .decorate("logService", new LogService())
  .model(logModels)
  .get(
    "/stream",
    async ({ logService, set }) => {
      set.headers["Content-Type"] = "text/event-stream";
      set.headers["Cache-Control"] = "no-cache";
      set.headers.Connection = "keep-alive";

      return logService.streamLogs();
    },
    {
      detail: {
        summary: "Stream logs via SSE",
        description: "Server-Sent Events endpoint that streams new log lines in real-time",
        tags: ["logs"],
      },
    }
  )
  .get(
    "/history",
    async ({ logService }) => {
      const result = await logService.getHistory();
      return result;
    },
    {
      response: {
        200: "LogHistory",
        404: "ErrorResponse",
      },
      detail: {
        summary: "Get log history",
        description: "Retrieve all logs from the file",
        tags: ["logs"],
      },
    }
  )
  .post(
    "/clear",
    async ({ logService }) => {
      const result = await logService.clearLogs();
      return result;
    },
    {
      response: {
        200: "SuccessResponse",
        500: "ErrorResponse",
      },
      detail: {
        summary: "Clear logs",
        description: "Clear the log file content",
        tags: ["logs"],
      },
    }
  );
