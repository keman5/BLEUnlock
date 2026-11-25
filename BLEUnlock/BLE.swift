import Foundation
import CoreBluetooth
import Accelerate

private let GenericAccess = CBUUID(string:"1800")
private let DeviceName = CBUUID(string:"2A00")
private let DeviceInformation = CBUUID(string:"180A")
private let ManufacturerName = CBUUID(string:"2A29")
private let ModelName = CBUUID(string:"2A24")
private let SerialNumber = CBUUID(string:"2A25")
private let InformationServices = [GenericAccess: [DeviceName],
                                   DeviceInformation: [ManufacturerName, ModelName, SerialNumber]]
let ExposureNotification = CBUUID(string:"FD6F")

func getMACFromUUID(_ uuid: String) -> String? {
    guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") else { return nil }
    guard let cbcache = plist["CoreBluetoothCache"] as? NSDictionary else { return nil }
    guard let device = cbcache[uuid] as? NSDictionary else { return nil }
    return device["DeviceAddress"] as? String
}

func getNameFromMAC(_ mac: String) -> String? {
    guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist") else { return nil }
    guard let devcache = plist["DeviceCache"] as? NSDictionary else { return nil }
    guard let device = devcache[mac] as? NSDictionary else { return nil }
    if let name = device["Name"] as? String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed == "" { return nil }
        return trimmed
    }
    return nil
}

class Device: NSObject {
    let uuid: UUID
    var peripheral : CBPeripheral?
    var manufacture : String?
    var model : String?
    var deviceName: String?
    var advertisedName: String?
    var serialNumber: String?
    var advData: Data?
    var rssi: Int = 0
    var scanTimer: Timer?
    var informationTimer: Timer?
    var pendingServices: Set<CBUUID> = []
    var pendingCharacteristics: Set<CBUUID> = []
    var macAddr: String?
    var blName: String?

    func refreshCachedInfo() {
        let info = getLEDeviceInfoFromUUID(uuid.uuidString)
        macAddr = info?.macAddr ?? getMACFromUUID(uuid.uuidString) ?? macAddr
        blName = info?.name ?? macAddr.flatMap(getNameFromMAC) ?? blName
    }
    
    override var description: String {
        if let deviceName = deviceName {
            return deviceName
        }
        let names = [blName, peripheral?.name, advertisedName].compactMap { $0?.bluetoothInformation }
        // Apple devices can advertise a generic product name in place of their configured name.
        if let name = names.first(where: { $0 != "iPhone" && $0 != "iPad" && $0 != "Apple Watch" }) {
            return name
        }
        if let model = model {
            if let manufacture = manufacture {
                if manufacture == "Apple Inc.", let appleName = appleDeviceNames[model] {
                    return appleName
                }
                return "\(manufacture)/\(model)"
            }
            return model
        }
        if let name = names.first ?? manufacture {
            return name
        }
        if let adv = advData, adv.count >= 25 {
            var iBeaconPrefix: [UInt16] = [0x004c, 0x1502]
            if adv[0...3] == Data(bytes: &iBeaconPrefix, count: 4) {
                let major = UInt16(adv[20]) << 8 | UInt16(adv[21])
                let minor = UInt16(adv[22]) << 8 | UInt16(adv[23])
                let tx = Int8(bitPattern: adv[24])
                let distance = pow(10, Double(Int(tx) - rssi) / 20.0)
                let formattedDistance = String(format: "%.1f", distance)
                return "iBeacon [\(major), \(minor)] \(formattedDistance)m"
            }
        }
        return macAddr ?? uuid.uuidString
    }

    init(uuid _uuid: UUID) {
        uuid = _uuid
    }
}

private extension String {
    var bluetoothInformation: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol BLEDelegate {
    func deviceListDidChange()
    func updateRSSI(rssi: Int?, active: Bool)
    func updatePresence(presence: Bool, reason: String)
    func bluetoothPowerWarn()
}

class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let UNLOCK_DISABLED = 1
    let LOCK_DISABLED = -100
    var centralMgr : CBCentralManager!
    var devices : [UUID : Device] = [:]
    var delegate: BLEDelegate?
    var scanMode = false
    var monitoredUUID: UUID?
    var monitoredPeripheral: CBPeripheral?
    var proximityTimer : Timer?
    var signalTimer: Timer?
    var presence = false
    var lockRSSI = -80
    var unlockRSSI = -60
    var proximityTimeout = 5.0
    var signalTimeout = 60.0
    var lastReadAt = 0.0
    var powerWarn = true
    var passiveMode = false
    var thresholdRSSI = -70
    var latestRSSIs: [Double] = []
    var latestN: Int = 5
    var activeModeTimer : Timer? = nil
    var connectionTimer : Timer? = nil

    func scanForPeripherals() {
        guard centralMgr.state == .poweredOn, !centralMgr.isScanning else { return }
        centralMgr.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        //print("Start scanning")
    }

    func startScanning() {
        scanMode = true
        scanForPeripherals()
    }

