import Foundation
import Network

/// Serves the captured audio as an endless 16-bit stereo WAV over HTTP for the speaker to pull.
/// Each listener starts just behind live and is kept at most `maxLagSeconds` behind it.
final class LiveWAVServer: @unchecked Sendable {
    private static let prerollSeconds = 0.25
    private static let maxLagSeconds = 1.5
    private static let maxInFlightSeconds = 1.0
    private static let tick = DispatchTimeInterval.milliseconds(20)

    private let buffer: LiveAudioBuffer
    private let sampleRate: Int
    private let bytesPerSecond: Int
    private let queue = DispatchQueue(label: "dev.markturnip.substrait.wav-server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]

    private final class Client {
        let connection: NWConnection
        var request = Data()
        var position = 0
        var inFlight = 0
        var timer: DispatchSourceTimer?
        init(connection: NWConnection) { self.connection = connection }
    }

    init(buffer: LiveAudioBuffer, sampleRate: Int) {
        self.buffer = buffer
        self.sampleRate = sampleRate
        bytesPerSecond = sampleRate * 4
    }

    /// Starts listening on an ephemeral port and returns it.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for client in self.clients.values { self.close(client) }
        }
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        clients[ObjectIdentifier(client)] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled: self.close(client)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveRequest(client)
    }

    private func receiveRequest(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { client.request.append(data) }
            if client.request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: client)
            } else if error != nil || isComplete || client.request.count > 16384 {
                self.close(client)
            } else {
                self.receiveRequest(client)
            }
        }
    }

    private func respond(to client: Client) {
        let headers = Data((
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: audio/wav\r\n" +
            "Cache-Control: no-cache\r\n" +
            // DLNA renderers (e.g. Sonos) expect these on live streams.
            "transferMode.dlna.org: Streaming\r\n" +
            "contentFeatures.dlna.org: DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\r\n" +
            "Connection: close\r\n\r\n"
        ).utf8)
        guard !client.request.starts(with: Data("HEAD ".utf8)) else {
            client.connection.send(content: headers, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in self?.close(client) })
            return
        }
        client.connection.send(content: headers + wavHeader(), completion: .contentProcessed { _ in })
        client.position = startPosition()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.tick)
        timer.setEventHandler { [weak self] in self?.pump(client) }
        client.timer = timer
        timer.resume()
    }

    private func pump(_ client: Client) {
        // A speaker that consumes slower than we produce would otherwise grow the delay forever.
        guard client.inFlight < Int(Double(bytesPerSecond) * Self.maxInFlightSeconds) else { return }
        if buffer.totalWritten - client.position > Int(Double(bytesPerSecond) * Self.maxLagSeconds) {
            client.position = startPosition()
        }
        let chunk = buffer.read(from: &client.position, maxBytes: bytesPerSecond / 2)
        guard !chunk.isEmpty else { return }
        client.inFlight += chunk.count
        client.connection.send(content: chunk, completion: .contentProcessed { [weak self, weak client] error in
            guard let self, let client else { return }
            client.inFlight -= chunk.count
            if error != nil { self.close(client) }
        })
    }

    private func startPosition() -> Int {
        let preroll = Int(Double(sampleRate) * Self.prerollSeconds) * 4
        return max(0, buffer.totalWritten - preroll)
    }

    private func close(_ client: Client) {
        client.timer?.cancel()
        client.timer = nil
        client.connection.cancel()
        clients[ObjectIdentifier(client)] = nil
    }

    /// Streaming WAV header: 16-bit stereo PCM with "unknown" (maximal) RIFF and data sizes.
    private func wavHeader() -> Data {
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8)); append(UInt32.max)
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2))
        append(UInt32(sampleRate)); append(UInt32(bytesPerSecond)); append(UInt16(4)); append(UInt16(16))
        header.append(contentsOf: Array("data".utf8)); append(UInt32.max)
        return header
    }
}
