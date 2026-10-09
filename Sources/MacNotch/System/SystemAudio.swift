import AudioToolbox
import CoreAudio

/// Reads and writes the system output volume directly through CoreAudio, so a
/// volume slider stays instant instead of shelling out to `osascript`.
enum SystemAudio {
    private static let mainChannel: UInt32 = 0

    static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: mainChannel
        )
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: mainChannel
        )
    }

    static func outputVolume() -> Double {
        let device = defaultOutputDevice()
        guard device != 0 else { return 0 }
        var address = volumeAddress()
        var volume = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? Double(volume) : 0
    }

    static func setOutputVolume(_ value: Double) {
        let device = defaultOutputDevice()
        guard device != 0 else { return }
        var address = volumeAddress()
        var volume = Float(max(0, min(1, value)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &volume)
    }

    static func isMuted() -> Bool {
        let device = defaultOutputDevice()
        guard device != 0 else { return false }
        var address = muteAddress()
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr && muted == 1
    }

    static func setMuted(_ muted: Bool) {
        let device = defaultOutputDevice()
        guard device != 0 else { return }
        var address = muteAddress()
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static var observerBlocks: [AudioObjectPropertyListenerBlock] = []

    /// Fires `handler` (on the main queue) whenever system volume or mute changes.
    static func observeVolumeChanges(_ handler: @escaping () -> Void) {
        let device = defaultOutputDevice()
        guard device != 0 else { return }
        let queue = DispatchQueue.main

        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: mainChannel
            )
            let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                observerBlocks.append(block)
            }
        }
    }
}
