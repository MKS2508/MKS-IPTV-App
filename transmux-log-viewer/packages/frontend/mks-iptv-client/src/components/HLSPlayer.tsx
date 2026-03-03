import { Card } from "@mks2508/mks-ui/react";
import { MonitorPlay } from "lucide-react";
import { useHLSPlayer } from "@/hooks/useHLSPlayer";

/**
 * Props for the HLSPlayer component
 *
 * @property sessionId - Active transmux session ID (null = show empty state)
 */
interface IHLSPlayerProps {
  sessionId: string | null;
}

/**
 * HLS video player component with hls.js integration
 *
 * Renders a video element that loads the HLS stream from the backend
 * when a session is active. Shows an empty state with animated placeholder
 * when no session is running.
 *
 * @example
 * ```tsx
 * <HLSPlayer sessionId="abc123" />
 * <HLSPlayer sessionId={null} /> // empty state
 * ```
 */
export function HLSPlayer({ sessionId }: IHLSPlayerProps) {
  const { videoRef, error, loaded } = useHLSPlayer(sessionId);

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

            {/* Error overlay */}
            {error && (
              <div className="absolute inset-0 flex items-center justify-center bg-background/80">
                <div className="text-center space-y-1 px-4">
                  <p className="font-mono text-[11px] text-destructive/80">
                    {error}
                  </p>
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
    </Card>
  );
}
