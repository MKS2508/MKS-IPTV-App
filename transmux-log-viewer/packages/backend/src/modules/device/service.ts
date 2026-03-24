import logger from "@mks2508/better-logger";

const deviceLog = logger.component("DeviceService");

/**
 * Represents a connected iOS/macOS device session.
 */
export interface IDeviceSession {
  /** WebSocket instance for this device */
  ws: any;
  /** Device name from handshake (e.g., "iPhone 16 Pro") */
  deviceName: string;
  /** App version from handshake */
  appVersion: string;
  /** OS version from handshake */
  systemVersion: string;
  /** Current player state */
  playerState: string;
  /** When the device connected */
  connectedAt: Date;
}

/**
 * Log entry received from an iOS device via WebSocket.
 * Matches the JSON format sent by RemoteLogTransport.swift.
 */
export interface IDeviceLogEntry {
  type: "log";
  timestamp: string;
  level: string;
  category: string;
  tag: string;
  message: string;
  fields?: Record<string, string>;
  sessionId?: string;
}

/**
 * Handshake message sent by the iOS device on WS connect.
 */
export interface IDeviceHandshake {
  type: "handshake";
  deviceName: string;
  appVersion: string;
  systemVersion: string;
  playerState: string;
}

/**
 * Command message sent from the viewer to the iOS device.
 */
export interface IRemoteCommand {
  type: "command";
  command: string;
  payload?: Record<string, string>;
}

/**
 * Manages connected iOS devices and bridges their logs to the SSE stream.
 *
 * Architecture:
 * - iOS device connects via WebSocket to /ws/device
 * - Device sends handshake with device info
 * - Device streams log entries as JSON
 * - DeviceService buffers entries for SSE consumers
 * - Frontend sends commands via POST /device/command → relayed to device WS
 */
export class DeviceService {
  /** Currently connected device sessions (keyed by a generated ID) */
  private sessions = new Map<string, IDeviceSession>();

  /** Buffered log entries from devices, consumed by SSE stream */
  private logBuffer: IDeviceLogEntry[] = [];

  /** Max buffer size before oldest entries are dropped */
  private readonly maxBuffer = 5000;

  /** Listeners waiting for new log entries (SSE generators) */
  private listeners: Array<(entry: IDeviceLogEntry) => void> = [];

  /** Counter for generating session IDs */
  private sessionCounter = 0;

  // MARK: - Device Connection

  /**
   * Register a new device WebSocket connection.
   * @returns Session ID for this connection.
   */
  registerDevice(ws: any): string {
    const sessionId = `device-${++this.sessionCounter}`;
    const session: IDeviceSession = {
      ws,
      deviceName: "Unknown Device",
      appVersion: "0.0",
      systemVersion: "unknown",
      playerState: "idle",
      connectedAt: new Date(),
    };
    this.sessions.set(sessionId, session);
    deviceLog.info(`Device connected: ${sessionId}`);
    return sessionId;
  }

  /**
   * Remove a device session on disconnect.
   */
  removeDevice(sessionId: string): void {
    this.sessions.delete(sessionId);
    deviceLog.info(`Device disconnected: ${sessionId}`);
  }

  /**
   * Process an incoming message from a device.
   */
  handleMessage(sessionId: string, raw: string): void {
    try {
      const data = JSON.parse(raw);

      if (data.type === "handshake") {
        this.handleHandshake(sessionId, data as IDeviceHandshake);
      } else if (data.type === "log") {
        this.handleLogEntry(data as IDeviceLogEntry);
      }
    } catch (err) {
      deviceLog.warn(`Failed to parse device message: ${raw.slice(0, 200)}`);
    }
  }

  // MARK: - Log Streaming (for SSE bridge)

  /**
   * Async generator that yields device log entries as they arrive.
   * Used by the SSE /logs/stream endpoint to merge device logs.
   */
  async *streamDeviceLogs(signal?: AbortSignal): AsyncGenerator<IDeviceLogEntry, void, unknown> {
    // Yield any buffered entries first
    for (const entry of this.logBuffer) {
      if (signal?.aborted) return;
      yield entry;
    }

    // Then yield new entries as they arrive
    while (!signal?.aborted) {
      const entry = await this.waitForEntry(signal);
      if (entry) yield entry;
    }
  }

  /**
   * Get all connected device sessions.
   */
  getConnectedDevices(): Array<{
    sessionId: string;
    deviceName: string;
    appVersion: string;
    systemVersion: string;
    playerState: string;
    connectedAt: string;
  }> {
    return Array.from(this.sessions.entries()).map(([id, s]) => ({
      sessionId: id,
      deviceName: s.deviceName,
      appVersion: s.appVersion,
      systemVersion: s.systemVersion,
      playerState: s.playerState,
      connectedAt: s.connectedAt.toISOString(),
    }));
  }

  /**
   * Send a command to a connected device.
   * If no sessionId specified, sends to the first (most common: single device).
   */
  sendCommand(command: IRemoteCommand, sessionId?: string): boolean {
    const target = sessionId
      ? this.sessions.get(sessionId)
      : this.sessions.values().next().value;

    if (!target) {
      deviceLog.warn(`No device connected to send command: ${command.command}`);
      return false;
    }

    try {
      target.ws.send(JSON.stringify(command));
      deviceLog.info(`Command sent: ${command.command}`);
      return true;
    } catch (err) {
      deviceLog.error(`Failed to send command: ${err}`);
      return false;
    }
  }

  /** Whether any device is currently connected */
  get hasConnectedDevice(): boolean {
    return this.sessions.size > 0;
  }

  /** Number of buffered log entries */
  get bufferSize(): number {
    return this.logBuffer.length;
  }

  // MARK: - Private

  private handleHandshake(sessionId: string, handshake: IDeviceHandshake): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.deviceName = handshake.deviceName;
    session.appVersion = handshake.appVersion;
    session.systemVersion = handshake.systemVersion;
    session.playerState = handshake.playerState;

    deviceLog.info(
      `Device identified: ${handshake.deviceName} (${handshake.systemVersion}, v${handshake.appVersion})`
    );
  }

  private handleLogEntry(entry: IDeviceLogEntry): void {
    // Buffer for late SSE consumers
    this.logBuffer.push(entry);
    if (this.logBuffer.length > this.maxBuffer) {
      this.logBuffer.splice(0, this.logBuffer.length - this.maxBuffer);
    }

    // Notify all waiting listeners
    for (const listener of this.listeners) {
      listener(entry);
    }
    this.listeners = [];
  }

  private waitForEntry(signal?: AbortSignal): Promise<IDeviceLogEntry | null> {
    return new Promise((resolve) => {
      if (signal?.aborted) {
        resolve(null);
        return;
      }

      const onAbort = () => {
        resolve(null);
      };
      signal?.addEventListener("abort", onAbort, { once: true });

      this.listeners.push((entry) => {
        signal?.removeEventListener("abort", onAbort);
        resolve(entry);
      });
    });
  }
}
