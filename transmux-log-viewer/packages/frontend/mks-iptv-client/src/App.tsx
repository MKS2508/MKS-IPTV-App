import { Badge, Button } from "@mks2508/mks-ui/react";
import { type IAnimationSettings, SettingsModal } from "@mks2508/theme-manager-react";
import { Activity, MonitorSmartphone, Settings, Terminal } from "lucide-react";
import { useCallback, useState } from "react";
import { ThemeTogglerButton } from "@/components/animate-ui/components/buttons/theme-toggler";
import { DeviceLogViewer } from "@/components/DeviceLogViewer";
import { HLSPlayer } from "@/components/HLSPlayer";
import { LogViewer } from "@/components/LogViewer";
import { SessionInfo } from "@/components/SessionInfo";
import { SourcePanel } from "@/components/SourcePanel";
import { StatsBar } from "@/components/StatsBar";
import { ThemeSelector } from "@/components/ThemeSelector";
import { useCLISession } from "@/hooks/useCLISession";
import { useLogStream } from "@/hooks/useLogStream";

/**
 * Main application component for TransmuxCore Test Pipeline
 *
 * Composes the full testing dashboard with source selection (left panel),
 * HLS player, session info, real-time log viewer, and stats bar (right panel).
 * Wires hooks to components for CLI execution and log streaming.
 */
export function App() {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [animationSettings, setAnimationSettings] = useState<IAnimationSettings>({
    preset: "wipe",
    direction: "ltr",
    duration: 500,
  });

  const [availableDuration, setAvailableDuration] = useState(0);
  const [activeTab, setActiveTab] = useState<"cli" | "device">("cli");

  const { logs, stats, connected, clearLogs } = useLogStream();
  const { activeSession, loading, runCLI, stopSession, seekSession } = useCLISession();

  /**
   * Handle run from SourcePanel
   */
  const handleRun = useCallback(
    (input: string, opts: { seek: number; duration: number; verbose: boolean }) => {
      clearLogs();
      runCLI({ input, ...opts });
    },
    [clearLogs, runCLI]
  );

  /**
   * Handle stop from SourcePanel or SessionInfo
   */
  const handleStop = useCallback(() => {
    if (activeSession) {
      stopSession(activeSession.sessionId);
    }
  }, [activeSession, stopSession]);

  /**
   * Handle seek from HLSPlayer controls
   *
   * @param time - Target time in seconds
   * @returns Whether the seek was accepted by the backend
   */
  const handleSeek = useCallback(
    async (time: number): Promise<boolean> => {
      if (activeSession && activeSession.status === "running") {
        return seekSession(activeSession.sessionId, time);
      }
      return false;
    },
    [activeSession, seekSession]
  );

  const isRunning = activeSession?.status === "running" || loading;

  return (
    <div className="h-screen flex flex-col bg-background text-foreground grain-overlay tech-grid overflow-hidden">
      {/* Header */}
      <header className="sticky top-0 z-50 w-full border-b border-border/30 glass shrink-0">
        <div className="flex h-11 items-center justify-between px-4">
          <div className="flex items-center gap-3">
            <div className="relative flex size-7 items-center justify-center rounded-md bg-primary/10 border border-primary/15">
              <Terminal className="size-3.5 text-primary" />
              {connected && (
                <div className="absolute -top-0.5 -right-0.5 size-1.5 rounded-full bg-primary shadow-[0_0_6px_var(--primary)]" />
              )}
            </div>
            <div className="flex items-center gap-2">
              <h1 className="font-mono-emphasis text-sm uppercase tracking-wider">TransmuxCore</h1>
              <Badge variant="outline" className="font-mono text-[9px] h-4 px-1.5 border-border/30">
                Debug Viewer
              </Badge>
            </div>

            {/* Tab switcher */}
            <div className="flex items-center gap-1 ml-4">
              <button
                onClick={() => setActiveTab("cli")}
                className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                  activeTab === "cli"
                    ? "bg-primary/15 text-primary border border-primary/20"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/30"
                }`}
              >
                <Terminal className="size-3" />
                CLI Pipeline
              </button>
              <button
                onClick={() => setActiveTab("device")}
                className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                  activeTab === "device"
                    ? "bg-primary/15 text-primary border border-primary/20"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted/30"
                }`}
              >
                <MonitorSmartphone className="size-3" />
                Device Logs
              </button>
            </div>
          </div>

          <div className="flex items-center gap-1.5">
            {/* Connection status */}
            <div className="flex items-center gap-1.5 mr-2 px-2 py-0.5 rounded-md bg-background/30 border border-border/15">
              <Activity
                className={`size-3 ${connected ? "text-primary" : "text-muted-foreground/30"}`}
              />
              <span className="font-mono text-[9px] text-muted-foreground/60 uppercase tracking-wider">
                {connected ? "SSE" : "Off"}
              </span>
            </div>

            <ThemeSelector
              animation={animationSettings.preset}
              direction={animationSettings.direction}
              duration={animationSettings.duration}
            />
            <ThemeTogglerButton
              variant="ghost"
              size="icon"
              className="size-7"
              animation={animationSettings.preset}
              direction={animationSettings.direction}
              duration={animationSettings.duration}
            />
            <Button
              variant="ghost"
              size="icon"
              className="size-7"
              onClick={() => setSettingsOpen(true)}
            >
              <Settings className="size-3.5" />
            </Button>
          </div>
        </div>
      </header>

      {/* Main content area */}
      <div className="flex-1 flex min-h-0 overflow-hidden">
        {activeTab === "cli" ? (
          <>
            {/* Left panel - Source selector */}
            <aside className="w-[280px] shrink-0 border-r border-border/15 bg-background/20 overflow-hidden">
              <SourcePanel onRun={handleRun} onStop={handleStop} isRunning={isRunning} />
            </aside>

            {/* Right panel - Player + Logs */}
            <main className="flex-1 flex flex-col min-h-0 min-w-0 overflow-hidden">
              <div className="flex-1 flex flex-col gap-2 p-3 min-h-0 overflow-hidden">
                {/* HLS Player */}
                <div className="shrink-0">
                  <HLSPlayer
                    sessionId={
                      activeSession &&
                      !activeSession.sessionId.startsWith("pending-") &&
                      (activeSession.status === "running" || activeSession.status === "completed")
                        ? activeSession.sessionId
                        : null
                    }
                    onSeek={isRunning ? handleSeek : undefined}
                    onAvailableDurationChange={setAvailableDuration}
                  />
                </div>

                {/* Session Info */}
                <div className="shrink-0">
                  <SessionInfo session={activeSession} onStop={(id) => stopSession(id)} />
                </div>

                {/* Log Viewer */}
                <div className="flex-1 min-h-0">
                  <LogViewer logs={logs} onClear={clearLogs} />
                </div>
              </div>

              {/* Stats Bar */}
              <StatsBar stats={stats} connected={connected} availableDuration={availableDuration} />
            </main>
          </>
        ) : (
          /* Device Logs tab — full-width Terminal panel */
          <main className="flex-1 flex flex-col min-h-0 min-w-0 overflow-hidden p-3">
            <DeviceLogViewer />
          </main>
        )}
      </div>

      {/* Settings Modal */}
      <SettingsModal
        open={settingsOpen}
        onOpenChange={setSettingsOpen}
        initialTab="themes"
        animationSettings={animationSettings}
        onAnimationSettingsChange={setAnimationSettings}
      />
    </div>
  );
}

export default App;
