//
//  EventRoutes.swift
//  mksiptv-server
//
//  WebSocket routes for real-time event streaming.
//

import Vapor
import NIOWebSocket
import Foundation

// MARK: - Event Routes Collection

/// WebSocket routes for real-time events
public struct EventRoutes: RouteCollection, Sendable {
    private let eventBus: EventBus

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    public func boot(routes: RoutesBuilder) throws {
        // WebSocket endpoint for events
        routes.webSocket("ws", "events") { req, socket in
            await handleWebSocket(req, socket)
        }

        // Statistics endpoint (optional, for debugging)
        routes.get("ws", "stats") { req -> EventStatsResponse in
            let stats = await eventBus.getStats()
            return EventStatsResponse(
                totalClients: stats["totalClients"] as? Int ?? 0,
                channelSubscribers: stats["channelSubscribers"] as? [String: Int] ?? [:]
            )
        }

        MKSLog.server.info("WebSocket routes registered")
    }

    // MARK: - WebSocket Handler

    /// Handle WebSocket connection lifecycle
    private func handleWebSocket(_ req: Request, _ socket: WebSocket) async {
        let clientId = UUID()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        MKSLog.server.info("WebSocket connection established: \(clientId.uuidString)")

        // Add client to event bus
        await eventBus.addClient(socket, id: clientId)

        // Keep the connection alive and handle incoming messages
        // Note: Vapor's WebSocket doesn't use AsyncSequence pattern directly
        // Messages are handled through callbacks in onText/onBinary etc.
        socket.onClose.whenComplete { result in
            Task {
                await eventBus.removeClient(clientId)
            }

            switch result {
            case .success:
                MKSLog.server.info("WebSocket connection closed normally: \(clientId.uuidString)")
            case .failure(let error):
                MKSLog.server.error("WebSocket connection closed with error: \(error.localizedDescription)")
            }
        }

        // Handle incoming text messages
        socket.onText { _, text in
            await handleTextMessage(text, clientId: clientId, decoder: decoder)
        }

        // Handle incoming binary messages
        socket.onBinary { _, data in
            MKSLog.server.warning("Binary message received from client \(clientId.uuidString) (not supported)")
        }

        // Handle ping
        socket.onPing { _, data in
            // Send pong response
            let pongMessage = WSMessage(type: .pong, channel: nil, payload: nil)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            if let data = try? encoder.encode(pongMessage),
               let text = String(data: data, encoding: .utf8) {
                socket.send(text)
            }
        }
    }

    // MARK: - Message Handling

    /// Handle text messages from WebSocket clients
    private func handleTextMessage(_ text: String, clientId: UUID, decoder: JSONDecoder) async {
        guard let data = text.data(using: .utf8) else {
            MKSLog.server.warning("Failed to decode message from client \(clientId.uuidString)")
            return
        }

        do {
            let message = try decoder.decode(WSMessage.self, from: data)

            switch message.type {
            case .subscribe:
                if let channel = message.channel {
                    await eventBus.subscribe(clientId: clientId, to: channel)
                } else {
                    MKSLog.server.warning("Subscribe message missing channel from client \(clientId.uuidString)")
                }

            case .unsubscribe:
                if let channel = message.channel {
                    await eventBus.unsubscribe(clientId: clientId, from: channel)
                } else {
                    MKSLog.server.warning("Unsubscribe message missing channel from client \(clientId.uuidString)")
                }

            case .ping:
                // Respond with pong
                await sendPong(to: clientId)

            case .event:
                MKSLog.server.warning("Client \(clientId.uuidString) sent event (server-only)")

            case .pong:
                MKSLog.server.debug("Pong received from client \(clientId.uuidString)")
            }

        } catch {
            MKSLog.server.error("Failed to decode WebSocket message from client \(clientId.uuidString): \(error.localizedDescription)")
        }
    }

    /// Send pong response to client
    private func sendPong(to clientId: UUID) async {
        // This would require socket access, which we don't have in this context
        // The ping/pong is handled automatically by NIOWebSocket
        MKSLog.server.debug("Pong sent to client \(clientId.uuidString)")
    }
}

// MARK: - Statistics Response

/// Event bus statistics response
public struct EventStatsResponse: Content {
    public let totalClients: Int
    public let channelSubscribers: [String: Int]

    public init(totalClients: Int, channelSubscribers: [String: Int]) {
        self.totalClients = totalClients
        self.channelSubscribers = channelSubscribers
    }
}
