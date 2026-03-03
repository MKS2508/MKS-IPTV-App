import { useCallback, useEffect, useRef, useState } from "react";
import type { ILogEntry, ILogStats } from "@/types/log";

const MAX_BUFFER_SIZE = 5000;
const RECONNECT_BASE_MS = 1000;
const RECONNECT_MAX_MS = 10000;

/** SSE endpoint — uses VITE_API_URL when available (portless mode) */
const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";
const SSE_URL = `${API_BASE}/logs/stream`;

/**
 * Hook for consuming the SSE log stream from the backend
 *
 * Connects to /logs/stream via EventSource. The backend uses Elysia's
 * native sse() helper, so each event's data field contains a JSON object.
 * Maintains a buffer of parsed log entries (max 5000) and calculates
 * incremental stats.
 *
 * Uses stable refs internally so the mount effect has zero dependencies,
 * preventing reconnect cycles caused by parent re-renders.
 *
 * @returns Log entries, stats, connection status, and control functions
 */
export function useLogStream() {
  const [logs, setLogs] = useState<ILogEntry[]>([]);
  const [stats, setStats] = useState<ILogStats>({
    total: 0,
    errors: 0,
    warns: 0,
    seeks: 0,
    packets: 0,
  });
  const [connected, setConnected] = useState(false);
  const eventSourceRef = useRef<EventSource | null>(null);
  const reconnectAttemptRef = useRef(0);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mountedRef = useRef(false);

  /**
   * Connect to the SSE stream with automatic reconnection.
   * Stored as a ref-stable function to avoid effect dependency cycles.
   */
  const connectRef = useRef<() => void>();
  connectRef.current = () => {
    // Cleanup previous connection
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
    }
    if (reconnectTimerRef.current) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }

    const es = new EventSource(SSE_URL);
    eventSourceRef.current = es;

    es.onopen = () => {
      setConnected(true);
      reconnectAttemptRef.current = 0;
    };

    es.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        // Skip connection meta messages
        if (data.type === "connected" || data.type === "error") return;

        const entry: ILogEntry = {
          timestamp: data.timestamp || new Date().toISOString(),
          tag: data.tag || "UNKNOWN",
          level: data.level || "INFO",
          message: data.message || data.raw || "",
          raw: data.raw || JSON.stringify(data),
        };

        setLogs((prev) => {
          const next = [...prev, entry];
          return next.length > MAX_BUFFER_SIZE ? next.slice(-MAX_BUFFER_SIZE) : next;
        });

        setStats((prev) => ({
          total: prev.total + 1,
          errors: prev.errors + (entry.level === "ERROR" ? 1 : 0),
          warns: prev.warns + (entry.level === "WARN" ? 1 : 0),
          seeks: prev.seeks + (entry.tag === "SEEK" ? 1 : 0),
          packets:
            prev.packets + (entry.message.toLowerCase().includes("packet") ? 1 : 0),
        }));
      } catch {
        // Ignore malformed SSE data
      }
    };

    es.onerror = () => {
      setConnected(false);
      es.close();
      eventSourceRef.current = null;

      // Only reconnect if still mounted
      if (!mountedRef.current) return;

      // Exponential backoff reconnection
      const attempt = reconnectAttemptRef.current;
      const delay = Math.min(RECONNECT_BASE_MS * 2 ** attempt, RECONNECT_MAX_MS);
      reconnectAttemptRef.current = attempt + 1;

      reconnectTimerRef.current = setTimeout(() => {
        connectRef.current?.();
      }, delay);
    };
  };

  /**
   * Disconnect from the SSE stream
   */
  const disconnect = useCallback(() => {
    if (reconnectTimerRef.current) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
      setConnected(false);
    }
  }, []);

  /**
   * Public connect — delegates to the ref-stable internal connect
   */
  const connect = useCallback(() => {
    connectRef.current?.();
  }, []);

  /**
   * Clear the log buffer and reset stats
   */
  const clearLogs = useCallback(() => {
    setLogs([]);
    setStats({ total: 0, errors: 0, warns: 0, seeks: 0, packets: 0 });
  }, []);

  // Auto-connect on mount, cleanup on unmount — zero deps
  useEffect(() => {
    mountedRef.current = true;
    connectRef.current?.();

    return () => {
      mountedRef.current = false;
      disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return {
    logs,
    stats,
    connected,
    connect,
    disconnect,
    clearLogs,
  };
}
