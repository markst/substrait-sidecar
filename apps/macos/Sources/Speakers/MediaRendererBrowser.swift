import Foundation

/// A UPnP/DLNA media renderer (network speaker, streamer, TV) that can play a URL.
struct MediaRenderer: Identifiable, Hashable {
    /// UPnP device UDN.
    let id: String
    let name: String
    let host: String
    let avTransportControlURL: URL
}

/// Keeps a list of media renderers on the local network, refreshed by periodic SSDP searches.
@MainActor
final class MediaRendererBrowser: ObservableObject {
    @Published private(set) var renderers: [MediaRenderer] = []

    private static let refreshInterval: Duration = .seconds(30)
    private var descriptions: [URL: MediaRenderer] = [:]
    private var refreshTask: Task<Void, Never>?

    init() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    deinit { refreshTask?.cancel() }

    private func refresh() async {
        let locations = await SSDPDiscovery.search()
        var found: [String: MediaRenderer] = [:]
        for location in locations {
            let renderer: MediaRenderer?
            if let cached = descriptions[location] {
                renderer = cached
            } else {
                renderer = await Self.describe(location)
                descriptions[location] = renderer
            }
            if let renderer { found[renderer.id] = renderer }
        }
        renderers = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Fetches a device description and extracts its name and AVTransport control URL.
    private static func describe(_ location: URL) async -> MediaRenderer? {
        var request = URLRequest(url: location)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let host = location.host else { return nil }
        let parsed = DeviceDescriptionParser(data: data)
        guard let name = parsed.friendlyName, let udn = parsed.udn,
              let controlPath = parsed.avTransportControlURL,
              let controlURL = URL(string: controlPath, relativeTo: parsed.urlBase.flatMap(URL.init(string:)) ?? location)?.absoluteURL
        else { return nil }
        return MediaRenderer(id: udn, name: name, host: host, avTransportControlURL: controlURL)
    }
}

/// Minimal UPnP device-description reader: the first device's friendlyName/UDN, the optional
/// URLBase, and the controlURL of the AVTransport service (top-level or embedded device).
private final class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    private(set) var friendlyName: String?
    private(set) var udn: String?
    private(set) var urlBase: String?
    private(set) var avTransportControlURL: String?

    private var text = ""
    private var serviceType: String?
    private var controlURL: String?

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if elementName == "service" {
            serviceType = nil
            controlURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "friendlyName" where friendlyName == nil: friendlyName = value
        case "UDN" where udn == nil: udn = value
        case "URLBase": urlBase = value
        case "serviceType": serviceType = value
        case "controlURL": controlURL = value
        case "service":
            if avTransportControlURL == nil, serviceType?.contains(":service:AVTransport:") == true {
                avTransportControlURL = controlURL
            }
        default: break
        }
    }
}
