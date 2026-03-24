import { Elysia, sse, t } from "elysia";
import { DeviceService } from "./service";

/**
 * Device module — WebSocket endpoint for iOS/macOS remote debugging.
 *
 * Endpoints:
 * - WS  /ws/device          — iOS device connects here, sends logs, receives commands
 * - GET /device/stream       — SSE stream of device logs (for frontend consumption)
 * - GET /device/sessions     — List connected devices
 * - POST /device/command     — Send command to connected device
 *
 * @example
 * ```typescript
 * // From iOS (Swift URLSessionWebSocketTask):
 * ws.send('{"type":"handshake","deviceName":"iPhone","appVersion":"2.0","systemVersion":"iOS 26","playerState":"idle"}')
 * ws.send('{"type":"log","timestamp":"...","level":"info","category":"player","tag":"AVPlayer","message":"LOAD ..."}')
 *
 * // From frontend (send command):
 * POST /device/command { "type": "command", "command": "pause" }
 * ```
 */
export const deviceModule = new Elysia()
  .decorate("deviceService", new DeviceService())

  // MARK: - WebSocket endpoint for iOS devices
  .ws("/ws/device", {
    open(ws) {
      const service = (ws as any).data?.deviceService as DeviceService | undefined;
      if (!service) return;
      const sessionId = service.registerDevice(ws);
      // Store sessionId on the ws object for close/message handlers
      (ws as any)._deviceSessionId = sessionId;
    },
    message(ws, message) {
      const service = (ws as any).data?.deviceService as DeviceService | undefined;
      const sessionId = (ws as any)._deviceSessionId as string | undefined;
      if (!service || !sessionId) return;

      const raw = typeof message === "string" ? message : JSON.stringify(message);
      service.handleMessage(sessionId, raw);
    },
    close(ws) {
      const service = (ws as any).data?.deviceService as DeviceService | undefined;
      const sessionId = (ws as any)._deviceSessionId as string | undefined;
      if (!service || !sessionId) return;
      service.removeDevice(sessionId);
    },
  })

  // MARK: - SSE stream of device logs (for frontend LogViewer)
  .get(
    "/device/stream",
    async function* ({ deviceService, request }) {
      const signal = request.signal;

      yield sse({
        data: {
          type: "connected",
          message: "Connected to device log stream",
          source: "device",
          timestamp: new Date().toISOString(),
        },
      });

      for await (const entry of deviceService.streamDeviceLogs(signal)) {
        if (signal.aborted) return;
        yield sse({
          data: {
            ...entry,
            source: "device", // Tag so frontend knows this is from a device
          },
        });
      }
    },
    {
      detail: {
        summary: "Stream device logs via SSE",
        description: "Server-Sent Events stream of logs from connected iOS/macOS devices",
        tags: ["device"],
      },
    }
  )

  // MARK: - List connected devices
  .get(
    "/device/sessions",
    ({ deviceService }) => {
      return {
        devices: deviceService.getConnectedDevices(),
        count: deviceService.getConnectedDevices().length,
      };
    },
    {
      detail: {
        summary: "List connected devices",
        description: "Returns all currently connected iOS/macOS devices",
        tags: ["device"],
      },
    }
  )

  // MARK: - Send command to device
  .post(
    "/device/command",
    ({ deviceService, body }) => {
      const success = deviceService.sendCommand(
        {
          type: "command",
          command: body.command,
          payload: body.payload,
        },
        body.sessionId
      );

      return {
        success,
        message: success ? `Command '${body.command}' sent` : "No device connected",
      };
    },
    {
      body: t.Object({
        command: t.String(),
        payload: t.Optional(t.Record(t.String(), t.String())),
        sessionId: t.Optional(t.String()),
      }),
      detail: {
        summary: "Send command to device",
        description:
          "Send a remote command (play/pause/seek/etc.) to a connected iOS device",
        tags: ["device"],
      },
    }
  );
