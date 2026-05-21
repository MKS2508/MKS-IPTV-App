//
//  EventBus.swift
//  mksiptv-server
//
//  WebSocket event bus for broadcasting real-time events to connected clients.
//

import Vapor
import Foundation
import NIOWebSocket

// MARK: - WebSocket Client

/// Represents a connected WebSocket client with subscriptions
private struct WSClient {
    let id: UUID
    let socket: WebSocket
    var subscriptions: Set<EventChannel>
    let connectedAt: Date

    init(id: UUID = UUID(), socket: WebSocket, subscriptions: Set<EventChannel> = [], connectedAt: Date = Date()) {
        self.id = id
        self.socket = socket
        self.subscriptions = subscriptions
        self.connectedAt = connectedAt
    }
}

// MARK: - Event Bus Actor

/// Thread-safe event bus for managing WebSocket connections and broadcasting events
public actor EventBus {
    private var clients: [UUID: WSClient] = [:]
    private var channelSubscribers: [EventChannel: Set<UUID>] = [:]

    private let encoder: JSONEncoder
    private let pingInterval: TimeInterval
    private var pingTask: Task<Void, Never>?

    // Rate limiting
    private let maxEventsPerSecond: Int = 100
    private var eventTimestamps: [Date] = []

    public init(pingInterval: TimeInterval = 30.0) {
        self.pingInterval = pingInterval

        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]

        // Start ping task
        Task {
            await startPingTask()
        }
    }

    // MARK: - Client Management

    /// Register a new WebSocket client
    public func addClient(_ socket: WebSocket, id: UUID = UUID()) {
        let client = WSClient(id: id, socket: socket)
        clients[id] = client

        MKSLog.server.info("WebSocket client connected: \(id.uuidString)")

        // Send welcome message
        sendWelcome(to: client)
    }

    /// Remove a WebSocket client
    public func removeClient(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else {
            return
        }

        // Remove from all channel subscriptions
        for channel in client.subscriptions {
            channelSubscribers[channel]?.remove(id)
        }

        let duration = Date().timeIntervalSince(client.connectedAt)
        MKSLog.server.info("WebSocket client disconnected: \(id.uuidString) (duration: \(String(format: "%.2f", duration))s)")
    }

    /// Subscribe a client to a channel
    public func subscribe(clientId: UUID, to channel: EventChannel) {
        guard var client = clients[clientId] else {
            MKSLog.server.warning("Attempted to subscribe unknown client: \(clientId.uuidString)")
            return
        }

        client.subscriptions.insert(channel)
        clients[clientId] = client

        // Add to channel subscribers
        if channelSubscribers[channel] == nil {
            channelSubscribers[channel] = []
        }
        channelSubscribers[channel]?.insert(clientId)

        MKSLog.server.info("Client \(clientId.uuidString) subscribed to channel: \(channel.rawValue)")
    }

    /// Unsubscribe a client from a channel
    public func unsubscribe(clientId: UUID, from channel: EventChannel) {
        guard var client = clients[clientId] else {
            return
        }

        client.subscriptions.remove(channel)
        clients[clientId] = client

        // Remove from channel subscribers
        channelSubscribers[channel]?.remove(clientId)

        MKSLog.server.info("Client \(clientId.uuidString) unsubscribed from channel: \(channel.rawValue)")
    }

    // MARK: - Event Publishing

    /// Publish an event to all subscribers of a channel
    public func publish(channel: EventChannel, data: AnyCodable) {
        // Rate limiting check
        if !checkRateLimit() {
            MKSLog.server.warning("Rate limit exceeded for events, dropping message")
            return
        }

        let payload = EventPayload(channel: channel, data: data)
        let message = WSMessage(type: .event, channel: channel, payload: payload)

        guard let subscribers = channelSubscribers[channel], !subscribers.isEmpty else {
            MKSLog.server.debug("No subscribers for channel: \(channel.rawValue)")
            return
        }

        // Broadcast to all subscribers
        var sentCount = 0
        for clientId in subscribers {
            if let client = clients[clientId] {
                send(message: message, to: client)
                sentCount += 1
            }
        }

        MKSLog.server.debug("Broadcast event to \(sentCount) clients on channel: \(channel.rawValue)")
    }

    /// Send a message to a specific client
    private func send(message: WSMessage, to client: WSClient) {
        do {
            let data = try encoder.encode(message)
            let text = String(data: data, encoding: .utf8)!

            client.socket.send(text)
        } catch {
            MKSLog.server.error("Failed to encode WebSocket message: \(error.localizedDescription)")
        }
    }

    /// Send welcome message to newly connected client
    private func sendWelcome(to client: WSClient) {
        let welcome = WSMessage(
            type: .event,
            channel: nil,
            payload: EventPayload(
                channel: .profile,
                data: AnyCodable([
                    "message": "Connected to MKS IPTV Server",
                    "clientId": client.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ])
            )
        )

        send(message: welcome, to: client)
    }

    // MARK: - Rate Limiting

    /// Check if event rate is within limits
    private func checkRateLimit() -> Bool {
        let now = Date()
        let oneSecondAgo = now.addingTimeInterval(-1.0)

        // Clean old timestamps
        eventTimestamps.removeAll { $0 < oneSecondAgo }

        // Check rate limit
        if eventTimestamps.count >= maxEventsPerSecond {
            return false
        }

        eventTimestamps.append(now)
        return true
    }

    // MARK: - Heartbeat / Ping

    /// Start background ping task
    private func startPingTask() {
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))

                // Send ping to all connected clients
                await sendPingToAll()
            }
        }
    }

    /// Send ping to all connected clients
    private func sendPingToAll() {
        let ping = WSMessage(type: .ping, channel: nil, payload: nil)

        for client in clients.values {
            send(message: ping, to: client)
        }

        if !clients.isEmpty {
            MKSLog.server.debug("Sent ping to \(clients.count) clients")
        }
    }

    /// Stop the event bus and cleanup resources
    public func shutdown() {
        pingTask?.cancel()

        // Close all WebSocket connections
        for client in clients.values {
            client.socket.close(code: .goingAway)
        }

        clients.removeAll()
        channelSubscribers.removeAll()

        MKSLog.server.info("EventBus shutdown complete")
    }

    // MARK: - Statistics

    /// Get statistics about connected clients
    public func getStats() -> [String: Any] {
        var channelCounts: [String: Int] = [:]

        for (channel, subscribers) in channelSubscribers {
            channelCounts[channel.rawValue] = subscribers.count
        }

        return [
            "totalClients": clients.count,
            "channelSubscribers": channelCounts
        ]
    }
}
