import AppKit
import Foundation

/// Streams this app's audio to a DLNA/UPnP media renderer: captures the WebKit GPU process (muted on
/// the Mac), serves it as live WAV over HTTP and tells the renderer to play that URL.
@MainActor
final class SpeakerStreamer: ObservableObject {
    enum State: Equatable {
        case idle
        case starting(String)
        case streaming(String)
    }

    @Published private(set) var state: State = .idle
    @Published var errorMessage: String?
    /// The speaker's own volume (0–100) while streaming; nil if unknown or it has no volume control.
    @Published private(set) var volume: Double?

    private struct Session {
        let id = UUID()
        let renderer: MediaRenderer
        let capture: AppAudioCapture
        let server: LiveWAVServer
    }

    private var session: Session?
    /// Latest slider value not yet sent to the speaker.
    private var pendingVolume: Int?
    /// Session whose volume requests are currently being sent, one at a time.
    private var volumeSendingSession: UUID?
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopBeforeTermination() }
        }
    }

    var helpText: String {
        switch state {
        case .idle: "Stream this app's audio to a network speaker"
        case .starting(let name): "Connecting to \(name)…"
        case .streaming(let name): "Streaming to \(name)"
        }
    }

    func start(on renderer: MediaRenderer, gpuProcess: pid_t?) async {
        await stop()
        guard let gpuProcess else {
            errorMessage = "Start playback first, then choose a speaker."
            return
        }
        state = .starting(renderer.name)
        var capture: AppAudioCapture?
        var server: LiveWAVServer?
        do {
            // 4 s of 16-bit stereo at up to 192 kHz; the tap's actual rate is only known once it exists.
            let buffer = LiveAudioBuffer(capacity: 192_000 * 4 * 4)
            let started = try AppAudioCapture.start(pid: gpuProcess) { buffer.write($0) }
            capture = started
            let wavServer = LiveWAVServer(buffer: buffer, sampleRate: Int(started.sampleRate))
            server = wavServer
            let port = try await wavServer.start()
            let localAddress = try AVTransport.localAddress(toward: renderer.host)
            try await AVTransport.play("http://\(localAddress):\(port)/substrait.wav", title: "Substrait", on: renderer)
            session = Session(renderer: renderer, capture: started, server: wavServer)
            state = .streaming(renderer.name)
            await refreshVolume()
        } catch {
            capture?.stop()
            server?.stop()
            state = .idle
            errorMessage = "Couldn't stream to \(renderer.name): \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard let session else { return }
        self.session = nil
        state = .idle
        clearVolume()
        // Stop the renderer first so the Mac doesn't un-mute while the speaker still plays its buffer.
        try? await AVTransport.stop(on: session.renderer)
        session.capture.stop()
        session.server.stop()
    }

    /// Reads the speaker's volume, e.g. after it was changed in the speaker's own app.
    func refreshVolume() async {
        guard let session, session.renderer.renderingControlURL != nil, volumeSendingSession == nil else { return }
        let level = try? await RenderingControl.volume(of: session.renderer)
        guard self.session?.id == session.id, volumeSendingSession == nil else { return }
        volume = level.map(Double.init)
    }

    /// Sets the speaker's volume. Requests go out one at a time and only the latest slider value is
    /// sent next, so dragging doesn't queue up dozens of SOAP calls.
    func setVolume(_ value: Double) {
        guard let session, volume != nil else { return }
        volume = value
        pendingVolume = Int(value.rounded())
        guard volumeSendingSession != session.id else { return }
        volumeSendingSession = session.id
        Task { await sendPendingVolume(for: session) }
    }

    private func sendPendingVolume(for session: Session) async {
        var failed = false
        while self.session?.id == session.id, let level = pendingVolume {
            pendingVolume = nil
            do {
                try await RenderingControl.setVolume(level, on: session.renderer)
            } catch {
                failed = true
            }
        }
        guard self.session?.id == session.id else { return }
        volumeSendingSession = nil
        // Show what the speaker actually has rather than a value it rejected.
        if failed { await refreshVolume() }
    }

    private func clearVolume() {
        volume = nil
        pendingVolume = nil
        volumeSendingSession = nil
    }

    /// Termination can't await, so give the renderer's stop command up to a second.
    private func stopBeforeTermination() {
        guard let session else { return }
        self.session = nil
        clearVolume()
        let done = DispatchSemaphore(value: 0)
        let renderer = session.renderer
        Task.detached {
            try? await AVTransport.stop(on: renderer)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
        session.capture.stop()
        session.server.stop()
    }
}
