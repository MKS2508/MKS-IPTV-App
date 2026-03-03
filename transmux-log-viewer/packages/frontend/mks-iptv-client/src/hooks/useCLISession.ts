import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import type { ICLIOptions } from "@/types/stream-source";
import type { ISessionInfo, SessionStatus } from "@/types/log";

/**
 * Shallow compare two session objects to avoid unnecessary re-renders
 *
 * @param a - First session
 * @param b - Second session
 * @returns Whether they are equivalent
 */
function sessionEqual(a: ISessionInfo | null, b: ISessionInfo | null): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  return (
    a.sessionId === b.sessionId &&
    a.status === b.status &&
    a.outputPath === b.outputPath &&
    a.playlistPath === b.playlistPath &&
    a.pid === b.pid
  );
}

/** Polling interval when a session is running */
const POLL_ACTIVE_MS = 2000;
/** Polling interval when idle (to detect external sessions) */
const POLL_IDLE_MS = 5000;

/**
 * Hook for managing TransmuxCore CLI sessions
 *
 * Provides functions to run the CLI, list sessions, and stop sessions.
 * Uses Eden Treaty client for type-safe API communication.
 *
 * Continuously polls the backend for session state — when idle every 5s
 * to auto-detect sessions started externally (curl, terminal), and every
 * 2s while a session is running for faster updates.
 *
 * Uses stable refs for polling so the effect has zero dependencies,
 * preventing interval recreation on every state change.
 *
 * @returns Session state and control functions
 */
export function useCLISession() {
  const [activeSession, setActiveSession] = useState<ISessionInfo | null>(null);
  const [sessions, setSessions] = useState<ISessionInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const activeSessionRef = useRef<ISessionInfo | null>(null);
  const statusRef = useRef<SessionStatus | undefined>(undefined);
  const mountedRef = useRef(false);

  // Keep refs in sync
  useEffect(() => {
    activeSessionRef.current = activeSession;
    const newStatus = activeSession?.status;

    // If status changed, adjust polling interval
    if (newStatus !== statusRef.current) {
      const prevStatus = statusRef.current;
      statusRef.current = newStatus;

      // Only recreate interval if crossing the running/idle boundary
      const wasRunning = prevStatus === "running";
      const isRunning = newStatus === "running";

      if (wasRunning !== isRunning && mountedRef.current) {
        const interval = isRunning ? POLL_ACTIVE_MS : POLL_IDLE_MS;
        if (pollTimerRef.current) {
          clearInterval(pollTimerRef.current);
        }
        pollTimerRef.current = setInterval(() => {
          fetchSessionsRef.current?.();
        }, interval);
      }
    }
  }, [activeSession]);

  /**
   * Fetch all sessions and update active session state.
   * Stored as ref to avoid effect dependency cycles.
   */
  const fetchSessionsRef = useRef<() => Promise<void>>();
  fetchSessionsRef.current = async () => {
    try {
      const { data, error: apiError } = await api.cli.sessions.get();

      if (apiError) {
        setError(String(apiError));
        return;
      }

      if (data) {
        const sessionList = (data.sessions ?? []) as ISessionInfo[];

        // Only update sessions array if count changed (avoid re-render)
        setSessions((prev) =>
          prev.length === sessionList.length ? prev : sessionList
        );

        const prev = activeSessionRef.current;

        if (prev) {
          // Update existing active session from backend state
          // Match by sessionId OR by PID (handles pending-* re-keying)
          const updated = sessionList.find(
            (s) =>
              s.sessionId === prev.sessionId ||
              (prev.sessionId.startsWith("pending-") && s.pid === prev.pid)
          );

          if (updated) {
            const merged = { ...prev, ...updated };
            if (!sessionEqual(prev, merged)) {
              setActiveSession(merged);
            }
          }
        } else {
          // No active session — auto-adopt any running session
          const running = sessionList.find((s) => s.status === "running");
          if (running) {
            setActiveSession(running);
          }
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  /**
   * Public fetchSessions — delegates to ref-stable internal function
   */
  const fetchSessions = useCallback(async () => {
    await fetchSessionsRef.current?.();
  }, []);

  // Single mount/unmount effect — manages polling lifecycle with zero deps
  useEffect(() => {
    mountedRef.current = true;

    // Initial fetch
    fetchSessionsRef.current?.();

    // Start idle polling
    pollTimerRef.current = setInterval(() => {
      fetchSessionsRef.current?.();
    }, POLL_IDLE_MS);

    return () => {
      mountedRef.current = false;
      if (pollTimerRef.current) {
        clearInterval(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /**
   * Run the TransmuxCore CLI with given options
   *
   * @param opts - CLI execution options
   */
  const runCLI = useCallback(async (opts: ICLIOptions) => {
    setLoading(true);
    setError(null);

    try {
      const { data, error: apiError } = await api.cli.run.post({
        input: opts.input,
        seek: opts.seek ?? 0,
        duration: opts.duration ?? 10,
        verbose: opts.verbose ?? true,
      });

      if (apiError) {
        setError(String(apiError));
        return null;
      }

      if (data) {
        const session: ISessionInfo = {
          sessionId: data.sessionId,
          pid: data.pid,
          input: opts.input,
          outputPath: data.outputPath,
          playlistPath: data.playlistPath,
          initSegmentSize: 0,
          duration: opts.duration ?? 10,
          status: "running",
          startedAt: new Date().toISOString(),
        };
        setActiveSession(session);
        return session;
      }

      return null;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(msg);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  /**
   * Stop a running CLI session
   *
   * @param sessionId - Session to stop
   */
  const stopSession = useCallback(
    async (sessionId: string) => {
      try {
        const { error: apiError } = await api.cli
          .stop({ sessionId })
          .post();

        if (apiError) {
          setError(String(apiError));
          return;
        }

        setActiveSession((prev) =>
          prev &&
          (prev.sessionId === sessionId ||
            prev.sessionId.startsWith("pending-"))
            ? { ...prev, status: "killed" }
            : prev
        );

        await fetchSessions();
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
    },
    [fetchSessions]
  );

  return {
    activeSession,
    sessions,
    loading,
    error,
    runCLI,
    fetchSessions,
    stopSession,
  };
}
