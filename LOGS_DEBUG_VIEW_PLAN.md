# Plan: Log Viewer para Debug Tab

## Overview

Crear una nueva vista `LogsDebugView` en la sección de Debug del permita visualizar los de tiempo real los los los logs de la aplicación en tiempo real:
 con colores, badges, deduplication, and y copy functionality.

---

## Files to Create

### 1. `LogsDebugView.swift`
**Location:** `mks-multiplatform-iptv/IPTVDownloader/Features/Debug/Views/LogsDebugView.swift`

### 2. `LogEntryModel.swift`
**Location:** `mks-multiplatform-iptv/IPTVDownloader/Features/Debug/ViewModels/LogEntryModel.swift`

### 3. `LogParser.swift`
**Location:** `mks-multiplatform-iptv/IPTVDownloader/Features/Debug/Utils/LogParser.swift`

### 4. `LogDeduplicator.swift`
**Location:** `mks-multiplatform-iptv/IPTVDownloader/Features/Debug/Utils/LogDeduplicator.swift`

### 5. Update `NavigationDestination` enum
**Location:** `mks-multiplatform-iptv/IPTVDownloader/Core/Layout/PlatformNavigationView.swift`

---

## Log File Sources

| Source | Path | Content |
|-------|------|---------|
| TransmuxCore | `$TMPDIR/mks-iptv-transmux.log` | Transmuxing, seeking, segments |
| PlayerLog | `$TMPDIR/mks-iptv-player.log` | AVPlayer events, glitches, buffering |
| CastLog | `$TMPDIR/mks-iptv-cast.log` | Chromecast protocol |

## UI Structure

```
┌── LogsDebugView ──────────────────────────────────────────────────────┐
│                                        │                                            │
│  ┌── SourcePicker (TabView)          ┌── LogContent (ScrollView)              │
│  │   [Transmux] [Player] [Cast]     │   ├── ParsedEntries ─── DedupedGroups ───│
│                                        │                                            │
│                                        ▼────────────────────────────────────────┘
│                                                                                   │
│  ┌── LogEntryRow ─── LogEntryRow ─── LogEntryRow ─── ...                 │
│      (with badges, colors, copy button)                                           │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Data Models

### LogEntry
```swift
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel        // INF, WRN, ERR, DBG
    let category: String      // lifecycle, buffer, timing, etc.
    let tag: String           // Server, Remux, Segmenter, etc.
    let action: String         // LOAD, SEEK_COMPLETE, SERVE, etc.
    let fields: [String: Any]  // Parsed key-value pairs
    let rawLine: String       // Original log line for copy
    let source: LogSource      // transmux, player, cast
}

enum LogLevel: String {
    case debug = "DBG"
    case info = "INF"
    case warning = "WRN"
    case error = "ERR"
    case critical = "CRI"
}

enum LogSource: String {
    case transmux = "TransmuxCore"
    case player = "PlayerLog"
    case cast = "CastLog"
}
```

### DeduplicationResult
```swift
struct DeduplicationResult {
    let entries: [LogEntry]
    let collapsedGroups: [CollapsedLogGroup]  // Groups of similar entries
    let stats: DeduplicationStats
}

struct CollapsedLogGroup: Identifiable {
    let id: UUID
    let pattern: String        // "SERVE seg_XXX..YYY"
    let count: Int             // Number of occurrences
    let firstTimestamp: Date
    let lastTimestamp: Date
    let sampleEntry: LogEntry  // One representative entry
    let level: LogLevel
}

struct DeduplicationStats {
    let totalEntries: Int
    let uniqueEntries: Int
    let collapsedCount: Int
    let collapseRatio: Double  // % of entries collapsed
}
```

## Log Parsing Strategy

### TransmuxLog Format
```
[HH:mm:ss.SSS] [LEVEL] [TAG] MESSAGE
Example: [14:32:15.123] [INF] [Server] SERVE seg_004..0.1f-2.5s 9/9 immediate avg=142KB buf=2.5s
```

### PlayerLog / CastLog Format
```
[ISO8601] [LEVEL] [CATEGORY] ACTION session=SESSION_ID KEY1=VAL1 KEY2=VAL2
Example: [2025-03-16T14:32:15.123Z] [INF] [lifecycle] LOAD session=abc123 player=AVPlayer url=***
```

### Parsing Steps
1. Extract timestamp with regex
2. Extract level with regex
3. Extract tag/category with regex
4. Extract action (first word after category)
5. Parse key=value pairs from remainder
6. Create LogEntry with all fields

## Deduplication Strategy

### Pattern Detection
- **SERVE segments**: Collapse consecutive `SERVE seg_XXX` entries into `SERVE seg_004..0.2.5s (9/9 immediate avg=142KB)`
- **Heartbeats**: Collapse consecutive `HEARTBEAT PING/PONG` into `HEARTBEAT x5`
- **Buffer events**: Group similar buffer underrun/stall events

### Algorithm
```swift
func deduplicate(entries: [LogEntry]) -> DeduplicationResult {
    var result: [LogEntry] = []
    var groups: [CollapsedLogGroup] = []
    var currentGroup: CollapsedLogGroup?
    
    for entry in entries {
        if let pattern = detectPattern(entry) {
            if currentGroup?.pattern == pattern {
                // Extend existing group
                currentGroup.count += 1
                currentGroup.lastTimestamp = entry.timestamp
            } else {
                // Save previous group, start new
                if let g = currentGroup { groups.append(g) }
                currentGroup = CollapsedLogGroup(
                    pattern: pattern,
                    count: 1,
                    firstTimestamp: entry.timestamp,
                    lastTimestamp: entry.timestamp,
                    sampleEntry: entry,
                    level: entry.level
                )
            }
        } else {
            // Non-duplicable entry - save group if exists, add entry
            if let g = currentGroup {
                groups.append(g)
                currentGroup = nil
            }
            result.append(entry)
        }
    }
    
    // Finalize
    if let g = currentGroup { groups.append(g) }
    
    return DeduplicationResult(
        entries: result,
        collapsedGroups: groups,
        stats: DeduplicationStats(...)
    )
}
```

## UI Components

### 1. SourcePicker
```swift
struct SourcePicker: View {
    @Binding var selectedSource: LogSource?
    
