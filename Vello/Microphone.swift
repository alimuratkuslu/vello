import CoreAudio

/// Which input Vello records from. Auto avoids Bluetooth mics: opening one flips AirPods into low-quality
/// call mode (music degrades, the first syllable is lost while it switches), and the built-in mic hears
/// the user just as well, including during calls where the other side plays in the earbuds.
enum MicMode: String, CaseIterable, Identifiable {
    case auto, builtIn, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "Automatic")
        case .builtIn: String(localized: "MacBook microphone")
        case .system: String(localized: "System default")
        }
    }

    /// nil = system default input.
    func deviceID() -> AudioDeviceID? {
        switch self {
        case .system: return nil
        case .builtIn: return Microphone.builtIn()
        case .auto:
            guard let current = Microphone.defaultInput(), Microphone.isBluetooth(current) else { return nil }
            return Microphone.builtIn() // nil in clamshell mode → falls back to the system default
        }
    }
}

enum Microphone {
    static func defaultInput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        return get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, &id) ? id : nil
    }

    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        let t = transport(device)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    static func builtIn() -> AudioDeviceID? {
        allDevices().first { transport($0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) }
    }

    private static func transport(_ device: AudioDeviceID) -> UInt32 {
        var t = UInt32(0)
        return get(device, kAudioDevicePropertyTransportType, &t) ? t : 0
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
