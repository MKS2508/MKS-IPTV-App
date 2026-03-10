import { t } from "elysia";

/**
 * Session status for CLI processes
 */
export type SessionStatus = "running" | "completed" | "failed" | "killed";

/**
 * Session execution mode — determines which stdin commands are accepted
 *
 * - `interactive`: No seek/duration args, CLI accepts SEEK/STOP via stdin
 * - `seek`: One-shot `--seek` mode, no stdin seek support
 * - `test-seek`: Self-terminating `--test-seek` mode
 */
export type SessionMode = "interactive" | "seek" | "test-seek";

/**
 * Active CLI session tracking
 *
 * @property sessionId - Unique session identifier from CLI output
 * @property pid - Process ID of the spawned CLI
 * @property input - Input file path or URL
 * @property outputPath - Path to output stream.mp4
 * @property playlistPath - Path to output stream.m3u8
 * @property initSegmentSize - Size of init segment in bytes
 * @property duration - Duration argument passed to CLI
 * @property mode - Execution mode (interactive, seek, test-seek)
 * @property status - Current session status
 * @property startedAt - ISO timestamp when session started
 */
export interface IActiveSession {
  sessionId: string;
  pid: number;
  input: string;
  outputPath: string;
  playlistPath: string;
  initSegmentSize: number;
  duration: number;
  mode: SessionMode;
  status: SessionStatus;
  startedAt: string;
}

/**
 * TypeBox models for CLI module validation
 */
export const cliModels = {
  CLIRunRequest: t.Object({
    input: t.String({ description: "Input file path or URL" }),
    seek: t.Optional(t.Number({ description: "Seek time in seconds", default: 0 })),
    testSeek: t.Optional(t.Number({ description: "Run automated seek test at TIME seconds with log validation" })),
    duration: t.Optional(t.Number({ description: "Duration in seconds", default: 10 })),
    verbose: t.Optional(t.Boolean({ description: "Enable verbose logging", default: true })),
  }),

  SessionInfo: t.Object({
    sessionId: t.String(),
    pid: t.Number(),
    input: t.String(),
    outputPath: t.String(),
    playlistPath: t.String(),
    initSegmentSize: t.Number(),
    duration: t.Number(),
    mode: t.Union([
      t.Literal("interactive"),
      t.Literal("seek"),
      t.Literal("test-seek"),
    ]),
    status: t.Union([
      t.Literal("running"),
      t.Literal("completed"),
      t.Literal("failed"),
      t.Literal("killed"),
    ]),
    startedAt: t.String(),
  }),

  SessionList: t.Object({
    sessions: t.Array(t.Ref("SessionInfo")),
    count: t.Number(),
  }),

  CLIRunResponse: t.Object({
    sessionId: t.String(),
    pid: t.Number(),
    outputPath: t.String(),
    playlistPath: t.String(),
    mode: t.Union([
      t.Literal("interactive"),
      t.Literal("seek"),
      t.Literal("test-seek"),
    ]),
    status: t.String(),
    message: t.String(),
  }),

  CLISeekRequest: t.Object({
    time: t.Number({ description: "Target seek time in seconds", minimum: 0 }),
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
