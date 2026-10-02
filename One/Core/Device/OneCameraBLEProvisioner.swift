@preconcurrency import CoreBluetooth
import Foundation
import Observation

struct NearbyOneCamera: Identifiable, Equatable {
    let id: UUID
    let name: String
    let signal: Int
}

@MainActor
@Observable
final class OneCameraBLEProvisioner: NSObject {
    enum Phase: Equatable {
        case idle
        case bluetoothUnavailable(String)
        case scanning
        case connecting
        case sending
        case waitingForNetwork
        case linkingAccount
        case paired
        case failed(String)
    }

    static let serviceUUID = CBUUID(string: "7BB10000-8D4B-4D56-9A79-7D2A3A100001")
    static let provisionUUID = CBUUID(string: "7BB10001-8D4B-4D56-9A79-7D2A3A100001")
    static let statusUUID = CBUUID(string: "7BB10002-8D4B-4D56-9A79-7D2A3A100001")

    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var target: CBPeripheral?
    private var pendingPayload: Data?
    private var pendingWrites: [Data] = []
    private var pendingWriteIndex = 0
    private var provisionCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var wantsScanning = false

    var phase: Phase = .idle
    var nearby: [NearbyOneCamera] = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        wantsScanning = true
        guard central.state == .poweredOn else {
            updateBluetoothState(central.state)
            return
        }
        nearby = []
        discovered = [:]
        phase = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        wantsScanning = false
        central.stopScan()
        if phase == .scanning { phase = .idle }
    }

    func provision(
        deviceID: UUID,
        ssid: String,
        password: String,
        pairingCode: String,
        apiBaseURL: URL,
        videoConsent: Bool,
        audioConsent: Bool
    ) {
        guard let peripheral = discovered[deviceID] else {
            phase = .failed("That ONE Camera is no longer nearby. Scan again and retry.")
            return
        }
        let payload: [String: Any] = [
            "version": 1,
            "wifi": ["ssid": ssid, "password": password],
            "pairing": ["code": pairingCode, "api_base_url": apiBaseURL.absoluteString],
            "capture": ["video": videoConsent, "audio": audioConsent],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard data.count <= 4096 else {
                phase = .failed("The Wi-Fi setup details are too long for Bluetooth provisioning.")
                return
            }
            pendingPayload = data
        } catch {
            phase = .failed("ONE could not prepare the camera setup details.")
            return
        }

        central.stopScan()
        target = peripheral
        peripheral.delegate = self
        phase = .connecting
        central.connect(peripheral)
    }

    func reset() {
        if let target { central.cancelPeripheralConnection(target) }
        target = nil
        pendingPayload = nil
        pendingWrites = []
        pendingWriteIndex = 0
        provisionCharacteristic = nil
        statusCharacteristic = nil
        phase = .idle
    }

    private func updateBluetoothState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if wantsScanning { startScanning() }
        case .poweredOff:
            phase = .bluetoothUnavailable("Turn on Bluetooth to find the ONE Camera nearby.")
        case .unauthorized:
            phase = .bluetoothUnavailable("Allow Bluetooth for ONE in Settings to configure a camera.")
        case .unsupported:
            phase = .bluetoothUnavailable("Bluetooth setup is not available on this device.")
        default:
            phase = .bluetoothUnavailable("Bluetooth is getting ready. Try again in a moment.")
        }
    }

    private func applyStatus(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["phase"] as? String else { return }
        switch status {
        case "joining_wifi": phase = .waitingForNetwork
        case "linking_account": phase = .linkingAccount
        case "paired": phase = .paired
        case "error": phase = .failed((object["detail"] as? String) ?? "The camera could not finish setup.")
        case "ready":
            if phase != .sending && phase != .connecting { phase = .scanning }
        default: break
        }
    }

    private func makeWrites(payload: Data, maxWriteLength: Int) -> [Data] {
        guard payload.count > maxWriteLength else { return [payload] }
        let headerLength = 8
        let chunkLength = max(1, maxWriteLength - headerLength)
        let count = Int(ceil(Double(payload.count) / Double(chunkLength)))
        guard count <= Int(UInt16.max) else { return [] }

        return (0..<count).map { index in
            let lower = index * chunkLength
            let upper = min(lower + chunkLength, payload.count)
            var packet = Data("ONE1".utf8)
            var encodedIndex = UInt16(index).bigEndian
            var encodedCount = UInt16(count).bigEndian
            withUnsafeBytes(of: &encodedIndex) { packet.append(contentsOf: $0) }
            withUnsafeBytes(of: &encodedCount) { packet.append(contentsOf: $0) }
            packet.append(payload[lower..<upper])
            return packet
        }
    }

    private func writeNextProvisionChunk(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard pendingWriteIndex < pendingWrites.count else {
            phase = .waitingForNetwork
            return
        }
        let packet = pendingWrites[pendingWriteIndex]
        pendingWriteIndex += 1
        peripheral.writeValue(packet, for: characteristic, type: .withResponse)
    }
}

extension OneCameraBLEProvisioner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateBluetoothState(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "ONE Camera"
        discovered[peripheral.identifier] = peripheral
        let candidate = NearbyOneCamera(id: peripheral.identifier, name: name, signal: RSSI.intValue)
        if let index = nearby.firstIndex(where: { $0.id == candidate.id }) {
            nearby[index] = candidate
        } else {
            nearby.append(candidate)
        }
        nearby.sort { $0.signal > $1.signal }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        phase = .failed(error?.localizedDescription ?? "ONE could not connect to that camera.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        if phase != .paired, let error {
            phase = .failed(error.localizedDescription)
        }
    }
}

extension OneCameraBLEProvisioner: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { phase = .failed(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            phase = .failed("The nearby device is not exposing the ONE setup service.")
            return
        }
        peripheral.discoverCharacteristics([Self.provisionUUID, Self.statusUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { phase = .failed(error.localizedDescription); return }
        provisionCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.provisionUUID })
        statusCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.statusUUID })
        guard let provision = provisionCharacteristic, let payload = pendingPayload else {
            phase = .failed("The ONE Camera setup channel is incomplete. Restart the camera and try again.")
            return
        }
        if let status = statusCharacteristic { peripheral.setNotifyValue(true, for: status) }
        pendingWrites = makeWrites(
            payload: payload,
            maxWriteLength: peripheral.maximumWriteValueLength(for: .withResponse)
        )
        pendingWriteIndex = 0
        guard !pendingWrites.isEmpty else {
            phase = .failed("The ONE Camera setup details could not be sent over Bluetooth.")
            return
        }
        phase = .sending
        writeNextProvisionChunk(to: peripheral, characteristic: provision)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { phase = .failed(error.localizedDescription) }
        else if let provisionCharacteristic {
            writeNextProvisionChunk(to: peripheral, characteristic: provisionCharacteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { phase = .failed(error.localizedDescription); return }
        if let data = characteristic.value { applyStatus(data) }
    }
}
