import Darwin
import Foundation

/// UPnP AVTransport control (SOAP) for telling a renderer to play or stop a stream URL.
enum AVTransport {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Loads `streamURL` (live 16-bit stereo WAV) on the renderer and starts playback.
    static func play(_ streamURL: String, title: String, on renderer: MediaRenderer) async throws {
        let metadata = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1">\
        <dc:title>\(escape(title))</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        <res protocolInfo="http-get:*:audio/wav:*">\(escape(streamURL))</res></item></DIDL-Lite>
        """
        try await action("SetAVTransportURI", on: renderer, arguments: [
            ("CurrentURI", streamURL),
            ("CurrentURIMetaData", metadata),
        ])
        try await action("Play", on: renderer, arguments: [("Speed", "1")])
    }

    static func stop(on renderer: MediaRenderer) async throws {
        try await action("Stop", on: renderer, arguments: [])
    }

    /// IPv4 address of this Mac's interface that routes to `host` (no packets are sent).
    static func localAddress(toward host: String) throws -> String {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw Failure("Couldn't open a socket.") }
        defer { close(fd) }
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(9).bigEndian
        guard inet_pton(AF_INET, host, &remote.sin_addr) == 1 else {
            throw Failure("\(host) isn't an IPv4 address.")
        }
        let connected = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { throw Failure("No route to \(host).") }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil else {
            throw Failure("Couldn't read this Mac's address.")
        }
        return String(cString: text)
    }

    private static func action(_ name: String, on renderer: MediaRenderer, arguments: [(String, String)]) async throws {
        let service = "urn:schemas-upnp-org:service:AVTransport:1"
        let body = arguments.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(name) xmlns:u="\(service)"><InstanceID>0</InstanceID>\(body)</u:\(name)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: renderer.avTransportControlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(name)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let fault = String(data: data, encoding: .utf8)?
                .range(of: "(?<=<errorDescription>)[^<]+", options: .regularExpression)
                .map { String(String(data: data, encoding: .utf8)![$0]) }
            throw Failure("\(renderer.name) rejected \(name)\(fault.map { ": \($0)" } ?? ".")")
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
