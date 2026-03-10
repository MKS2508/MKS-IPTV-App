import { Card } from "@mks2508/mks-ui/react";
import { MonitorPlay, Pause, Play, VolumeOff } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useHLSPlayer } from "@/hooks/useHLSPlayer";

/**
 * Props for the HLSPlayer component
 *
 * @property sessionId - Active transmux session ID (null = show empty state)
 * @property onSeek - Async callback to seek in the transmux source. Returns true if accepted.
 * @property onAvailableDurationChange - Callback fired when available duration updates
 */
interface IHLSPlayerProps {
  sessionId: string | null;
  onSeek?: (time: number) => Promise<boolean>;
  onAvailableDurationChange?: (duration: number) => void;
}

/**
 * Format seconds as h:mm:ss or m:ss
 *
 * @param s - Seconds to format
 * @returns Formatted time string
 */
function formatTime(s: number): string {
  if (!Number.isFinite(s) || s < 0) return "0:00";
  const totalSeconds = Math.floor(s);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return hours > 0
    ? `${hours}:${pad(minutes)}:${pad(seconds)}`
    : `${minutes}:${pad(seconds)}`;
}

/**
 * HLS video player with custom progress bar and progressive playback
 *
 * Uses HLS.js to load a BYTERANGE EVENT playlist from the backend.
 * The progress bar shows four layers: played, buffered, available, and total.
 * Supports click-to-seek within the available range and beyond (triggers backend seek).
 *
 * @example
 * ```tsx
 * <HLSPlayer sessionId="abc123" onSeek={(t) => seekSession(id, t)} />
 * <HLSPlayer sessionId={null} /> // empty state
 * ```
 */
