import Darwin
import Foundation

/// SSDP (UPnP discovery): multicasts an M-SEARCH for AVTransport services and collects the
/// `LOCATION` (device description URL) of every unicast reply. Plain BSD sockets, so no
/// multicast entitlement is needed on macOS.
enum SSDPDiscovery {
    private static let searchTarget = "urn:schemas-upnp-org:service:AVTransport:1"

    static func search(timeout: TimeInterval = 3) async -> Set<URL> {
        await Task.detached(priority: .utility) { searchBlocking(timeout: timeout) }.value
    }

    private static func searchBlocking(timeout: TimeInterval) -> Set<URL> {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var destination = sockaddr_in()
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        destination.sin_addr.s_addr = inet_addr("239.255.255.250")
        let request = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: \(searchTarget)\r\n\r\n"
        // UDP is lossy; send the search a few times.
        for _ in 0..<3 {
            _ = request.withCString { bytes in
                withUnsafePointer(to: &destination) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes, strlen(bytes), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var locations = Set<URL>()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0, let response = String(bytes: buffer[0..<count], encoding: .utf8) else { continue }
            for line in response.split(separator: "\r\n") where line.lowercased().hasPrefix("location:") {
                let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if let url = URL(string: value) { locations.insert(url) }
            }
        }
        return locations
    }
}
