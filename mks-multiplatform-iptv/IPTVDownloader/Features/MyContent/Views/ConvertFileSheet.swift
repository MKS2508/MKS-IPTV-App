import SwiftUI
import IPTVCore
import TransmuxCore

// MARK: - Output Format Options

private enum OutputFormatOption: String, CaseIterable {
    case mp4 = "MP4"
    case mkv = "MKV"
    case mov = "MOV"

    var fileExtension: String { rawValue.lowercased() }
}

// MARK: - Convert File Sheet

struct ConvertFileSheet: View {
    let file: LocalVideoFile
    let onDismiss: () -> Void
    let onComplete: (URL) -> Void

    @State private var selectedFormat = OutputFormatOption.mp4
    @State private var transcodeAudio = true
    @State private var isConverting = false
    @State private var progress: Double = 0
    @State private var elapsed: TimeInterval = 0
    @State private var errorMessage: String?
    @State private var startTime: Date?

    @State private var outputURL: URL?
    @State private var conversionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            header
            Divider()
            fileInfo
            Divider()
            formatPicker
            audioPicker
            progressSection
            actionButtons
        }
        .padding(24)
        .frame(width: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Convert Format")
                .font(.headline)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - File Info

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack {
                Text(file.fileExtension.uppercased())
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .cornerRadius(4)
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT FORMAT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(OutputFormatOption.allCases, id: \.self) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                            Text(format.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedFormat == format ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedFormat == format ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedFormat == format ? .primary : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Audio Picker

    private var audioPicker: some View {
        Toggle(isOn: $transcodeAudio) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcode audio to AAC")
                    .font(.subheadline)
                Text("EAC3/AC3/DTS → AAC. Recommended for AirPlay and Apple TV compatibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if isConverting {
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatElapsed(elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.red.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if isConverting {
                Button(role: .destructive) {
                    conversionTask?.cancel()
                    isConverting = false
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    startConversion()
                } label: {
                    Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFormat.fileExtension == file.fileExtension)
            }

            Spacer()

            #if os(macOS)
            if let output = outputURL, !isConverting {
                Button {
                    NSWorkspace.shared.selectFile(output.path, inFileViewerRootedAtPath: output.deletingLastPathComponent().path)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            #endif
        }
    }

    // MARK: - Conversion Logic

    private func startConversion() {
        errorMessage = nil
        outputURL = nil
        isConverting = true
        progress = 0
        elapsed = 0
        startTime = Date()

        // Generate output path
        let outputDir = file.url.deletingLastPathComponent()
        let baseName = file.url.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName).\(selectedFormat.fileExtension)"
        let destURL = outputDir.appendingPathComponent(outputName)

        // Prevent overwriting self
        guard destURL.path != file.url.path else {
            errorMessage = "Cannot convert to the same format"
            isConverting = false
            return
        }

        conversionTask = Task { @MainActor in
            do {
                let session = try await TransmuxingService.shared.startTransmux(
                    from: file.url,
                    transcodeAudio: transcodeAudio
                )

                // Monitor progress
                let start = Date()
                while !Task.isCancelled {
                    let buffered = await session.segmenter.latestBufferedSourceTime()
                    let pct = session.duration > 0 ? min(buffered / session.duration, 1.0) : 0.0
                    await MainActor.run {
                        self.progress = pct
                        self.elapsed = Date().timeIntervalSince(start)
                    }
                    if pct >= 1.0 { break }
                    try await Task.sleep(for: .milliseconds(500))
                }

                if Task.isCancelled {
                    await TransmuxingService.shared.cleanup(sessionID: session.sessionID)
                    return
                }

                // Wait for completion notification
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    NotificationCenter.default.addObserver(
                        forName: .transmuxDidComplete,
                        object: session.sessionID,
                        queue: .main
                    ) { _ in
                        continuation.resume()
                    }
                }

                // Move to destination
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(atPath: session.outputPath, toPath: destURL.path)

                await TransmuxingService.shared.cleanup(sessionID: session.sessionID)

                await MainActor.run {
                    self.progress = 1.0
                    self.isConverting = false
                    self.outputURL = destURL
                    self.onComplete(destURL)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isConverting = false
                }
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
