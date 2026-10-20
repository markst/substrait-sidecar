import Foundation

/// Minimal UPnP SOAP client shared by the AVTransport and RenderingControl services.
enum UPnPSOAP {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Calls `action` on instance 0 of `service` and returns the response body.
    @discardableResult
    static func call(
        _ action: String,
        service: String,
        controlURL: URL,
        rendererName: String,
        arguments: [(String, String)]
    ) async throws -> String {
        let body = arguments.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(service)"><InstanceID>0</InstanceID>\(body)</u:\(action)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let fault = value(of: "errorDescription", in: text)
            throw Failure("\(rendererName) rejected \(action)\(fault.map { ": \($0)" } ?? ".")")
        }
        return text
    }

    /// Text of the first `<element>` in a SOAP response (UPnP response arguments are unprefixed).
    static func value(of element: String, in response: String) -> String? {
        response.range(of: "(?<=<\(element)>)[^<]+", options: .regularExpression).map { String(response[$0]) }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
