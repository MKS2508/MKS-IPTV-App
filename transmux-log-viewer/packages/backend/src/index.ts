import { cors } from "@elysiajs/cors";
import logger from "@mks2508/better-logger";
import { Elysia } from "elysia";
import { cliModule } from "./modules/cli";
import { healthModule } from "./modules/health";
import { logsModule } from "./modules/logs";

/**
 * Main Elysia server for TransmuxCore log viewer
 *
 * Provides real-time log streaming via SSE (Server-Sent Events) for
 * the React frontend to consume.
 *
 * @see /modules/logs - SSE streaming, history, and clear endpoints
 * @see /modules/health - Health check endpoint
 * @see /modules/cli - TransmuxCore CLI execution endpoints
 */
const app = new Elysia()
  .use(
    cors({
      origin: ["http://localhost:5173", "http://127.0.0.1:5173"],
      credentials: true,
    })
  )
  .use(logsModule)
  .use(healthModule)
  .use(cliModule)
  .onStart(() => {
    const serverLog = logger.component("Server");
    serverLog.info("🚀 TransmuxCore Log Viewer API started");
    serverLog.info(`📝 Watching log file: /tmp/mks-iptv-transmux.log`);
    serverLog.info(`🌐 API: http://localhost:3000`);
  })
  .onError(({ code, error, set }) => {
    const errorLog = logger.component("Error");
    const errorMessage = error instanceof Error ? error.message : String(error);

    if (code === "NOT_FOUND") {
      set.status = 404;
      errorLog.warn(`404 Not Found: ${errorMessage}`);
      return { error: "Not Found", message: errorMessage };
    }

    if (code === "VALIDATION") {
      set.status = 400;
      errorLog.warn(`Validation error: ${errorMessage}`);
      return { error: "Validation Error", message: errorMessage };
    }

    set.status = 500;
    errorLog.error(`Internal error: ${errorMessage}`, { error });
    return { error: "Internal Server Error", message: errorMessage };
  })
  .listen(3000);

export type App = typeof app;