    func stopScanning() {
        scanMode = false
        if activeModeTimer != nil {
            centralMgr.stopScan()
        }
    }

    func setPassiveMode(_ mode: Bool) {
        passiveMode = mode
        if passiveMode {
            activeModeTimer?.invalidate()
            activeModeTimer = nil
            if let p = monitoredPeripheral {
                centralMgr.cancelPeripheralConnection(p)
            }
        }
        scanForPeripherals()
    }

    func startMonitor(uuid: UUID) {
        if let p = monitoredPeripheral {
            centralMgr.cancelPeripheralConnection(p)
        }
        monitoredUUID = uuid
        proximityTimer?.invalidate()
        resetSignalTimer()
        presence = true
        monitoredPeripheral = nil
        activeModeTimer?.invalidate()
        activeModeTimer = nil
        scanForPeripherals()
    }

    func resetSignalTimer() {
        signalTimer?.invalidate()
        signalTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { _ in
            print("Device is lost")
            self.delegate?.updateRSSI(rssi: nil, active: false)
            if self.presence {
                self.presence = false
                self.delegate?.updatePresence(presence: self.presence, reason: "lost")
            }
        })
        if let timer = signalTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on")
            if activeModeTimer == nil {
                scanForPeripherals()
            }
            powerWarn = false
        case .poweredOff:
            print("Bluetooth powered off")
            presence = false
            signalTimer?.invalidate()
            signalTimer = nil
            if powerWarn {
                powerWarn = false
                delegate?.bluetoothPowerWarn()
            }
        default:
            break
        }
    }
    
    func getEstimatedRSSI(rssi: Int) -> Int {
        if latestRSSIs.count >= latestN {
            latestRSSIs.removeFirst()
        }
        latestRSSIs.append(Double(rssi))
        var mean: Double = 0.0
        var sddev: Double = 0.0
        vDSP_normalizeD(latestRSSIs, 1, nil, 1, &mean, &sddev, vDSP_Length(latestRSSIs.count))
        return Int(mean)
    }

    func updateMonitoredPeripheral(_ rssi: Int) {
        // print(String(format: "rssi: %d", rssi))
        if rssi >= (unlockRSSI == UNLOCK_DISABLED ? lockRSSI : unlockRSSI) && !presence {
            print("Device is close")
            presence = true
            delegate?.updatePresence(presence: presence, reason: "close")
            latestRSSIs.removeAll() // Avoid bouncing
        }

        let estimatedRSSI = getEstimatedRSSI(rssi: rssi)
        delegate?.updateRSSI(rssi: estimatedRSSI, active: activeModeTimer != nil)

        if estimatedRSSI >= (lockRSSI == LOCK_DISABLED ? unlockRSSI : lockRSSI) {
            if let timer = proximityTimer {
                timer.invalidate()
                print("Proximity timer canceled")
                proximityTimer = nil
            }
        } else if presence && proximityTimer == nil {
            proximityTimer = Timer.scheduledTimer(withTimeInterval: proximityTimeout, repeats: false, block: { _ in
                print("Device is away")
                self.presence = false
                self.delegate?.updatePresence(presence: self.presence, reason: "away")
                self.proximityTimer = nil
            })
            RunLoop.main.add(proximityTimer!, forMode: .common)
            print("Proximity timer started")
        }
        resetSignalTimer()
    }

    func resetScanTimer(device: Device) {
        device.scanTimer?.invalidate()
        device.scanTimer = Timer.scheduledTimer(withTimeInterval: signalTimeout, repeats: false, block: { [weak device] _ in
            guard let device = device else { return }
            self.finishDeviceInformation(device)
            self.devices.removeValue(forKey: device.uuid)
            self.delegate?.deviceListDidChange()
        })
        if let timer = device.scanTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func startDeviceInformation(_ device: Device, peripheral: CBPeripheral) {
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self, weak device] _ in
            if let device = device {
                self?.finishDeviceInformation(device)
            }
        }
        device.informationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        peripheral.delegate = self
        if peripheral.state == .connected {
            peripheral.discoverServices(Array(InformationServices.keys))
        } else if peripheral.state == .disconnected {
            centralMgr.connect(peripheral, options: nil)
        }
    }

    private func finishDeviceInformation(_ device: Device) {
        guard let timer = device.informationTimer else { return }
        timer.invalidate()
        device.informationTimer = nil
        device.pendingServices.removeAll()
        device.pendingCharacteristics.removeAll()
        if let peripheral = device.peripheral, device.uuid != monitoredUUID || passiveMode {
            centralMgr.cancelPeripheralConnection(peripheral)
        }
    }

    func connectMonitoredPeripheral() {
        guard let p = monitoredPeripheral else { return }

        // Idk why but this works like a charm when 'didConnect' won't get called.
        // However, this generates warnings in the log.
        p.readRSSI()

        guard p.state == .disconnected else { return }
        print("Connecting")
        centralMgr.connect(p, options: nil)
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false, block: { _ in
            if p.state == .connecting {
                print("Connection timeout")
                self.centralMgr.cancelPeripheralConnection(p)
            }
        })
        RunLoop.main.add(connectionTimer!, forMode: .common)
    }

    //MARK:- CBCentralManagerDelegate start

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber)
    {
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        if let uuid = monitoredUUID {
            if peripheral.identifier.description == uuid.description {
                if monitoredPeripheral == nil {
                    monitoredPeripheral = peripheral
                }
                if activeModeTimer == nil {
                    //print("Discover \(rssi)dBm")
                    updateMonitoredPeripheral(rssi)
                    if !passiveMode {
                        connectMonitoredPeripheral()
                    }
                }
            }
        }

        guard scanMode else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        guard services?.contains(ExposureNotification) != true else { return }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if let device = devices[peripheral.identifier] {
            device.rssi = rssi
            device.advertisedName = advertisedName?.bluetoothInformation ?? device.advertisedName
            resetScanTimer(device: device)
            delegate?.deviceListDidChange()
            return
        }
        guard rssi >= thresholdRSSI else { return }
        let device = Device(uuid: peripheral.identifier)
        device.peripheral = peripheral
        device.rssi = rssi
        device.advertisedName = advertisedName?.bluetoothInformation
        device.advData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        device.refreshCachedInfo()
        devices[device.uuid] = device
        resetScanTimer(device: device)
        if (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) != false {
            startDeviceInformation(device, peripheral: peripheral)
        }
        delegate?.deviceListDidChange()
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral)
    {
        peripheral.delegate = self
        if let device = devices[peripheral.identifier], device.informationTimer != nil {
            device.refreshCachedInfo()
            delegate?.deviceListDidChange()
            peripheral.discoverServices(Array(InformationServices.keys))
        }
        if peripheral == monitoredPeripheral && !passiveMode {
            print("Connected")
            connectionTimer?.invalidate()
            connectionTimer = nil
            peripheral.readRSSI()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let device = devices[peripheral.identifier] {
            finishDeviceInformation(device)
        }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        if let device = devices[peripheral.identifier] {
            device.refreshCachedInfo()
            delegate?.deviceListDidChange()
        }
    }

    //MARK:CBCentralManagerDelegate end -
    
    //MARK:- CBPeripheralDelegate start

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral == monitoredPeripheral else { return }
        let rssi = RSSI.intValue > 0 ? 0 : RSSI.intValue
        //print("readRSSI \(rssi)dBm")
        updateMonitoredPeripheral(rssi)
        lastReadAt = Date().timeIntervalSince1970

        if activeModeTimer == nil && !passiveMode {
            print("Entering active mode")
            if !scanMode {
                centralMgr.stopScan()
            }
            activeModeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true, block: { _ in
                if Date().timeIntervalSince1970 > self.lastReadAt + 10 {
                    print("Falling back to passive mode")
                    self.centralMgr.cancelPeripheralConnection(peripheral)
                    self.activeModeTimer?.invalidate()
                    self.activeModeTimer = nil
                    self.scanForPeripherals()
                } else if peripheral.state == .connected {
                    peripheral.readRSSI()
                } else {
                    self.connectMonitoredPeripheral()
                }
            })
            RunLoop.main.add(activeModeTimer!, forMode: .common)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard let device = devices[peripheral.identifier], device.informationTimer != nil else { return }
        let services = error == nil ? peripheral.services ?? [] : []
        for service in services {
            if let characteristics = InformationServices[service.uuid] {
                device.pendingServices.insert(service.uuid)
                peripheral.discoverCharacteristics(characteristics, for: service)
            }
        }
        finishDeviceInformationIfReady(device)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?)
    {
        guard let device = devices[peripheral.identifier], device.informationTimer != nil,
              device.pendingServices.remove(service.uuid) != nil else { return }
        let characteristics = error == nil ? service.characteristics ?? [] : []
        let requested = InformationServices[service.uuid] ?? []
        for characteristic in characteristics where requested.contains(characteristic.uuid) && characteristic.properties.contains(.read) {
            device.pendingCharacteristics.insert(characteristic.uuid)
            peripheral.readValue(for: characteristic)
        }
        finishDeviceInformationIfReady(device)
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        guard let device = devices[peripheral.identifier], device.informationTimer != nil,
              device.pendingCharacteristics.remove(characteristic.uuid) != nil else { return }
        if error == nil, let value = characteristic.value,
           let text = String(data: value, encoding: .utf8)?.bluetoothInformation {
            switch characteristic.uuid {
            case DeviceName: device.deviceName = text
            case ManufacturerName: device.manufacture = text
            case ModelName: device.model = text
            case SerialNumber: device.serialNumber = text
            default: break
            }
            delegate?.deviceListDidChange()
        }
        finishDeviceInformationIfReady(device)
    }

    private func finishDeviceInformationIfReady(_ device: Device) {
        if device.pendingServices.isEmpty && device.pendingCharacteristics.isEmpty {
            finishDeviceInformation(device)
        }
    }
    //MARK:CBPeripheralDelegate end -

    override init() {
        super.init()
        centralMgr = CBCentralManager(delegate: self, queue: nil)
    }
}
