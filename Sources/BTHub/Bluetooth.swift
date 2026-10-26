import BTHubCore
import Foundation
import IOBluetooth

/// This Mac's paired Bluetooth audio devices, driven through IOBluetooth.
final class Bluetooth: @unchecked Sendable {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    // Many devices report an unhelpful class of device, so the audio profiles they offer count too.
    private static let audioServices: [SDPServiceClasses] = [
        kBluetoothSDPUUID16ServiceClassAudioSink,
        kBluetoothSDPUUID16ServiceClassHandsFree,
        kBluetoothSDPUUID16ServiceClassHeadset,
    ]

    // openConnection blocks until the link is up or times out, so it stays off the main thread.
    private let queue = DispatchQueue(label: "bthub.bluetooth")

    func audioDevices() async -> [DeviceState] {
        await run {
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            return paired
                .filter(Self.isAudio)
                .map { DeviceState(address: Self.canonical($0.addressString), name: $0.name ?? $0.addressString, connected: $0.isConnected(), kind: Self.kind(of: $0)) }
                .sorted { $0.name < $1.name }
        }
    }

    func connect(_ address: String) async throws {
        try await run {
            let device = try Self.device(address)
            if device.isConnected() { return }
            let result = device.openConnection()
            guard result == kIOReturnSuccess else {
                throw Failure(errorDescription: String(localized: "the device did not respond (code \(Self.hex(result)))"))
            }
        }
    }

    func disconnect(_ address: String) async throws {
        try await run {
            let device = try Self.device(address)
            guard device.isConnected() else { return }
            let result = device.closeConnection()
            guard result == kIOReturnSuccess else {
                throw Failure(errorDescription: String(localized: "could not disconnect (code \(Self.hex(result)))"))
            }
        }
    }

    private static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        if device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) { return true }
        return audioServices.contains { uuid in
            device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: BluetoothSDPUUID16(uuid.rawValue))) != nil
        }
    }

    private static func kind(of device: IOBluetoothDevice) -> DeviceState.Kind {
        guard device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) else { return .other }
        switch Int(device.deviceClassMinor) {
        case kBluetoothDeviceClassMinorAudioHeadset, kBluetoothDeviceClassMinorAudioHandsFree, kBluetoothDeviceClassMinorAudioHeadphones:
            return .headphones
        case kBluetoothDeviceClassMinorAudioLoudspeaker, kBluetoothDeviceClassMinorAudioPortable, kBluetoothDeviceClassMinorAudioHiFi:
            return .speaker
        default:
            return .other
        }
    }

    private static func device(_ address: String) throws -> IOBluetoothDevice {
        guard let device = IOBluetoothDevice(addressString: address), device.isPaired() else {
            throw Failure(errorDescription: String(localized: "the device is not paired with this Mac"))
        }
        return device
    }

    /// IOBluetooth spells addresses `aa-bb-cc-dd-ee-ff`; peers exchange `AA:BB:CC:DD:EE:FF`.
    static func canonical(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    private static func hex(_ code: IOReturn) -> String {
        String(format: "0x%x", code)
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func run<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}
