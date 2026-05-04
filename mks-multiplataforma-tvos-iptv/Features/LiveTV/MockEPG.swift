//
//  MockEPG.swift
//  mks-multiplataforma-tvos-iptv
//
//  Deterministic mock EPG schedule per channel.
//  Generates a stable sequence of programmes (past / now / upcoming)
//  hashed off the channel's stream id, so card-to-detail looks consistent.
//

import Foundation
import IPTVCore

struct MockProgramme: Identifiable, Equatable {
    let id: UUID = UUID()
    let title: String
    let start: Date
    let end: Date

    var isLive: Bool {
        let now = Date()
        return now >= start && now < end
    }

    var progress: Double {
        let now = Date()
        guard now >= start, now < end else {
            return now < start ? 0 : 1
        }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return now.timeIntervalSince(start) / total
    }
}

enum MockEPG {
    private static let titlePool: [String] = [
        "Morning News",
        "Talk of the Town",
        "Highlights of the Week",
        "Sports Roundup",
        "Documentary: Nature's Edge",
        "Headlines Live",
        "Featured Movie: Midnight Run",
        "Late Night Show",
        "Match of the Day",
        "Weather Report",
        "Cooking with Friends",
        "World Affairs",
        "Tech Today",
        "Music Hour",
        "Drama Special",
        "Live Concert"
    ]

    /// Generate 8 programmes around now: 2 past, 1 current, 5 upcoming.
    static func schedule(for channel: LiveChannel) -> [MockProgramme] {
        let seed = abs(channel.streamId)
        var rng = SeededRNG(seed: UInt64(seed))

        let now = Date()
        let block: TimeInterval = 30 * 60

        var schedule: [MockProgramme] = []
        var cursor = now.addingTimeInterval(-2 * block)

        for _ in 0..<8 {
            let durationBlocks = Double(rng.next(in: 1...3)) // 30, 60 or 90 min
            let duration = durationBlocks * block
            let title = titlePool[Int(rng.next(in: 0...UInt64(titlePool.count - 1)))]
            schedule.append(MockProgramme(
                title: title,
                start: cursor,
                end: cursor.addingTimeInterval(duration)
            ))
            cursor = cursor.addingTimeInterval(duration)
        }

        return schedule
    }

    static func currentProgramme(for channel: LiveChannel) -> MockProgramme? {
        schedule(for: channel).first(where: \.isLive)
    }
}

// MARK: - Stable RNG so each channel gets a consistent schedule

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed != 0 ? seed : 0xdead_beef_cafe
    }

    mutating func next(in range: ClosedRange<UInt64>) -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + (state % span)
    }
}
