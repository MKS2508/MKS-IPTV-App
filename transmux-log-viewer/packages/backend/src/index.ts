import { cors } from "@elysiajs/cors";
import logger from "@mks2508/better-logger";
import { Elysia } from "elysia";
import { cliModule } from "./modules/cli";
import { healthModule } from "./modules/health";
import { hlsModule } from "./modules/hls";
import { logsModule } from "./modules/logs";
import { sourcesModule } from "./modules/sources";

/** Port — uses PORT env var when available (portless sets this automatically) */
const port = Number(process.env.PORT) || 3000;

/**
 * Main Elysia server for TransmuxCore log viewer
 *
 * Provides real-time log streaming via SSE (Server-Sent Events) for
 * the React frontend to consume.
 *
 * @see /modules/logs - SSE streaming, history, and clear endpoints
 * @see /modules/health - Health check endpoint
 * @see /modules/cli - TransmuxCore CLI execution endpoints
 * @see /modules/hls - HLS serving (fMP4 + m3u8)
 * @see /modules/sources - Test data sources (IPTV + local files)
 */
const app = new Elysia()
  .use(
    cors({
      origin: (request): boolean => {
        const origin = request.headers.get("origin");
        if (!origin) return true;
        // Allow localhost (any port) and portless .localhost URLs
        return (
          /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin) ||
          /^https?:\/\/[\w.-]+\.localhost(:\d+)?$/.test(origin)
        );
      },
      credentials: true,
    })
  )
  .use(logsModule)
  .use(healthModule)
  .use(cliModule)
  .use(hlsModule)
  .use(sourcesModule)
  .onStart(({ decorator, server }) => {
    // Wire CLIService into HLSService so it can access session metadata
    const cli = (decorator as any).cliService;
    const hls = (decorator as any).hlsService;
    if (cli && hls && typeof hls.setCLIService === "function") {
      hls.setCLIService(cli);
    }

    const serverLog = logger.component("Server");
    serverLog.info("TransmuxCore Log Viewer API started");
    serverLog.info(`Watching log file: /tmp/mks-iptv-transmux.log`);
    serverLog.info(`API: http://localhost:${server?.port ?? port}`);
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
  .listen(port);

export type App = typeof app;
