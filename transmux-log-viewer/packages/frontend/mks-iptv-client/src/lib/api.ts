import type { App } from "@backend/index";
import { treaty } from "@elysiajs/eden";

/**
 * Eden Treaty client for type-safe API communication
 *
 * Provides end-to-end type safety between frontend and backend.
 * All routes are auto-completed and typed based on the Elysia server.
 *
 * @example
 * ```typescript
 * // GET /logs/history
 * const { data, error } = await api.logs.history.get()
 *
 * // POST /logs/clear
 * const result = await api.logs.clear.post()
 *
 * // GET /logs/stream (SSE)
 * const stream = await api.logs.stream.get()
 * for await (const chunk of stream.data) {
 *   console.log(chunk)
 * }
 * ```
 */
export const api = treaty<App>("http://localhost:3000");

/**
 * API response helper for handling Eden responses
 *
 * @param response - Eden response object with data/error
 * @returns Result tuple [data, error]
 */
export async function unwrap<T, E>(response: {
  data: T | null;
  error: { value: E; status: number } | null;
}): Promise<[T, null] | [null, E]> {
  if (response.error) {
    return [null, response.error.value as E];
  }
  return [response.data as T, null];
}
