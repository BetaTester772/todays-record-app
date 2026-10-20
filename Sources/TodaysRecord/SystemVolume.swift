import AudioToolbox
import CoreAudio
import Foundation

/// 기본 출력 장치의 음량과 음소거. CoreAudio 속성 알림으로 바로 받는다. 명세 4.10.
final class SystemVolume {
    struct Level: Equatable {
        /// 0...1. 장치에 음량 조절이 없으면 nil.
        var level: Double?
        var muted: Bool

        var payload: [String: Any] {
            var dict: [String: Any] = ["muted": muted]
            if let level { dict["level"] = level }
            return dict
        }
    }

    /// 메인 스레드에서 불린다.
    var onChange: ((Level) -> Void)?
    private(set) var current = Level(level: nil, muted: false)

    private var device = AudioObjectID(kAudioObjectUnknown)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    deinit {
        detach()
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, defaultDeviceListener)
    }

    func start() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, defaultDeviceListener)
        attach()
    }

    /// 기본 출력 장치가 바뀌면 새 장치에 다시 붙는다.
    private func attach() {
        detach()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else {
            Log.app.error("기본 출력 장치를 찾지 못함 \(status)")
            return
        }
        device = id
        for address in [Self.volumeAddress, Self.muteAddress] {
            var address = address
            if AudioObjectHasProperty(device, &address) {
                AudioObjectAddPropertyListenerBlock(device, &address, .main, deviceListener)
            }
        }
        refresh()
    }

    private func detach() {
        guard device != kAudioObjectUnknown else { return }
        for address in [Self.volumeAddress, Self.muteAddress] {
            var address = address
            if AudioObjectHasProperty(device, &address) {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
            }
        }
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func refresh() {
        var volume = Float32(0)
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        let hasVolume = AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &volumeSize, &volume) == noErr

        var mute = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &muteSize, &mute) == noErr

        let level = Level(level: hasVolume ? Double(volume) : nil, muted: hasMute && mute != 0)
        guard level != current else { return }
        current = level
        onChange?(level)
    }
}
