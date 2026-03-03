import { Badge, Button } from "@mks2508/mks-ui/react";
import { ArrowDownToLine, Eraser, Pause, Play } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ILogEntry, LogTag } from "@/types/log";

/** All known log tags for filtering */
const ALL_TAGS: LogTag[] = [
  "SERVICE",
  "REMUX",
  "SEGMENTER",
  "AC3",
  "SEEK",
  "OFFSET",
  "DTS",
  "CHELPER",
  "CLAYOUT",
  "FFMPEG",
  "SESSION",
  "ERROR",
  "UNKNOWN",
];

/**
 * Props for the LogViewer component
 *
 * @property logs - Array of parsed log entries to display
 * @property onClear - Callback to clear the log buffer
 */
interface ILogViewerProps {
  logs: ILogEntry[];
  onClear: () => void;
}

/**
 * Real-time log viewer with tag filtering, auto-scroll, and color-coded levels
 *
 * Displays streaming log entries in a terminal-style monospace view.
 * Each entry is color-coded by level (ERROR=destructive, WARN=chart-1,
 * INFO=primary, DEBUG=muted). Tags are filterable via clickable badges.
 *
 * @example
 * ```tsx
 * <LogViewer logs={logEntries} onClear={handleClear} />
 * ```
 */
export function LogViewer({ logs, onClear }: ILogViewerProps) {
  const [activeTags, setActiveTags] = useState<Set<string>>(new Set());
  const [autoScroll, setAutoScroll] = useState(true);
  const scrollRef = useRef<HTMLDivElement>(null);

  const filteredLogs = useMemo(() => {
    if (activeTags.size === 0) return logs;
    return logs.filter((log) => activeTags.has(log.tag));
  }, [logs, activeTags]);

  const toggleTag = useCallback((tag: string) => {
    setActiveTags((prev) => {
      const next = new Set(prev);
      if (next.has(tag)) {
        next.delete(tag);
      } else {
        next.add(tag);
      }
      return next;
    });
  }, []);

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [filteredLogs, autoScroll]);

  /**
   * Get CSS class for log level coloring
   */
  const getLevelClass = (level: string): string => {
    switch (level) {
      case "ERROR":
        return "text-destructive";
      case "WARN":
        return "text-chart-1";
      case "DEBUG":
        return "text-muted-foreground/50";
      default:
        return "text-foreground/80";
    }
  };

  /**
   * Get CSS class for tag badge coloring
   */
  const getTagClass = (tag: string): string => {
    switch (tag) {
      case "REMUX":
        return "border-primary/40 text-primary";
      case "SEEK":
        return "border-chart-2/40 text-chart-2";
      case "AC3":
        return "border-chart-3/40 text-chart-3";
      case "ERROR":
        return "border-destructive/40 text-destructive";
      case "DTS":
        return "border-chart-4/40 text-chart-4";
      case "SERVICE":
        return "border-chart-5/40 text-chart-5";
      case "CHELPER":
        return "border-orange-500/40 text-orange-400";
      case "CLAYOUT":
        return "border-amber-500/40 text-amber-400";
      case "FFMPEG":
        return "border-red-400/40 text-red-300";
      case "SESSION":
        return "border-cyan-500/40 text-cyan-400";
      default:
        return "border-border/40 text-muted-foreground";
    }
  };

  /**
   * Format timestamp to HH:MM:SS
   */
  const formatTime = (timestamp: string): string => {
    try {
      if (timestamp.includes(" ")) {
        return timestamp.split(" ")[1] ?? timestamp;
      }
      const d = new Date(timestamp);
      return d.toLocaleTimeString("en-US", { hour12: false });
    } catch {
      return timestamp.slice(0, 8);
    }
  };

  return (
    <div className="flex flex-col h-full min-h-0 rounded-lg border border-border/20 overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center gap-1.5 px-2 py-1.5 border-b border-border/20 bg-background/40 shrink-0">
        {/* Tag filters */}
        <div className="flex items-center gap-1 flex-1 overflow-x-auto scrollbar-none">
          {ALL_TAGS.map((tag) => (
            <Badge
              key={tag}
              variant="outline"
              onClick={() => toggleTag(tag)}
              className={`text-[8px] px-1.5 py-0 h-4 cursor-pointer transition-all font-mono uppercase tracking-wider shrink-0 ${
                activeTags.size === 0 || activeTags.has(tag)
                  ? getTagClass(tag)
                  : "opacity-30 border-border/20 text-muted-foreground/30"
              }`}
            >
              {tag}
            </Badge>
          ))}
        </div>

        {/* Controls */}
        <div className="flex items-center gap-0.5 shrink-0 ml-2">
          <Button
            variant="ghost"
            size="icon"
            className="size-6"
            onClick={() => setAutoScroll(!autoScroll)}
            title={autoScroll ? "Pause auto-scroll" : "Resume auto-scroll"}
          >
            {autoScroll ? (
              <ArrowDownToLine className="size-3 text-primary" />
            ) : (
              <Pause className="size-3 text-muted-foreground" />
            )}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="size-6"
            onClick={onClear}
            title="Clear logs"
          >
            <Eraser className="size-3 text-muted-foreground" />
          </Button>
        </div>
      </div>

      {/* Log content */}
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto overflow-x-hidden p-1 scrollbar-thin bg-background/20 min-h-0"
      >
        {filteredLogs.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <div className="text-center space-y-2">
              <div className="font-mono text-[11px] text-muted-foreground/30">
                Waiting for log output...
              </div>
              <div className="flex items-center justify-center gap-1">
                {[0, 1, 2].map((i) => (
                  <div
                    key={i}
                    className="size-1 rounded-full bg-primary/40 animate-pulse"
                    style={{ animationDelay: `${i * 200}ms` }}
                  />
                ))}
              </div>
            </div>
          </div>
        ) : (
          <div className="space-y-0">
            {filteredLogs.map((log, idx) => (
              <div
                key={idx}
                className={`flex items-start gap-1.5 px-1.5 py-[2px] font-mono text-[10px] leading-[16px] hover:bg-accent/20 transition-colors rounded-sm group ${getLevelClass(log.level)}`}
              >
                {/* Timestamp */}
                <span className="text-muted-foreground/40 shrink-0 tabular-nums select-none">
                  {formatTime(log.timestamp)}
                </span>

                {/* Tag */}
                <span
                  className={`shrink-0 w-[52px] text-right uppercase tracking-wider font-semibold ${
                    getTagClass(log.tag)
                      .split(" ")
                      .find((c) => c.startsWith("text-")) ?? "text-muted-foreground"
                  }`}
                >
                  {log.tag}
                </span>

                {/* Level indicator */}
                <span className="shrink-0 select-none opacity-40">
                  {log.level === "ERROR"
                    ? "E"
                    : log.level === "WARN"
                      ? "W"
                      : log.level === "DEBUG"
                        ? "D"
                        : "I"}
                </span>

                {/* Message */}
                <span className="min-w-0 break-all">{log.message}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Line count footer */}
      <div className="flex items-center justify-between px-2 py-0.5 border-t border-border/10 bg-background/30 shrink-0">
        <span className="font-mono text-[9px] text-muted-foreground/40 tabular-nums">
          {filteredLogs.length} / {logs.length} lines
        </span>
        {activeTags.size > 0 && (
          <button
            type="button"
            onClick={() => setActiveTags(new Set())}
            className="font-mono text-[9px] text-primary/60 hover:text-primary transition-colors cursor-pointer"
          >
            clear filter
          </button>
        )}
      </div>
    </div>
  );
}
