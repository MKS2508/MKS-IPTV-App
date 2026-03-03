import { Elysia, t } from "elysia";
import { HLSService } from "./service";

/**
 * HLS module - Serves transmux output (fMP4 + m3u8)
 *
 * Endpoints:
 * - GET /hls/:sessionId/playlist.m3u8 - HLS playlist
 * - GET /hls/:sessionId/stream.mp4 - Video stream with Range support
 *
 * @example
 * ```bash
 * # Get playlist
 * curl http://localhost:3000/hls/abc123/playlist.m3u8
 *
 * # Get stream with range
 * curl -H "Range: bytes=0-1000" http://localhost:3000/hls/abc123/stream.mp4
 * ```
 */
export const hlsModule = new Elysia({ prefix: "/hls" })
  .decorate("hlsService", new HLSService())
  .get(
    "/:sessionId/playlist.m3u8",
    async ({ hlsService, params, set }) => {
      const playlist = await hlsService.getPlaylist(params.sessionId);

      if (!playlist) {
        set.status = 404;
        return { error: "Not Found", message: "Playlist not found" };
      }

      set.headers["Content-Type"] = "application/vnd.apple.mpegurl";
      set.headers["Cache-Control"] = "no-cache";
      return playlist;
    },
    {
      params: t.Object({
        sessionId: t.String(),
      }),
      detail: {
        summary: "Get HLS playlist",
        description: "Retrieve the m3u8 playlist for a transmux session",
        tags: ["hls"],
      },
    }
  )
  .get(
    "/:sessionId/stream.mp4",
    async ({ hlsService, params, request, set }) => {
      const rangeHeader = request.headers.get("range");
      const result = await hlsService.getStream(params.sessionId, rangeHeader);

      set.status = result.status;
      for (const [key, value] of Object.entries(result.headers)) {
        set.headers[key] = value;
      }

      if (!result.body) {
        return { error: "Not Found", message: "Stream file not found" };
      }

      return result.body;
    },
    {
      params: t.Object({
        sessionId: t.String(),
      }),
      detail: {
        summary: "Get HLS stream",
        description: "Serve the fMP4 stream with HTTP Range support",
        tags: ["hls"],
      },
    }
  );
