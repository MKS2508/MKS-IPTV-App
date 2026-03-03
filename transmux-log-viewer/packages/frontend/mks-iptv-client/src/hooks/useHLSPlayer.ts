import Hls from "hls.js";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Hook for managing HLS.js video player lifecycle
 *
 * Creates an HLS.js instance, loads the backend HLS source,
 * attaches to a video element, and handles cleanup on unmount.
 *
 * @param sessionId - Active transmux session ID (null = no source)
 * @returns Video ref, player state, and control functions
 */
export function useHLSPlayer(sessionId: string | null) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);
  const [playing, setPlaying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  /**
   * Load the HLS source for the given session
   */
  const loadSource = useCallback(
    (sid: string) => {
      const video = videoRef.current;
      if (!video) return;

      // Clean up existing instance
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }

      setError(null);
      setLoaded(false);

      const apiBase = import.meta.env.VITE_API_URL || "http://localhost:3000";
      const playlistUrl = `${apiBase}/hls/${sid}/playlist.m3u8`;

      if (Hls.isSupported()) {
        const hls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
        });

        hls.loadSource(playlistUrl);
        hls.attachMedia(video);

        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          setLoaded(true);
          video.play().catch(() => {
            // Autoplay may be blocked
          });
        });

        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (data.fatal) {
            setError(`HLS error: ${data.type} - ${data.details}`);

            if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
              hls.startLoad();
            } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
              hls.recoverMediaError();
            } else {
              hls.destroy();
            }
          }
        });

        hlsRef.current = hls;
      } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
        // Native HLS support (Safari)
        video.src = playlistUrl;
        video.addEventListener("loadedmetadata", () => {
          setLoaded(true);
          video.play().catch(() => {});
        });
      } else {
        setError("HLS is not supported in this browser");
      }
    },
    []
  );

  // Load source when sessionId changes
  useEffect(() => {
    if (sessionId) {
      loadSource(sessionId);
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

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
    };
  }, []);

  return {
    videoRef,
    playing,
    error,
    loaded,
    loadSource,
  };
}
