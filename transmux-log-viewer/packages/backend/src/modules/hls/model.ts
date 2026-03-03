import { t } from "elysia";

/**
 * Segment info response — metadata about HLS stream progress
 *
 * @property totalDuration - Total source duration in seconds (from CLI metadata)
 * @property availableDuration - Duration of content available in stream.mp4 so far
 * @property segmentCount - Number of fMP4 segments scanned so far
 * @property totalSegments - Estimated total segment count (totalDuration / avgSegDuration)
 * @property status - Session status: running, completed, failed, killed
 * @property initSegmentSize - Size of init segment (ftyp + moov) in bytes
 * @property timescale - Media timescale from moov (e.g. 90000)
 */
export interface ISegmentInfo {
  totalDuration: number;
  availableDuration: number;
  segmentCount: number;
  totalSegments: number;
  status: string;
  initSegmentSize: number;
  timescale: number;
}

/**
 * TypeBox models for HLS module validation
 */
export const hlsModels = {
  SegmentInfo: t.Object({
    totalDuration: t.Number({ description: "Total source duration in seconds" }),
    availableDuration: t.Number({ description: "Duration of available content in seconds" }),
    segmentCount: t.Number({ description: "Number of scanned fMP4 segments" }),
    totalSegments: t.Number({ description: "Estimated total segment count" }),
    status: t.String({ description: "Session status" }),
    initSegmentSize: t.Number({ description: "Init segment size in bytes" }),
    timescale: t.Number({ description: "Media timescale (e.g. 90000)" }),
  }),
};
