import type { ILogStats } from "@/types/log";

/**
 * Props for the StatsBar component
 *
 * @property stats - Aggregated log statistics
 * @property connected - Whether the SSE stream is connected
 */
interface IStatsBarProps {
  stats: ILogStats;
  connected: boolean;
}

/**
 * Horizontal telemetry bar displaying real-time log statistics
 *
 * Shows counters for total lines, errors, warnings, seeks, and packets.
 * Each counter is color-coded by severity. Includes a connection status
 * indicator.
 *
 * @example
 * ```tsx
 * <StatsBar stats={logStats} connected={true} />
 * ```
 */
export function StatsBar({ stats, connected }: IStatsBarProps) {
  return (
    <div className="flex items-center gap-3 px-3 py-1.5 border-t border-border/15 bg-background/30 shrink-0">
      {/* Connection indicator */}
      <div className="flex items-center gap-1.5">
        <div
          className={`size-1.5 rounded-full ${
            connected
              ? "bg-primary shadow-[0_0_6px_var(--primary)]"
              : "bg-muted-foreground/30"
          }`}
        />
        <span className="font-mono text-[9px] text-muted-foreground/50 uppercase tracking-wider">
          {connected ? "Live" : "Disconnected"}
        </span>
      </div>

      <div className="h-3 w-px bg-border/20" />

      {/* Stat counters */}
      <StatCounter label="Lines" value={stats.total} />
      <StatCounter
        label="Errors"
        value={stats.errors}
        highlight={stats.errors > 0 ? "destructive" : undefined}
      />
      <StatCounter
        label="Warns"
        value={stats.warns}
        highlight={stats.warns > 0 ? "chart-1" : undefined}
      />
      <StatCounter label="Seeks" value={stats.seeks} highlight={stats.seeks > 0 ? "chart-2" : undefined} />
      <StatCounter label="Packets" value={stats.packets} />
    </div>
  );
}

/**
 * Individual stat counter with optional color highlight
 */
function StatCounter({
  label,
  value,
  highlight,
}: {
  label: string;
  value: number;
  highlight?: "destructive" | "chart-1" | "chart-2";
}) {
  const valueColorClass = highlight
    ? highlight === "destructive"
      ? "text-destructive"
      : highlight === "chart-1"
        ? "text-chart-1"
        : "text-chart-2"
    : "text-foreground/60";

  return (
    <div className="flex items-center gap-1">
      <span className="font-mono text-[9px] text-muted-foreground/40 uppercase tracking-wider">
        {label}
      </span>
      <span className={`font-mono-emphasis text-[11px] tabular-nums ${valueColorClass}`}>
        {value.toLocaleString()}
      </span>
    </div>
  );
}
