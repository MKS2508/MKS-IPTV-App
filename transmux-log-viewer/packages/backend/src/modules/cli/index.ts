import { Elysia, t } from "elysia";
import { cliModels } from "./model";
import { CLIService } from "./service";

/**
 * CLI module - Handles TransmuxCore CLI execution and session management
 *
 * Endpoints:
 * - POST /cli/run - Start a new transmux session
 * - GET /cli/sessions - List all sessions (active and completed)
 * - POST /cli/stop/:sessionId - Stop a running session
 *
 * @example
 * ```bash
 * # Run CLI
 * curl -X POST http://localhost:3000/cli/run \
 *   -H "Content-Type: application/json" \
 *   -d '{"input":"/path/to/video.mkv","duration":10,"verbose":true}'
 *
 * # List sessions
 * curl http://localhost:3000/cli/sessions
 *
 * # Stop session
 * curl -X POST http://localhost:3000/cli/stop/session-id
 * ```
 */
export const cliModule = new Elysia({ prefix: "/cli" })
  .decorate("cliService", new CLIService())
  .model(cliModels)
  .post(
    "/run",
    async ({ cliService, body }) => {
      const session = await cliService.runCLI(body);
      return {
        sessionId: session.sessionId,
        pid: session.pid,
        outputPath: session.outputPath,
        playlistPath: session.playlistPath,
        status: session.status,
        message: `CLI started with PID ${session.pid}`,
      };
    },
    {
      body: "CLIRunRequest",
      response: {
        200: "CLIRunResponse",
      },
      detail: {
        summary: "Run TransmuxCore CLI",
        description: "Start a new transmux session with the given input and options",
        tags: ["cli"],
      },
    }
  )
  .get(
    "/sessions",
    ({ cliService }) => {
      return cliService.getSessions();
    },
    {
      response: {
        200: "SessionList",
      },
      detail: {
        summary: "List CLI sessions",
        description: "Get all active and completed transmux sessions",
        tags: ["cli"],
      },
    }
  )
  .post(
    "/stop/:sessionId",
    async ({ cliService, params }) => {
      const result = await cliService.stopSession(params.sessionId);
      return result;
    },
    {
      params: t.Object({
        sessionId: t.String(),
      }),
      response: {
        200: "SuccessResponse",
      },
      detail: {
        summary: "Stop CLI session",
        description: "Kill a running transmux session",
        tags: ["cli"],
      },
    }
  );
