struct AirPlayState: Equatable {
    var hasMedia = false
    var available = false
    var wireless = false
    var remoteDisabled = false
    var mse = false

    var canPick: Bool { hasMedia && available && !remoteDisabled && !mse }

    var helpText: String {
        if !hasMedia { return "Start playback, then choose an AirPlay speaker" }
        if remoteDisabled { return "This source has disabled AirPlay" }
        if mse { return "This source streams in a way AirPlay can't play" }
        if !available { return "No AirPlay speakers found" }
        return wireless ? "Playing on AirPlay speaker" : "Choose AirPlay speaker"
    }
}
