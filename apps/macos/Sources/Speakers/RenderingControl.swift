import Foundation

/// UPnP RenderingControl (SOAP): the renderer's own master volume, the one its app shows.
/// Assumes the usual 0–100 range (WiiM's SCPD declares exactly that).
enum RenderingControl {
    private static let service = "urn:schemas-upnp-org:service:RenderingControl:1"

    static func volume(of renderer: MediaRenderer) async throws -> Int {
        let response = try await UPnPSOAP.call(
            "GetVolume", service: service, controlURL: try controlURL(of: renderer),
            rendererName: renderer.name, arguments: [("Channel", "Master")]
        )
        guard let volume = UPnPSOAP.value(of: "CurrentVolume", in: response).flatMap({ Int($0) }) else {
            throw UPnPSOAP.Failure("\(renderer.name) didn't report its volume.")
        }
        return volume
    }

    static func setVolume(_ volume: Int, on renderer: MediaRenderer) async throws {
        try await UPnPSOAP.call(
            "SetVolume", service: service, controlURL: try controlURL(of: renderer),
            rendererName: renderer.name, arguments: [("Channel", "Master"), ("DesiredVolume", String(min(max(volume, 0), 100)))]
        )
    }

    private static func controlURL(of renderer: MediaRenderer) throws -> URL {
        guard let url = renderer.renderingControlURL else {
            throw UPnPSOAP.Failure("\(renderer.name) has no volume control.")
        }
        return url
    }
}
