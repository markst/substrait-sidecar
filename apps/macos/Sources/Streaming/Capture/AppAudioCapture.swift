import AudioToolbox
import CoreAudio
import Foundation

/// Captures everything one process plays (here: this app's WebKit GPU process) with a Core Audio
/// process tap, muting it on the Mac, and delivers it as interleaved 16-bit stereo PCM.
final class AppAudioCapture {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    let sampleRate: Double

    private let tapID: AudioObjectID
    private let aggregateID: AudioObjectID
    private let ioProcID: AudioDeviceIOProcID
    private let converter: StereoInt16Converter
    private var stopped = false

    private init(sampleRate: Double, tapID: AudioObjectID, aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID, converter: StereoInt16Converter) {
        self.sampleRate = sampleRate
        self.tapID = tapID
        self.aggregateID = aggregateID
        self.ioProcID = ioProcID
        self.converter = converter
    }

    deinit { stop() }

    /// Starts capturing `pid`. `onPCM` runs on Core Audio's real-time thread: keep it allocation-free.
    static func start(pid: pid_t, onPCM: @escaping (UnsafeRawBufferPointer) -> Void) throws -> AppAudioCapture {
        let process = try processObject(for: pid)

        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.isPrivate = true
        description.muteBehavior = .muted
        description.uuid = UUID()
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the audio tap")

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        do {
            let format = try property(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else {
                throw Failure("The audio tap delivered an unsupported format.")
            }
            let outputDevice = try property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(kAudioObjectUnknown))
            let outputUID = try property(outputDevice, kAudioDevicePropertyDeviceUID, "" as CFString) as String
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Substrait capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create the capture device")

            let converter = StereoInt16Converter(capacityFrames: 8192)
            var ioProcID: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, _, _ in
                converter.convert(input, deliver: onPCM)
            }, "attach to the capture device")
            guard let ioProcID else { throw Failure("Couldn't attach to the capture device.") }
            let capture = AppAudioCapture(sampleRate: format.mSampleRate, tapID: tapID, aggregateID: aggregateID, ioProcID: ioProcID, converter: converter)
            try check(AudioDeviceStart(aggregateID, ioProcID), "start capturing")
            return capture
        } catch {
            if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    /// Stops capturing and un-mutes the process on the Mac.
    func stop() {
        guard !stopped else { return }
        stopped = true
        AudioDeviceStop(aggregateID, ioProcID)
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        AudioHardwareDestroyAggregateDevice(aggregateID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    private static func processObject(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else {
            throw Failure("The player hasn't produced any audio yet. Start playback, then choose a speaker.")
        }
        return object
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "read audio device properties")
        return value
    }

    private static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw Failure("Couldn't \(action) (Core Audio error \(status)).") }
    }
}

/// Converts Core Audio float buffers (interleaved or not, mono or stereo) to interleaved Int16 stereo
/// into a preallocated scratch buffer, so the real-time callback never allocates.
private final class StereoInt16Converter {
    private let capacityFrames: Int
    private let scratch: UnsafeMutablePointer<Int16>

    init(capacityFrames: Int) {
        self.capacityFrames = capacityFrames
        scratch = .allocate(capacity: capacityFrames * 2)
    }

    deinit { scratch.deallocate() }

    func convert(_ list: UnsafePointer<AudioBufferList>, deliver: (UnsafeRawBufferPointer) -> Void) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mNumberChannels > 0,
              buffers.allSatisfy({ $0.mData != nil }) else { return }
        let firstChannels = Int(first.mNumberChannels)
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * firstChannels)

        func sample(_ frame: Int, _ channel: Int) -> Float {
            if buffers.count == 1 {
                let samples = first.mData!.assumingMemoryBound(to: Float.self)
                return samples[frame * firstChannels + min(channel, firstChannels - 1)]
            }
            return buffers[min(channel, buffers.count - 1)].mData!.assumingMemoryBound(to: Float.self)[frame]
        }

        var start = 0
        while start < frames {
            let count = min(capacityFrames, frames - start)
            for i in 0..<count {
                for channel in 0..<2 {
                    let clamped = max(-1, min(1, sample(start + i, channel)))
                    scratch[i * 2 + channel] = Int16(clamped * Float(Int16.max))
                }
            }
            deliver(UnsafeRawBufferPointer(start: scratch, count: count * 2 * MemoryLayout<Int16>.size))
            start += count
        }
    }
}
