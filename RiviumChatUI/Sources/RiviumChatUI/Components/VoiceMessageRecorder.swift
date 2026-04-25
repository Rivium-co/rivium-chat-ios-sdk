import SwiftUI
import AVFoundation

/// State of the voice recorder.
public enum VoiceRecorderState {
    case idle
    case recording
    case locked
    case cancelled
}

/// Result of a voice recording.
public struct VoiceRecordingResult {
    public let url: URL
    public let duration: TimeInterval
    public let waveform: [Float]?

    public init(url: URL, duration: TimeInterval, waveform: [Float]? = nil) {
        self.url = url
        self.duration = duration
        self.waveform = waveform
    }
}

/// A widget for recording voice messages with hold-to-record and slide-to-cancel.
public struct VoiceMessageRecorder: View {
    @Binding var isRecording: Bool
    let onRecordingComplete: (VoiceRecordingResult) -> Void
    var onRecordingCancelled: (() -> Void)?
    var cancelThreshold: CGFloat = 80
    var lockThreshold: CGFloat = 60

    @State private var state: VoiceRecorderState = .idle
    @State private var dragOffset: CGSize = .zero
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var waveformSamples: [Float] = []

    @Environment(\.riviumChatColors) private var colors

    public init(
        isRecording: Binding<Bool>,
        onRecordingComplete: @escaping (VoiceRecordingResult) -> Void,
        onRecordingCancelled: (() -> Void)? = nil,
        cancelThreshold: CGFloat = 80,
        lockThreshold: CGFloat = 60
    ) {
        self._isRecording = isRecording
        self.onRecordingComplete = onRecordingComplete
        self.onRecordingCancelled = onRecordingCancelled
        self.cancelThreshold = cancelThreshold
        self.lockThreshold = lockThreshold
    }

    public var body: some View {
        ZStack {
            if state == .idle {
                recordButton
            } else {
                recordingUI
            }
        }
    }

    private var recordButton: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundColor(.accentColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.2)
                    .onEnded { _ in
                        startRecording()
                    }
                    .simultaneously(with:
                        DragGesture()
                            .onChanged { value in
                                if state == .recording {
                                    dragOffset = value.translation

                                    // Check for cancel (slide left)
                                    if -value.translation.width > cancelThreshold {
                                        cancelRecording()
                                    }

                                    // Check for lock (slide up)
                                    if -value.translation.height > lockThreshold && state == .recording {
                                        state = .locked
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                    }
                                }
                            }
                            .onEnded { _ in
                                if state == .recording {
                                    stopRecording()
                                }
                                dragOffset = .zero
                            }
                    )
            )
    }

    private var recordingUI: some View {
        HStack(spacing: 16) {
            // Cancel hint or locked indicator
            if state == .locked {
                Button(action: cancelRecording) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.secondary)
                    Text("Slide to cancel")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(Double(1 - min(1, -dragOffset.width / cancelThreshold)))
            }

            Spacer()

            // Recording indicator and duration
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(recordingDuration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)

                Text(formatDuration(recordingDuration))
                    .font(.subheadline)
                    .monospacedDigit()
            }

            // Send button when locked, or recording indicator
            if state == .locked {
                Button(action: stopRecording) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                }
            } else {
                // Lock hint
                VStack(spacing: 2) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(Double(max(0, 1 + dragOffset.height / lockThreshold)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(20)
    }

    private func startRecording() {
        guard state == .idle else { return }

        // Request permission
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.beginRecording()
                }
            }
        }
    }

    private func beginRecording() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("voice_\(Date().timeIntervalSince1970).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            state = .recording
            isRecording = true
            recordingDuration = 0
            waveformSamples = []

            // Start timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.recordingDuration += 0.1
                self.audioRecorder?.updateMeters()
                if let power = self.audioRecorder?.averagePower(forChannel: 0) {
                    // Normalize power to 0-1 range
                    let normalizedPower = max(0, (power + 60) / 60)
                    self.waveformSamples.append(normalizedPower)
                }
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder, state == .recording || state == .locked else { return }

        timer?.invalidate()
        timer = nil

        recorder.stop()
        let url = recorder.url
        let duration = recordingDuration

        audioRecorder = nil
        state = .idle
        isRecording = false
        recordingDuration = 0

        let result = VoiceRecordingResult(
            url: url,
            duration: duration,
            waveform: waveformSamples
        )
        waveformSamples = []

        onRecordingComplete(result)
    }

    private func cancelRecording() {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        if let url = audioRecorder?.url {
            try? FileManager.default.removeItem(at: url)
        }

        audioRecorder = nil
        state = .idle
        isRecording = false
        recordingDuration = 0
        waveformSamples = []
        dragOffset = .zero

        onRecordingCancelled?()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A widget for playing back voice messages.
public struct VoiceMessagePlayer: View {
    let url: URL
    var duration: TimeInterval?
    var waveform: [Float]?

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var timer: Timer?

    public init(url: URL, duration: TimeInterval? = nil, waveform: [Float]? = nil) {
        self.url = url
        self.duration = duration
        self.waveform = waveform
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }

            // Waveform or progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(Color(UIColor.systemGray4))
                        .frame(height: 4)

                    // Progress
                    let totalDuration = duration ?? audioPlayer?.duration ?? 1
                    let progress = currentTime / totalDuration
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(progress), height: 4)
                }
                .frame(height: 24)
            }
            .frame(height: 24)

            // Duration
            Text(formatDuration(isPlaying ? currentTime : (duration ?? 0)))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.currentTime = currentTime
            audioPlayer?.play()

            isPlaying = true

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let player = self.audioPlayer {
                    self.currentTime = player.currentTime
                    if !player.isPlaying {
                        self.stopPlayback()
                    }
                }
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
