import AVKit
import SwiftUI

/// System AirPlay button; routes this app's audio (including the web view) to the chosen speaker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        // A zero-frame AVRoutePickerView silently ignores taps, so give it its final size up front.
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.prioritizesVideoDevices = false
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
