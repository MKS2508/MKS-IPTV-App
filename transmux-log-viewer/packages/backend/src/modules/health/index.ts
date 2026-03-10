import { Elysia } from "elysia";

/**
 * Health check module
 *
 * Provides a simple health check endpoint for monitoring.
 *
 * @example
 * ```bash
 * curl http://localhost:3000/health
 * # { "status": "ok", "timestamp": "2026-03-02T21:00:00.000Z" }
 * ```
 */
export const healthModule = new Elysia({ prefix: "/health" }).get(
  "/",
  () => ({
    status: "ok",
    timestamp: new Date().toISOString(),
  }),
  {
    detail: {
      summary: "Health check",
      description: "Check if the server is running",
      tags: ["health"],
    },
  }
);
