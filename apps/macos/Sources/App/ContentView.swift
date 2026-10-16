import SwiftUI

struct ContentView: View {
    @StateObject private var player = WebPlayer()
    @StateObject private var streamer = SpeakerStreamer()
    @StateObject private var speakers = MediaRendererBrowser()

    /// `obscuredContentInsets` (macOS 26+) is what lets page content start below a transparent
    /// toolbar yet scroll under it; on older systems keep the web view below the toolbar.
    private var extendsUnderToolbar: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var airPlayIconStyle: AnyShapeStyle {
        if player.airPlay.wireless { return AnyShapeStyle(Color.accentColor) }
        return player.airPlay.canPick ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
    }

    private var streamingIconStyle: AnyShapeStyle {
        switch streamer.state {
        case .idle: AnyShapeStyle(.primary)
        case .starting: AnyShapeStyle(.secondary)
        case .streaming: AnyShapeStyle(Color.accentColor)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            WebViewHost(webView: player.webView, topInset: extendsUnderToolbar ? geometry.safeAreaInsets.top : 0)
                .ignoresSafeArea(edges: extendsUnderToolbar ? .top : [])
        }
        .background(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    player.showAirPlayPicker()
                } label: {
                    Image(systemName: "airplayaudio")
                        .foregroundStyle(airPlayIconStyle)
                }
                .disabled(!player.airPlay.canPick)
                .help(player.airPlay.helpText)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if case .streaming(let name) = streamer.state {
                        Button("Stop Streaming to \(name)") {
                            Task { await streamer.stop() }
                        }
                        Divider()
                    }
                    if speakers.renderers.isEmpty {
                        Text("No network speakers found")
                    }
                    ForEach(speakers.renderers) { renderer in
                        Button("Stream to \(renderer.name)") {
                            Task { await streamer.start(on: renderer, gpuProcess: player.gpuProcessIdentifier) }
                        }
                    }
                } label: {
                    Image(systemName: "hifispeaker")
                        .foregroundStyle(streamingIconStyle)
                }
                .help(streamer.helpText)
            }
        }
        .alert(
            "Speaker Streaming",
            isPresented: Binding(get: { streamer.errorMessage != nil }, set: { if !$0 { streamer.errorMessage = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(streamer.errorMessage ?? "") }
        )
    }
}
