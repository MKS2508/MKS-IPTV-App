import { useCallback, useMemo, useRef, useState } from "react";
import {
  TerminalLogsPanel,
  type ITerminalLogsPanelRef,
  type ITerminalSession,
  type TLogLevelFilter,
  SYNTHWAVE_TERMINAL_THEME,
} from "@mks2508/mks-ui/react/blocks/Terminal";
import { Badge, Button } from "@mks2508/mks-ui/react";
import {
  Monitor,
  MonitorSmartphone,
  Pause,
  Play,
  RefreshCw,
  SkipForward,
  Square,
  Trash2,
  Download,
  Search,
  Wifi,
  WifiOff,
  Send,
  Bug,
} from "lucide-react";
import { useDeviceLogStream, type IDeviceInfo } from "@/hooks/useDeviceLogStream";

/**
 * Full-featured remote device log viewer using mks-ui Terminal block.
 *
 * Features:
 * - Real-time log streaming from iOS/macOS devices via SSE
 * - TerminalLogsPanel with restty GPU renderer
 * - Multi-device tabs (when multiple devices connected)
 * - Log level filtering with counts
 * - Search, auto-scroll, line numbers
 * - Remote command panel (play/pause/seek/stop/debug info)
 * - Device info display (name, OS version, app version)
 *
 * @example
 * ```tsx
 * <DeviceLogViewer />
 * ```
 */
