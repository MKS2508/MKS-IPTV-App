import { useCallback, useEffect, useRef, useState } from "react";

/** Resolve API base URL for stream endpoints */
const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";

/**
 * Hook for managing video player lifecycle
 *
 * Loads the fMP4 stream directly from the backend stream.mp4 endpoint.
 * TransmuxCore outputs a single progressive fMP4 — no HLS segments needed.
 *
 * @param sessionId - Active transmux session ID (null = no source)
 * @returns Video ref, player state, and control functions
 */
export function useHLSPlayer(sessionId: string | null) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  const currentSessionRef = useRef<string | null>(null);

  /**
   * Load the stream.mp4 for the given session
   */
  const loadSource = useCallback((sid: string) => {
    const video = videoRef.current;
    if (!video) return;

    currentSessionRef.current = sid;
    setError(null);
    setLoaded(false);

    const streamUrl = `${API_BASE}/hls/${sid}/stream.mp4`;
    video.src = streamUrl;

    const onLoaded = () => {
      setLoaded(true);
      video.play().catch(() => {
        // Autoplay may be blocked
      });
    };

    const onError = () => {
      setError("Failed to load stream");
    };

    video.addEventListener("loadedmetadata", onLoaded, { once: true });
    video.addEventListener("error", onError, { once: true });
  }, []);

  /**
   * Reload the video source with a cache-busting param.
   *
   * After a seek the FFmpeg pipeline writes new content into stream.mp4
   * starting from the seek position. The browser won't re-request the
   * file on its own so we force a reload by resetting `video.src`.
   */
  const reloadSource = useCallback(() => {
    const video = videoRef.current;
    const sid = currentSessionRef.current;
    if (!video || !sid) return;

    setError(null);
    setLoaded(false);

    const streamUrl = `${API_BASE}/hls/${sid}/stream.mp4?t=${Date.now()}`;
    video.src = streamUrl;

    const onLoaded = () => {
      setLoaded(true);
      video.play().catch(() => {
        // Autoplay may be blocked
      });
    };

    const onError = () => {
      setError("Failed to reload stream after seek");
    };

    video.addEventListener("loadedmetadata", onLoaded, { once: true });
    video.addEventListener("error", onError, { once: true });
  }, []);

  // Load source when sessionId changes
  useEffect(() => {
    if (sessionId) {
      currentSessionRef.current = sessionId;
      loadSource(sessionId);
    } else {
      // Clear video when session ends
      currentSessionRef.current = null;
      const video = videoRef.current;
      if (video) {
        video.removeAttribute("src");
        video.load();
      }
      setLoaded(false);
      setError(null);
    }
  }, [sessionId, loadSource]);

  // Track play/pause state
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);

    video.addEventListener("play", onPlay);
    video.addEventListener("pause", onPause);

    return () => {
      video.removeEventListener("play", onPlay);
      video.removeEventListener("pause", onPause);
    };
  }, []);

  return {
    videoRef,
    playing,
    error,
    loaded,
    loadSource,
    reloadSource,
  };
}
