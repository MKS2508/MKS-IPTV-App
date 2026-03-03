import { Button, Card, Input } from "@mks2508/mks-ui/react";
import { FastForward, MonitorPlay } from "lucide-react";
import { useCallback, useRef, useState } from "react";
import { useHLSPlayer } from "@/hooks/useHLSPlayer";

/**
 * Props for the HLSPlayer component
 *
 * @property sessionId - Active transmux session ID (null = show empty state)
 * @property onSeek - Async callback to seek in the transmux source. Returns true if accepted.
 */
interface IHLSPlayerProps {
  sessionId: string | null;
  onSeek?: (time: number) => Promise<boolean>;
}

/**
 * HLS video player component with hls.js integration and seek controls
 *
 * Renders a video element that loads the HLS stream from the backend
 * when a session is active. Includes a seek bar to jump to specific
 * positions in the source file via the TransmuxCore seek API.
 * Shows an empty state with animated placeholder when no session is running.
 *
 * @example
 * ```tsx
 * <HLSPlayer sessionId="abc123" onSeek={(t) => seekSession(id, t)} />
 * <HLSPlayer sessionId={null} /> // empty state
 * ```
 */
export function HLSPlayer({ sessionId, onSeek }: IHLSPlayerProps) {
  const { videoRef, error, loaded, reloadSource } = useHLSPlayer(sessionId);
  const [seekInput, setSeekInput] = useState("");
  const [seeking, setSeeking] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  /**
   * Handle seek form submission.
   *
   * Awaits the backend seek command, then reloads the video source
   * after a delay so the browser fetches the post-seek content.
   */
  const handleSeek = useCallback(async () => {
    const time = parseFloat(seekInput);
    if (Number.isNaN(time) || time < 0 || !onSeek) return;

    setSeeking(true);
    const accepted = await onSeek(time);
    if (accepted) {
      setTimeout(() => {
        reloadSource();
        setSeeking(false);
      }, 2500);
    } else {
      setSeeking(false);
    }
  }, [seekInput, onSeek, reloadSource]);

  /**
   * Handle preset seek button clicks
   */
  const handlePresetSeek = useCallback(
    async (time: number) => {
      if (!onSeek) return;
      setSeekInput(String(time));
      setSeeking(true);
      const accepted = await onSeek(time);
      if (accepted) {
        setTimeout(() => {
          reloadSource();
          setSeeking(false);
        }, 2500);
      } else {
        setSeeking(false);
      }
    },
    [onSeek, reloadSource]
  );

  return (
    <Card className="glass border-border/20 rounded-lg overflow-hidden">
      <div className="relative aspect-video bg-background/50">
        {sessionId ? (
          <>
            <video
              ref={videoRef}
              controls
              playsInline
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

      {/* Seek controls — only shown when a session is active */}
      {sessionId && onSeek && (
        <div className="flex items-center gap-2 px-3 py-2 border-t border-border/15 bg-background/30">
          <FastForward className="size-3.5 text-muted-foreground/50 shrink-0" />
          <span className="font-mono text-[9px] text-muted-foreground/50 uppercase tracking-wider shrink-0">
            Seek
          </span>
          <div className="flex items-center gap-1">
            {[60, 300, 600, 1800].map((t) => (
              <Button
                key={t}
                variant="ghost"
                size="sm"
                className="h-5 px-1.5 font-mono text-[9px] text-muted-foreground/60 hover:text-foreground"
                onClick={() => handlePresetSeek(t)}
                disabled={seeking}
              >
                {t >= 60 ? `${Math.floor(t / 60)}m` : `${t}s`}
              </Button>
            ))}
          </div>
          <div className="flex items-center gap-1 ml-auto">
            <Input
              ref={inputRef}
              type="number"
              placeholder="seconds"
              value={seekInput}
              onChange={(e) => setSeekInput(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSeek()}
              className="h-5 w-20 font-mono text-[10px] px-1.5 bg-background/40 border-border/20"
            />
            <Button
              variant="outline"
              size="sm"
              className="h-5 px-2 font-mono text-[9px]"
              onClick={handleSeek}
              disabled={seeking || !seekInput}
            >
              {seeking ? "..." : "Go"}
            </Button>
          </div>
        </div>
      )}
    </Card>
  );
}
