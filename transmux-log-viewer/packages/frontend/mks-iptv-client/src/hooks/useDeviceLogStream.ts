import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { LogParserService, PersistentLogBuffer, type IParsedLogEntry, type TLogLevel } from "@mks2508/mks-ui/react/blocks/Terminal";

/**
 * Device info from WebSocket handshake.
 */
export interface IDeviceInfo {
  sessionId: string;
  deviceName: string;
  appVersion: string;
  systemVersion: string;
  playerState: string;
  connectedAt: string;
}

/**
 * Log entry from iOS device via SSE /device/stream.
 */
interface IDeviceLogSSE {
  type: "log" | "connected";
  timestamp?: string;
  level?: string;
  category?: string;
  tag?: string;
  message?: string;
  fields?: Record<string, string>;
  sessionId?: string;
  source?: "device";
}

/**
 * Hook that connects to the Elysia backend's /device/stream SSE endpoint
 * and parses incoming iOS device logs using mks-ui's LogParserService.
 *
 * Also polls /device/sessions for connected device info.
 *
 * @example
 * ```tsx
 * const { entries, devices, connected, levelCounts, clear } = useDeviceLogStream();
 * ```
 */
export function useDeviceLogStream() {
  const [entries, setEntries] = useState<IParsedLogEntry[]>([]);
  const [connected, setConnected] = useState(false);
  const [devices, setDevices] = useState<IDeviceInfo[]>([]);

  const parser = useMemo(() => new LogParserService({
    enable_ansi: true,
    timestamp_format: "time",
    enable_structured: true,
    enable_tags: true,
  }), []);

  const buffer = useMemo(() => new PersistentLogBuffer({ maxSize: 50000 }), []);
  const lineNumberRef = useRef(0);
  const eventSourceRef = useRef<EventSource | null>(null);
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Backend base URL (portless or localhost)
  const baseUrl = useMemo(() => {
    if (window.location.hostname.includes("localhost")) {
      return `http://localhost:${window.location.port || 3000}`;
    }
    // Portless mode: api is on a different subdomain
    return window.location.origin.replace("transmux-app", "transmux-api");
  }, []);

  // Connect to SSE /device/stream
  const connect = useCallback(() => {
    if (eventSourceRef.current) return;

    const es = new EventSource(`${baseUrl}/device/stream`);
    eventSourceRef.current = es;

    es.onopen = () => setConnected(true);
    es.onerror = () => {
      setConnected(false);
      // Auto-reconnect after 3s
      setTimeout(() => {
        eventSourceRef.current?.close();
        eventSourceRef.current = null;
        connect();
      }, 3000);
    };

    es.onmessage = (event) => {
      try {
        const data: IDeviceLogSSE = JSON.parse(event.data);
        if (data.type === "connected") return;
        if (data.type !== "log") return;

        // Format the log line for parsing
        const ts = data.timestamp?.split("T")[1]?.split("Z")[0] || "";
        const level = (data.level || "info").toUpperCase().slice(0, 3);
        const tag = data.tag || data.category || "?";
        const fieldsStr = data.fields
          ? Object.entries(data.fields).map(([k, v]) => `${k}=${v}`).join(" ")
          : "";
        const line = `[${ts}] [${level}] [${tag}] ${data.message || ""} ${fieldsStr}`.trim();

        const entry = parser.parseLine(line, ++lineNumberRef.current, false);
        buffer.append([entry]);

        setEntries((prev) => {
          const next = [...prev, entry];
          return next.length > 5000 ? next.slice(-5000) : next;
        });
      } catch {
        // Ignore parse errors
      }
    };
  }, [baseUrl, parser, buffer]);

  // Disconnect
  const disconnect = useCallback(() => {
    eventSourceRef.current?.close();
    eventSourceRef.current = null;
    setConnected(false);
  }, []);

  // Poll connected devices
  useEffect(() => {
    const poll = async () => {
      try {
        const res = await fetch(`${baseUrl}/device/sessions`);
        if (res.ok) {
          const data = await res.json();
          setDevices(data.devices || []);
        }
      } catch {
        // Ignore
      }
    };

    poll();
    pollTimerRef.current = setInterval(poll, 5000);
    return () => {
      if (pollTimerRef.current) clearInterval(pollTimerRef.current);
    };
  }, [baseUrl]);

  // Auto-connect on mount
  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  // Level counts
  const levelCounts = useMemo(() => {
    const counts: Partial<Record<TLogLevel, number>> = {};
    for (const e of entries) {
      counts[e.level] = (counts[e.level] || 0) + 1;
    }
    return counts;
  }, [entries]);

  // Clear
  const clear = useCallback(() => {
    setEntries([]);
    lineNumberRef.current = 0;
    buffer.clear();
  }, [buffer]);

  // Send command to device
  const sendCommand = useCallback(async (command: string, payload?: Record<string, string>) => {
    try {
      await fetch(`${baseUrl}/device/command`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command, payload }),
      });
    } catch {
      // Ignore
    }
  }, [baseUrl]);

  return {
    entries,
    devices,
    connected,
    levelCounts,
    clear,
    connect,
    disconnect,
    sendCommand,
    buffer,
  };
}
