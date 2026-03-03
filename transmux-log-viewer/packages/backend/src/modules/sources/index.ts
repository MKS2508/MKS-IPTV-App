import { Elysia } from "elysia";
import { SourcesService } from "./service";

/**
 * Sources module - Provides test data sources (IPTV URLs and local files)
 *
 * Endpoints:
 * - GET /sources - IPTV stream sources from data.json
 * - GET /sources/local - Local test files from /Volumes/KODAK1TB/
 *
 * @example
 * ```bash
 * # Get IPTV sources
 * curl http://localhost:3000/sources
 *
 * # Get local files
 * curl http://localhost:3000/sources/local
 * ```
 */
export const sourcesModule = new Elysia({ prefix: "/sources" })
  .decorate("sourcesService", new SourcesService())
  .get(
    "/",
    async ({ sourcesService }) => {
      return sourcesService.getIPTVSources();
    },
    {
      detail: {
        summary: "Get IPTV sources",
        description: "Retrieve IPTV stream sources from data.json",
        tags: ["sources"],
      },
    }
  )
  .get(
    "/local",
    ({ sourcesService }) => {
      return sourcesService.getLocalFiles();
    },
    {
      detail: {
        summary: "Get local files",
        description: "Retrieve local test files from /Volumes/KODAK1TB/",
        tags: ["sources"],
      },
    }
  );
