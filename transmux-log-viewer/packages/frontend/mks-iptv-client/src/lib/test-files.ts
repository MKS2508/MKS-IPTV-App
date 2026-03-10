import type { ILocalFileSource } from "@/types";

/**
 * Local test files available on /Volumes/KODAK1TB/
 *
 * These are real video files for testing the TransmuxCore CLI.
 *
 * ⚠️ PRIMARY TEST FILE: Crímenes Bellvitge (2026) 1x03.mkv
 *    - Only MKV file available (best for testing MKV → fMP4 transmux)
 *    - AC3 audio (tests init phase fix)
 *    - 1.6GB size
 */
export const LOCAL_TEST_FILES: ILocalFileSource[] = [
  // ═══════════════════════════════════════════════════════════════
  // PRIMARY TEST FILE (MKV) - Use this for all transmux testing
  // ═══════════════════════════════════════════════════════════════
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x03.mkv",
    name: "Crímenes Bellvitge (2026) 1x03.mkv",
    size: 1717986918, // 1.6GB
    extension: "mkv",
  },

  // ═══════════════════════════════════════════════════════════════
  // MP4 FILES (already in MP4 container, less interesting for transmux)
  // ═══════════════════════════════════════════════════════════════
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x01.mp4",
    name: "Crímenes Bellvitge (2026) 1x01.mp4",
    size: 1610612736, // 1.5GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x02.mp4",
    name: "Crímenes Bellvitge (2026) 1x02.mp4",
    size: 1825361100, // 1.7GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x03.mp4",
    name: "Crímenes Bellvitge (2026) 1x03.mp4",
    size: 1717986918, // 1.6GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crimen Por Encargo S01E01.mp4",
    name: "Crimen Por Encargo S01E01.mp4",
    size: 2576980377, // 2.4GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/FBI 1080P S63E04.mp4",
    name: "FBI 1080P S63E04.mp4",
    size: 1503238553, // 1.4GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Muerte en el hotel.mp4",
    name: "Muerte en el hotel.mp4",
    size: 2469606195, // 2.3GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Pluribus (2025) 1080p S01E05.mp4",
    name: "Pluribus (2025) 1080p S01E05.mp4",
    size: 3650722201, // 3.4GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/The Real CSI Miami (2025) 1080p S01E01.mp4",
    name: "The Real CSI: Miami (2025) 1080p S01E01.mp4",
    size: 2254857830, // 2.1GB
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Ya no quedan junglas.mp4",
    name: "Ya no quedan junglas.mp4",
    size: 3972844748, // 3.7GB
    extension: "mp4",
  },

  // ═══════════════════════════════════════════════════════════════
  // M4V FILES (iTunes format)
  // ═══════════════════════════════════════════════════════════════
  {
    path: "/Volumes/KODAK1TB/Pluribus (2025) 1080p S01E01.m4v",
    name: "Pluribus (2025) 1080p S01E01.m4v",
    size: 5046586572, // 4.7GB
    extension: "m4v",
  },
];

/**
 * Primary MKV test file (recommended for all testing)
 *
 * This is the ONLY MKV file available and the best candidate for
 * testing MKV → fMP4 transmux with AC3 audio handling.
 */
export const PRIMARY_MKV_TEST_FILE = LOCAL_TEST_FILES[0];

/**
 * Path to TransmuxCore CLI
 */
export const TRANSMUX_CLI_PATH =
  "/Users/mks/Documents/MKS-IPTV-App/TransmuxCore/.build/debug/transmux-cli";

/**
 * Log file path (watched by backend)
 */
export const LOG_FILE_PATH = "/tmp/mks-iptv-transmux.log";

/**
 * Default CLI options for testing
 */
export const DEFAULT_CLI_OPTIONS = {
  seek: 0,
  duration: 10,
  verbose: true,
};