    var body: some View {
        HStack(spacing: 4) {
        ForEach([LogSource.transmux, .player, .cast], id: \.self) { source in
            SourceBadge(source: source, isSelected: selectedSource == source)
                .onTapGesture { selectedSource = source }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}

```

### 2. LevelFilter
```swift
struct LevelFilter: View {
    @Binding var selectedLevels: Set<LogLevel>
    
    var body: some View {
        HStack(spacing: 4) {
        ForEach([.debug, .info, .warning, .error, .critical], id: \.self) { level in
            LevelBadge(level: level, isSelected: selectedLevels.contains(level))
                .onTapGesture { toggleLevel(level) }
        }
    }
}
```

### 3. LogEntryRow
```swift
struct LogEntryRow: View {
    let entry: LogEntry
    let onCopy: () -> Void
    
    var body: some View {
        HStack(alignment: .leading, spacing: 8) {
            // Timestamp
            Text(entry.timestamp.formatted("HH:mm:ss.SSS"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level Badge
            LevelBadge(level: entry.level)
            
            // Tag Badge
            TagBadge(tag: entry.tag)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action)
                    .font(.caption.weight(.semibold))
                
                if !entry.fields.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(entry.fields.sortedKeys, id: \.self) { key in
                            FieldBadge(key: key, value: entry.fields[key]!)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Copy button
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rowBackground)
    }
}
```

### 4. CollapsedLogGroupRow
```swift
struct CollapsedLogGroupRow: View {
    let group: CollapsedLogGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(group.entries) { entry in
                LogEntryRow(entry: entry)
            }
        } label: {
            HStack {
                LevelBadge(level: group.level)
                Text("\(group.pattern) ×\(group.count)")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(formatDuration(group.firstTimestamp, group.lastTimestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### 5. Badge Components
```swift
struct LevelBadge: View {
    let level: LogLevel
    var isSelected: Bool = true
    
    var body: some View {
        Text(level.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? .white : level.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? level.color : level.color.opacity(0.2))
            .cornerRadius(4)
    }
}

struct TagBadge: View {
    let tag: String
    
    var body: some View {
        Text(tag)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
    }
}

struct FieldBadge: View {
    let key: String
    let value: Any
    
    var body: some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.caption2.weight(.medium))
            Text("=")
                .font(.caption2)
            Text(String(describing: value))
                .font(.caption2.monospaced())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(3)
    }
}
```

### 6. Color Scheme
```swift
extension LogLevel {
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return Color(red: 0.8, green: 0.1, blue: 0.1)
        }
    }
}
```

## Features

### Real-time Monitoring
- Timer-based file polling (1 second interval)
- File size monitoring
- Live line count

### Search & Filter
- Text search across all entries
- Filter by source (tabs)
- Filter by level (badges)
- Filter by category/tag

### Copy Functionality
- Copy single entry
- Copy all filtered entries
- Copy collapsed group

### Export
- Export to file
- Export filtered results

## Integration

### NavigationDestination Update
```swift
enum NavigationDestination: String, CaseIterable {
    // ... existing cases ...
    
    #if DEBUG
    case debugStream
    case cacheDebug
    case logsDebug    // NEW: Logs viewer
    #endif
}
```

### ContentView Integration
```swift
case .logsDebug:
    LogsDebugView()
        .navigationTitle("Logs Inspector")
```

## Performance Considerations

1. **Lazy Loading**: Only parse visible entries
2. **Debouncing**: Debounce search/filter input (300ms)
3. **Background Parsing**: Parse logs on background queue
4. **Memory Management**: Limit max entries in memory (last 5000)

## Implementation Order

1. Create data models (`LogEntryModel.swift`)
2. Create parser (`LogParser.swift`)
3. Create deduplicator (`LogDeduplicator.swift`)
4. Create badge components (in `LogsDebugView.swift`)
5. Create main view (`LogsDebugView.swift`)
6. Update `NavigationDestination` enum
7. Update `ContentView` with new case
8. Test on macOS

## macOS-Specific Features

- Window management for detached log viewer
- Keyboard shortcuts (⌘F for search, ⌘C for copy)
- TouchBar support for quick actions
- Export to file with NSSavePanel

## Future Enhancements

1. **Log Rotation**: Auto-rotate old log files
2. **Remote Logs**: Fetch logs from remote devices
3. **Analytics**: Aggregate log statistics
4. **Alerts**: Configure alerts for specific log patterns
5. **Bookmarks**: Save interesting log entries

---

## Estimated Effort

| Component | Complexity | Time |
|-----------|------------|------|
| Data Models | Low | 30 min |
| Parser | Medium | 1 hour |
| Deduplicator | Medium | 1 hour |
| UI Components | Medium | 2 hours |
| Integration | Low | 30 min |
| Testing | Medium | 1 hour |
| **Total** | | **6 hours** |
