import AVFAudio
import SwiftUI

@main
struct iOSApp: App {
    init() {
        // Long-form playback so the system AirPlay route (AVRoutePickerView) carries the web view's audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}