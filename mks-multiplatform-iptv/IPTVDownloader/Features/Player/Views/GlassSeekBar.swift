import SwiftUI
import IPTVCore

struct GlassSeekBar: View {
    @Binding var progress: Double
    var bufferedProgress: Double = 0
    var currentTime: String = "0:00"
    var duration: String = "0:00"
    var remainingTime: String = "0:00"
    var onSeek: ((Double) -> Void)?
    var onSeekPreview: ((Double) -> Void)?
    var onSeekStart: (() -> Void)?
    var onSeekEnd: (() -> Void)?
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showPreview: Bool = false
    
    private let trackHeight: CGFloat = 4
    private let expandedTrackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 14
    
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    trackView(width: geometry.size.width)
                    bufferedView(width: geometry.size.width)
                    progressView(width: geometry.size.width)
                    thumbView(width: geometry.size.width)
                }
                .frame(height: isDragging ? expandedTrackHeight : trackHeight)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .contentShape(Rectangle().size(width: geometry.size.width, height: 24))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value: value, width: geometry.size.width)
                        }
                        .onEnded { value in
                            handleDragEnded(value: value, width: geometry.size.width)
                        }
                )
                .onTapGesture { location in
                    handleTap(location: location, width: geometry.size.width)
                }
            }
            .frame(height: 24)
            
            timeLabelsView
        }
    }
    
    @ViewBuilder
    private func trackView(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: trackHeight / 2)
            .fill(Color.white.opacity(0.2))
            .frame(width: width, height: isDragging ? expandedTrackHeight : trackHeight)
    }
    
    @ViewBuilder
    private func bufferedView(width: CGFloat) -> some View {
        let bufferWidth = width * (isDragging ? dragProgress : bufferedProgress)
        RoundedRectangle(cornerRadius: trackHeight / 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: bufferWidth, height: isDragging ? expandedTrackHeight : trackHeight)
    }
    
    @ViewBuilder
    private func progressView(width: CGFloat) -> some View {
        let currentProgress = isDragging ? dragProgress : progress
        let progressWidth = width * currentProgress
        RoundedRectangle(cornerRadius: trackHeight / 2)
            .fill(AppColors.accent)
            .frame(width: max(0, progressWidth), height: isDragging ? expandedTrackHeight : trackHeight)
    }
    
    @ViewBuilder
    private func thumbView(width: CGFloat) -> some View {
        let currentProgress = isDragging ? dragProgress : progress
        Circle()
            .fill(Color.white)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .overlay(
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: thumbSize - 4, height: thumbSize - 4)
            )
            .offset(x: width * currentProgress - thumbSize / 2)
            .scaleEffect(isDragging ? 1.2 : 1.0)
            .animation(.spring(response: 0.2), value: isDragging)
    }
    
    @ViewBuilder
    private var timeLabelsView: some View {
        HStack {
            Text(isDragging ? previewTime : currentTime)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDragging ? AppColors.accent : .white.opacity(0.8))
                .monospacedDigit()
            
            Spacer()
            
            if isDragging {
                Text(previewRemaining)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            } else {
                Text(duration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var previewTime: String {
        guard durationValue > 0 else { return "0:00" }
        let previewSeconds = dragProgress * durationValue
        return PlayerTimeInfo.formatTime(previewSeconds)
    }
    
    private var previewRemaining: String {
        guard durationValue > 0 else { return "-0:00" }
        let previewSeconds = dragProgress * durationValue
        let remaining = durationValue - previewSeconds
        return "-\(PlayerTimeInfo.formatTime(remaining))"
    }
    
    private var durationValue: Double {
        guard let durStr = duration.components(separatedBy: ":").last,
              let _ = Double(durStr) else {
            let parts = duration.components(separatedBy: ":")
            if parts.count == 2 {
                return Double(parts[0])! * 60 + Double(parts[1])!
            } else if parts.count == 3 {
                return Double(parts[0])! * 3600 + Double(parts[1])! * 60 + Double(parts[2])!
            }
            return 0
        }
        return 0
    }
    
    private func handleDragChanged(value: DragGesture.Value, width: CGFloat) {
        if !isDragging {
            isDragging = true
            showPreview = true
            onSeekStart?()
            #if os(iOS)
            if UserDefaults.standard.bool(forKey: "PlayerHapticFeedback") {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            #endif
        }
        
        let fraction = max(0, min(1, value.location.x / width))
        dragProgress = fraction
        onSeekPreview?(fraction)
    }
    
    private func handleDragEnded(value: DragGesture.Value, width: CGFloat) {
        let fraction = max(0, min(1, value.location.x / width))
        isDragging = false
        showPreview = false
        onSeek?(fraction)
        onSeekEnd?()
    }
    
    private func handleTap(location: CGPoint, width: CGFloat) {
        let fraction = max(0, min(1, location.x / width))
        onSeek?(fraction)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            GlassSeekBar(
                progress: .constant(0.35),
                bufferedProgress: 0.6,
                currentTime: "12:34",
                duration: "1:45:00",
                remainingTime: "-1:32:26"
            )
            .padding()
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }
}
