import { Elysia, t } from "elysia";
import { hlsModels } from "./model";
import { HLSService } from "./service";

/**
 * HLS module - Serves transmux output (fMP4 + m3u8) with live BYTERANGE support
 *
 * Endpoints:
 * - GET /hls/:sessionId/playlist.m3u8 - Original HLS playlist from CLI output
 * - GET /hls/:sessionId/live.m3u8 - Dynamic BYTERANGE EVENT playlist (for HLS.js)
 * - GET /hls/:sessionId/info - Segment progress metadata (JSON)
 * - GET /hls/:sessionId/stream.mp4 - Video stream with Range support
 * - GET /hls/:sessionId/:filename - Any session file (init.mp4, seg_*.mp4)
 *
 * @example
 * ```bash
 * # Get live playlist (for HLS.js)
 * curl http://localhost:3000/hls/abc123/live.m3u8
 *
 * # Get segment info
 * curl http://localhost:3000/hls/abc123/info
 *
 * # Get stream with range
 * curl -H "Range: bytes=0-1000" http://localhost:3000/hls/abc123/stream.mp4
 * ```
 */
export const hlsModule = new Elysia({ prefix: "/hls" })
  .decorate("hlsService", new HLSService())
  .model(hlsModels)
  .get(
    "/:sessionId/live.m3u8",
    async ({ hlsService, params, set }) => {
      const playlist = await hlsService.getLivePlaylist(params.sessionId);

      if (!playlist) {
        set.status = 404;
        return { error: "Not Found", message: "Live playlist not ready" };
      }

      set.headers["Content-Type"] = "application/vnd.apple.mpegurl";
      set.headers["Cache-Control"] = "no-cache, no-store";
      set.headers["Access-Control-Allow-Origin"] = "*";
      return playlist;
    },
    {
      params: t.Object({
        sessionId: t.String(),
      }),
      detail: {
        summary: "Get live BYTERANGE HLS playlist",
        description:
          "Dynamic playlist generated from scanning stream.mp4 moof/mdat boundaries. " +
          "EVENT type — HLS.js reloads periodically to discover new segments.",
        tags: ["hls"],
      },
    }
  )
  .get(
    "/:sessionId/info",
    async ({ hlsService, params, set }) => {
      const info = await hlsService.getSegmentInfo(params.sessionId);

      if (!info) {
        set.status = 404;
        return {
          totalDuration: 0,
          availableDuration: 0,
          segmentCount: 0,
          totalSegments: 0,
          status: "not_found",
          initSegmentSize: 0,
          timescale: 0,
        };
      }

      return info;
    },
    {
      params: t.Object({
        sessionId: t.String(),
      }),
      response: {
        200: "SegmentInfo",
      },
      detail: {
        summary: "Get segment progress info",
        description:
          "Returns metadata about transmux progress: total/available duration, segment counts, status.",
        tags: ["hls"],
      },
    }
  )
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
  )
  .get(
    "/:sessionId/:filename",
    async ({ hlsService, params, request, set }) => {
      const rangeHeader = request.headers.get("range");
      const result = await hlsService.getSessionFile(
        params.sessionId,
        params.filename,
        rangeHeader
      );

      set.status = result.status;
      for (const [key, value] of Object.entries(result.headers)) {
        set.headers[key] = value;
      }

      if (!result.body) {
        return {
          error: result.status === 400 ? "Bad Request" : "Not Found",
          message: `File not found: ${params.filename}`,
        };
      }

      return result.body;
    },
    {
      params: t.Object({
        sessionId: t.String(),
        filename: t.String(),
      }),
      detail: {
        summary: "Get session file",
        description:
          "Serve any file from the session directory (init.mp4, seg_XXX.mp4, etc.)",
        tags: ["hls"],
      },
    }
  );
