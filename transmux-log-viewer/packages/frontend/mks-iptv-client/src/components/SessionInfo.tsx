import { Badge, Button } from "@mks2508/mks-ui/react";
import { Copy, Square, Terminal } from "lucide-react";
import { useCallback } from "react";
import type { ISessionInfo } from "@/types/log";

/**
 * Props for the SessionInfo component
 *
 * @property session - Active session info (null = hidden)
 * @property onStop - Callback to stop the session
 */
interface ISessionInfoProps {
  session: ISessionInfo | null;
  onStop: (sessionId: string) => void;
}

/**
 * Compact session info bar showing active session metadata
 *
 * Displays session ID, input file, output paths, status badge,
 * and stop button. Hidden when no session is active.
 *
 * @example
 * ```tsx
 * <SessionInfo session={activeSession} onStop={handleStop} />
 * ```
 */
export function SessionInfo({ session, onStop }: ISessionInfoProps) {
  if (!session) return null;

  const copyToClipboard = useCallback((text: string) => {
    navigator.clipboard.writeText(text).catch(() => {});
  }, []);

  const statusClass =
    session.status === "running"
      ? "border-primary/40 text-primary bg-primary/10"
      : session.status === "completed"
        ? "border-chart-5/40 text-chart-5 bg-chart-5/10"
        : session.status === "failed"
          ? "border-destructive/40 text-destructive bg-destructive/10"
          : "border-muted-foreground/30 text-muted-foreground bg-muted/30";

  return (
    <div className="flex items-center gap-2 px-3 py-1.5 border border-border/15 rounded-lg bg-background/30">
      <Terminal className="size-3 text-primary/60 shrink-0" />

      {/* Session ID */}
      <button
        type="button"
        onClick={() => copyToClipboard(session.sessionId)}
        className="flex items-center gap-1 group cursor-pointer"
        title="Copy session ID"
      >
        <span className="font-mono text-[10px] text-foreground/60 truncate max-w-[140px]">
          {session.sessionId}
        </span>
        <Copy className="size-2.5 text-muted-foreground/30 group-hover:text-primary/60 transition-colors" />
      </button>

      <div className="h-3 w-px bg-border/15" />

      {/* Input truncated */}
      <span
        className="font-mono text-[9px] text-muted-foreground/40 truncate max-w-[200px]"
        title={session.input}
      >
        {session.input.split("/").pop()}
      </span>

      <div className="flex-1" />

      {/* Status badge */}
      <Badge
        variant="outline"
        className={`text-[8px] px-1.5 py-0 h-4 uppercase tracking-wider font-mono ${statusClass}`}
      >
        {session.status === "running" && (
          <span className="inline-block size-1 rounded-full bg-current mr-1 animate-[pulse_2s_ease-in-out_infinite]" />
        )}
        {session.status}
      </Badge>

      {/* Stop button */}
      {session.status === "running" && (
        <Button
          variant="ghost"
          size="icon"
          className="size-5"
          onClick={() => onStop(session.sessionId)}
          title="Stop session"
        >
          <Square className="size-2.5 text-destructive/60" />
        </Button>
      )}
    </div>
  );
}
