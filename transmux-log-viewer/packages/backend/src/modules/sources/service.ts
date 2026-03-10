import { readFile } from "node:fs/promises";
import logger from "@mks2508/better-logger";

const sourcesLog = logger.component("SourcesService");

/**
 * IPTV stream source from data.json
 */
interface IStreamSource {
  category: string;
  containerExtension: string;
  id: string;
  name: string;
  streamId: number;
  type: string;
  url: string;
}

/**
 * Local file source for testing
 */
interface ILocalFileSource {
  path: string;
  name: string;
  size: number;
  extension: string;
}

/**
 * Path to the root data.json with IPTV sources
 */
const DATA_JSON_PATH = new URL("../../../../../data.json", import.meta.url).pathname;

/**
 * Local test files available on /Volumes/KODAK1TB/
 */
const LOCAL_TEST_FILES: ILocalFileSource[] = [
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x03.mkv",
    name: "Crímenes Bellvitge (2026) 1x03.mkv",
    size: 1717986918,
    extension: "mkv",
  },
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x01.mp4",
    name: "Crímenes Bellvitge (2026) 1x01.mp4",
    size: 1610612736,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x02.mp4",
    name: "Crímenes Bellvitge (2026) 1x02.mp4",
    size: 1825361100,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crímenes Bellvitge (2026) 1x03.mp4",
    name: "Crímenes Bellvitge (2026) 1x03.mp4",
    size: 1717986918,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Crimen Por Encargo S01E01.mp4",
    name: "Crimen Por Encargo S01E01.mp4",
    size: 2576980377,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/FBI 1080P S63E04.mp4",
    name: "FBI 1080P S63E04.mp4",
    size: 1503238553,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Muerte en el hotel.mp4",
    name: "Muerte en el hotel.mp4",
    size: 2469606195,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Pluribus (2025) 1080p S01E05.mp4",
    name: "Pluribus (2025) 1080p S01E05.mp4",
    size: 3650722201,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/The Real CSI Miami (2025) 1080p S01E01.mp4",
    name: "The Real CSI: Miami (2025) 1080p S01E01.mp4",
    size: 2254857830,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Ya no quedan junglas.mp4",
    name: "Ya no quedan junglas.mp4",
    size: 3972844748,
    extension: "mp4",
  },
  {
    path: "/Volumes/KODAK1TB/Pluribus (2025) 1080p S01E01.m4v",
    name: "Pluribus (2025) 1080p S01E01.m4v",
    size: 5046586572,
    extension: "m4v",
  },
];

/**
 * Service for managing test data sources (IPTV URLs and local files)
 *
 * Provides access to IPTV stream sources from data.json and
 * local test files from /Volumes/KODAK1TB/.
 *
 * @example
 * ```typescript
 * const service = new SourcesService();
 * const iptv = await service.getIPTVSources();
 * const local = service.getLocalFiles();
 * ```
 */
export class SourcesService {
  private cachedSources: IStreamSource[] | null = null;

  /**
   * Get IPTV stream sources from data.json
   *
   * Reads and parses the data.json file. Results are cached after first read.
   *
   * @returns Array of IPTV stream sources
   */
  async getIPTVSources(): Promise<{ sources: IStreamSource[]; count: number }> {
    if (this.cachedSources) {
      return { sources: this.cachedSources, count: this.cachedSources.length };
    }

    try {
      const raw = await readFile(DATA_JSON_PATH, "utf-8");
      const parsed = JSON.parse(raw) as IStreamSource[];
      this.cachedSources = parsed;

      sourcesLog.info(`Loaded ${parsed.length} IPTV sources from data.json`);
      return { sources: parsed, count: parsed.length };
    } catch (error) {
      sourcesLog.error(
        `Failed to read data.json: ${error instanceof Error ? error.message : String(error)}`
      );
      return { sources: [], count: 0 };
    }
  }

  /**
   * Get local test files from /Volumes/KODAK1TB/
   *
   * Returns the hardcoded list of local test files.
   *
   * @returns Array of local file sources
   */
  getLocalFiles(): { files: ILocalFileSource[]; count: number } {
    return { files: LOCAL_TEST_FILES, count: LOCAL_TEST_FILES.length };
  }
}
