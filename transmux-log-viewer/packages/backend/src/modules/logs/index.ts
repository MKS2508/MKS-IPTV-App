import { Elysia, sse } from "elysia";
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
 * Uses Elysia's native sse() helper with async generator for proper
 * Server-Sent Events streaming with automatic cleanup on disconnect.
 *
 * @example
 * ```typescript
 * // Stream logs via EventSource
 * const es = new EventSource('/logs/stream');
 * es.onmessage = (e) => {
 *   const log = JSON.parse(e.data);
 *   console.log(log.message);
 * };
 *
 * // Or via Eden Treaty
 * const { data } = await api.logs.stream.get();
 * for await (const chunk of data) console.log(chunk);
 * ```
 */
export const logsModule = new Elysia({ prefix: "/logs" })
  .decorate("logService", new LogService())
  .model(logModels)
  .get(
    "/stream",
    async function* ({ logService, request }) {
      const signal = request.signal;

      // Initial connection event
      yield sse({
        data: {
          type: "connected",
          message: "Connected to log stream",
          timestamp: new Date().toISOString(),
        },
      });

      // Stream parsed log entries
      for await (const entry of logService.streamEntries(signal)) {
        if (signal.aborted) return;
        yield sse({ data: entry });
      }
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