export function HLSPlayer({ sessionId, onSeek, onAvailableDurationChange }: IHLSPlayerProps) {
  const {
    videoRef,
    loaded,
    error,
    playing,
    currentTime,
    totalDuration,
    availableDuration,
    segmentCount,
    sessionStatus,
    seekTo,
    togglePlay,
  } = useHLSPlayer(sessionId);

  const [seeking, setSeeking] = useState(false);
  const progressRef = useRef<HTMLDivElement>(null);

  /** Notify parent when available duration changes */
  useEffect(() => {
    onAvailableDurationChange?.(availableDuration);
  }, [availableDuration, onAvailableDurationChange]);

  /** The effective total for progress bar calculations */
  const effectiveTotal = totalDuration > 0 ? totalDuration : availableDuration || 1;

  /** Ratios for progress bar layers */
  const playedRatio = effectiveTotal > 0 ? Math.min(currentTime / effectiveTotal, 1) : 0;
  const availableRatio = effectiveTotal > 0 ? Math.min(availableDuration / effectiveTotal, 1) : 0;

  /**
   * Handle click on the progress bar
   *
   * If the click position is within the available range, seek natively.
   * If beyond, trigger a backend seek command.
   */
  const handleProgressClick = useCallback(
    async (e: React.MouseEvent<HTMLDivElement>) => {
      const bar = progressRef.current;
      if (!bar || effectiveTotal <= 0) return;

      const rect = bar.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const ratio = Math.max(0, Math.min(clickX / rect.width, 1));
      const targetTime = ratio * effectiveTotal;

      if (targetTime <= availableDuration) {
        // Within available range — native HLS.js seek
        seekTo(targetTime);
      } else if (onSeek) {
        // Beyond available — trigger backend seek
        setSeeking(true);
        const accepted = await onSeek(targetTime);
        if (!accepted) {
          setSeeking(false);
        }
        // Seeking overlay stays until new segments arrive
        // (poll timer in useHLSPlayer will update availableDuration)
        setTimeout(() => setSeeking(false), 5000);
      }
    },
    [effectiveTotal, availableDuration, seekTo, onSeek]
  );

  return (
    <Card className="glass border-border/20 rounded-lg overflow-hidden">
      <div className="relative h-[200px] bg-background/50">
        {sessionId ? (
          <>
            {/* Video element — hidden controls, managed by custom UI */}
            <video
              ref={videoRef}
              playsInline
              muted
              className="w-full h-full object-contain bg-background"
            />

            {/* Loading overlay */}
            {!loaded && !error && (
              <div className="absolute inset-0 flex items-center justify-center bg-background/80">
                <div className="text-center space-y-2">
                  <div className="relative size-8 mx-auto">
                    <div className="absolute inset-0 rounded-full border-2 border-primary/20" />
                    <div className="absolute inset-0 rounded-full border-2 border-primary border-t-transparent animate-spin" />
                  </div>
                  <p className="font-mono text-[10px] text-muted-foreground/60 uppercase tracking-wider">
                    Loading stream...
                  </p>
                  {segmentCount > 0 && (
                    <p className="font-mono text-[9px] text-muted-foreground/40">
                      {segmentCount} segments scanned
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* Seeking overlay */}
            {seeking && (
              <div className="absolute inset-0 flex items-center justify-center bg-background/80 z-10">
                <div className="text-center space-y-2">
                  <div className="relative size-8 mx-auto">
                    <div className="absolute inset-0 rounded-full border-2 border-primary/20" />
                    <div className="absolute inset-0 rounded-full border-2 border-primary border-t-transparent animate-spin" />
                  </div>
                  <p className="font-mono text-[10px] text-muted-foreground/60 uppercase tracking-wider">
                    Seeking...
                  </p>
                </div>
              </div>
            )}

            {/* Error overlay */}
            {error && (
              <div className="absolute inset-0 flex items-center justify-center bg-background/80">
                <div className="text-center space-y-1 px-4">
                  <p className="font-mono text-[11px] text-destructive/80">{error}</p>
                  <p className="font-mono text-[9px] text-muted-foreground/40">
                    Stream may still be initializing
                  </p>
                </div>
              </div>
            )}

            {/* No audio badge */}
            <div className="absolute top-2 right-2 flex items-center gap-1 px-1.5 py-0.5 rounded bg-background/60 backdrop-blur-sm border border-border/20">
              <VolumeOff className="size-3 text-muted-foreground/50" />
              <span className="font-mono text-[8px] text-muted-foreground/50 uppercase">
                EAC3
              </span>
            </div>
          </>
        ) : (
          /* Empty state */
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="text-center space-y-3">
              <div className="relative mx-auto w-fit">
                <MonitorPlay className="size-10 text-muted-foreground/15" strokeWidth={1} />
                <div className="absolute inset-0 animate-[pulse_3s_ease-in-out_infinite]">
                  <MonitorPlay className="size-10 text-primary/10" strokeWidth={1} />
                </div>
              </div>
              <div className="space-y-0.5">
                <p className="font-mono-emphasis text-[11px] text-muted-foreground/30 uppercase tracking-widest">
                  No Active Stream
                </p>
                <p className="font-mono text-[9px] text-muted-foreground/20">
                  Select a source and run transmux to preview
                </p>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Transport controls + progress bar */}
      {sessionId && (
        <div className="px-3 py-2 border-t border-border/15 bg-background/30 space-y-1.5">
          {/* Progress bar */}
          <div
            ref={progressRef}
            className="relative h-2 rounded-full bg-muted/20 cursor-pointer group"
            onClick={handleProgressClick}
          >
            {/* Available layer */}
            <div
              className="absolute inset-y-0 left-0 rounded-full bg-muted-foreground/15 transition-all duration-300"
              style={{ width: `${availableRatio * 100}%` }}
            />
            {/* Played layer */}
            <div
              className="absolute inset-y-0 left-0 rounded-full bg-primary transition-all duration-150"
              style={{ width: `${playedRatio * 100}%` }}
            />
            {/* Hover thumb indicator */}
            <div
              className="absolute top-1/2 -translate-y-1/2 size-3 rounded-full bg-primary shadow-[0_0_6px_var(--primary)] opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none"
              style={{ left: `calc(${playedRatio * 100}% - 6px)` }}
            />
          </div>

          {/* Controls row */}
          <div className="flex items-center gap-2">
            {/* Play/Pause */}
            <button
              onClick={togglePlay}
              className="shrink-0 flex items-center justify-center size-6 rounded-md bg-primary/10 hover:bg-primary/20 border border-primary/15 transition-colors"
              aria-label={playing ? "Pause" : "Play"}
            >
              {playing ? (
                <Pause className="size-3 text-primary" />
              ) : (
                <Play className="size-3 text-primary ml-0.5" />
              )}
            </button>

            {/* Time display */}
            <span className="font-mono text-[10px] text-foreground/70 tabular-nums">
              {formatTime(currentTime)}
            </span>
            <span className="font-mono text-[10px] text-muted-foreground/30">/</span>
            <span className="font-mono text-[10px] text-muted-foreground/50 tabular-nums">
              {formatTime(totalDuration)}
            </span>

            {/* Spacer */}
            <div className="flex-1" />

            {/* Status indicators */}
            <div className="flex items-center gap-2">
              {/* Available duration */}
              {availableDuration > 0 && (
                <div className="flex items-center gap-1">
                  <div className="size-1.5 rounded-full bg-muted-foreground/30" />
                  <span className="font-mono text-[9px] text-muted-foreground/40">
                    {formatTime(availableDuration)} avail
                  </span>
                </div>
              )}

              {/* Segment count */}
              {segmentCount > 0 && (
                <span className="font-mono text-[9px] text-muted-foreground/30 tabular-nums">
                  {segmentCount} seg
                </span>
              )}

              {/* Session status badge */}
              <span
                className={`font-mono text-[8px] uppercase tracking-wider px-1.5 py-0.5 rounded border ${
                  sessionStatus === "running"
                    ? "text-primary/70 border-primary/20 bg-primary/5"
                    : sessionStatus === "completed"
                      ? "text-chart-2/70 border-chart-2/20 bg-chart-2/5"
                      : "text-muted-foreground/40 border-border/15 bg-background/30"
                }`}
              >
                {sessionStatus}
              </span>
            </div>
          </div>
        </div>
      )}
    </Card>
  );
}