export function DeviceLogViewer() {
  const {
    entries,
    devices,
    connected,
    levelCounts,
    clear,
    sendCommand,
  } = useDeviceLogStream();

  const panelRef = useRef<ITerminalLogsPanelRef>(null);
  const [filterLevel, setFilterLevel] = useState<TLogLevelFilter>("all");
  const [followCursor, setFollowCursor] = useState(true);
  const [showLineNumbers, setShowLineNumbers] = useState(false);
  const [viewMode, setViewMode] = useState<"terminal" | "react">("terminal");
  const [activeDeviceId, setActiveDeviceId] = useState<string | null>(null);
  const [seekValue, setSeekValue] = useState("300");

  // Build session tabs from connected devices
  const sessions: ITerminalSession[] = useMemo(() => {
    if (devices.length === 0) {
      return [{
        id: "waiting",
        name: "Waiting for device...",
        status: "disconnected" as const,
      }];
    }
    return devices.map((d) => ({
      id: d.sessionId,
      name: `${d.deviceName} (${d.systemVersion})`,
      status: "connected" as const,
    }));
  }, [devices]);

  // Container info for header
  const containers = useMemo(() =>
    devices.map((d) => ({
      id: d.sessionId,
      name: d.deviceName,
      state: "running",
    })),
  [devices]);

  // Filter entries by device if multiple connected
  const filteredEntries = useMemo(() => {
    if (!activeDeviceId || devices.length <= 1) return entries;
    // All entries come from SSE merged — no per-device filter available yet
    return entries;
  }, [entries, activeDeviceId, devices]);

  // Command handlers
  const handlePlay = useCallback(() => sendCommand("play"), [sendCommand]);
  const handlePause = useCallback(() => sendCommand("pause"), [sendCommand]);
  const handleStop = useCallback(() => sendCommand("stop"), [sendCommand]);
  const handleSeek = useCallback(() => {
    sendCommand("seek", { position: seekValue });
  }, [sendCommand, seekValue]);
  const handleDebugInfo = useCallback(() => sendCommand("getDebugInfo"), [sendCommand]);
  const handleForceReload = useCallback(() => sendCommand("forceReloadPipeline"), [sendCommand]);

  const handleDownload = useCallback(() => {
    const text = entries.map((e) => e.raw).join("\n");
    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `device-logs-${new Date().toISOString().slice(0, 19)}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  }, [entries]);

  const handleSearch = useCallback(() => {
    const term = prompt("Search logs:");
    if (term) panelRef.current?.search(term);
  }, []);

  return (
    <div className="flex flex-col h-full gap-3">
      {/* Header: Connection status + device info */}
      <div className="flex items-center justify-between px-4 py-2 rounded-lg bg-card/50 border border-border/50">
        <div className="flex items-center gap-3">
          {connected ? (
            <Wifi className="w-4 h-4 text-green-500" />
          ) : (
            <WifiOff className="w-4 h-4 text-red-500" />
          )}
          <span className="text-sm font-medium">
            {connected ? "Device Stream Active" : "Waiting for device..."}
          </span>
          {devices.length > 0 && (
            <Badge variant="secondary">
              {devices.length} device{devices.length > 1 ? "s" : ""}
            </Badge>
          )}
          {entries.length > 0 && (
            <Badge variant="outline">{entries.length} logs</Badge>
          )}
        </div>

        {/* Device info badges */}
        <div className="flex items-center gap-2">
          {devices.map((d) => (
            <DeviceInfoBadge key={d.sessionId} device={d} />
          ))}
        </div>
      </div>

      {/* Command panel (only when device connected) */}
      {devices.length > 0 && (
        <div className="flex items-center gap-2 px-4 py-2 rounded-lg bg-card/50 border border-border/50">
          <span className="text-xs font-semibold text-muted-foreground mr-2">Remote:</span>

          <Button size="sm" variant="outline" onClick={handlePlay}>
            <Play className="w-3 h-3 mr-1" /> Play
          </Button>
          <Button size="sm" variant="outline" onClick={handlePause}>
            <Pause className="w-3 h-3 mr-1" /> Pause
          </Button>
          <Button size="sm" variant="outline" onClick={handleStop}>
            <Square className="w-3 h-3 mr-1" /> Stop
          </Button>

          <div className="flex items-center gap-1 ml-2">
            <input
              type="number"
              value={seekValue}
              onChange={(e) => setSeekValue(e.target.value)}
              className="w-20 h-7 px-2 text-xs rounded border border-border bg-background"
              placeholder="seconds"
            />
            <Button size="sm" variant="outline" onClick={handleSeek}>
              <SkipForward className="w-3 h-3 mr-1" /> Seek
            </Button>
          </div>

          <div className="ml-auto flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={handleDebugInfo}>
              <Bug className="w-3 h-3 mr-1" /> Debug Info
            </Button>
            <Button size="sm" variant="outline" onClick={handleForceReload}>
              <RefreshCw className="w-3 h-3 mr-1" /> Reload Pipeline
            </Button>
          </div>
        </div>
      )}

      {/* Terminal logs panel */}
      <div className="flex-1 min-h-0">
        <TerminalLogsPanel
          ref={panelRef}
          containerName={devices[0]?.deviceName || "Device Logs"}
          isConnected={connected && devices.length > 0}
          parsedEntries={filteredEntries}
          filterLevel={filterLevel}
          followCursor={followCursor}
          showLineNumbers={showLineNumbers}
          levelCounts={levelCounts}
          viewMode={viewMode}
          sessions={sessions}
          activeSessionId={activeDeviceId || sessions[0]?.id}
          containers={containers}
          onSessionChange={(id) => setActiveDeviceId(id)}
          onSessionClose={() => {}}
          onNewSession={() => {}}
          onFilterChange={setFilterLevel}
          onFollowCursorChange={setFollowCursor}
          onShowLineNumbersChange={setShowLineNumbers}
          onViewModeChange={setViewMode}
          onClear={clear}
          onDownload={handleDownload}
          onSearch={handleSearch}
        />
      </div>
    </div>
  );
}

/**
 * Compact badge showing device info (name, OS, version).
 */
function DeviceInfoBadge({ device }: { device: IDeviceInfo }) {
  return (
    <div className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-green-500/10 border border-green-500/20">
      <MonitorSmartphone className="w-3 h-3 text-green-500" />
      <span className="text-xs font-medium text-green-400">{device.deviceName}</span>
      <span className="text-xs text-muted-foreground">{device.systemVersion}</span>
      <span className="text-xs text-muted-foreground">v{device.appVersion}</span>
    </div>
  );
}
