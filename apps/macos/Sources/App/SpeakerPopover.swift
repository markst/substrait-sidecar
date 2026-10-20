import SwiftUI

/// The stream button's popover: the speaker's volume and Stop while streaming, and the network
/// speakers to stream to. A popover rather than a menu because menus can't hold a slider.
struct SpeakerPopover: View {
    @ObservedObject var streamer: SpeakerStreamer
    @ObservedObject var speakers: MediaRendererBrowser
    let start: (MediaRenderer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch streamer.state {
            case .streaming(let name):
                Text("Streaming to \(name)")
                    .font(.headline)
                if let volume = streamer.volume {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { volume }, set: streamer.setVolume), in: 0...100) {
                            Text("Volume")
                        }
                        .labelsHidden()
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Stop Streaming") {
                    Task { await streamer.stop() }
                }
                Divider()
            case .starting(let name):
                Text("Connecting to \(name)…")
                    .foregroundStyle(.secondary)
                Divider()
            case .idle:
                EmptyView()
            }
            if speakers.renderers.isEmpty {
                Text("No network speakers found")
                    .foregroundStyle(.secondary)
            }
            ForEach(speakers.renderers) { renderer in
                Button("Stream to \(renderer.name)", systemImage: "hifispeaker") {
                    start(renderer)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        // Pick up changes made meanwhile on the speaker or in its own app.
        .task { await streamer.refreshVolume() }
    }
}
