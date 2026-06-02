// MARK: - NetworkAndWiFiCollector.swift
// Monitors every aspect of network activity visible to the main app process:
//
//   • NWPathMonitor      — interface state changes (WiFi/cell/ethernet up/down)
//   • NEHotspotNetwork   — current SSID, BSSID, security type (polled every 15s)
//   • getifaddrs if_data — per-interface cumulative byte counters (polled every 15s)
//   • CTTelephonyNetworkInfo — cellular carrier + radio technology (polled every 15s)
//   • NWConnection probe — measures DNS resolution latency (every 60s)
//   • CoreBluetooth      — nearby BT device discovery / connect / disconnect

import NetworkExtension
import Network
import CoreBluetooth
import CoreTelephony
import SystemConfiguration.CaptiveNetwork
import Darwin    // getifaddrs, if_data

public final class NetworkAndWiFiCollector: NSObject, CBCentralManagerDelegate {

    public static let shared = NetworkAndWiFiCollector()

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.selfsurveillance.network.monitor")
    private var centralManager: CBCentralManager?

    private var lastSSID: String?      = nil
    private var lastRadioTech: String? = nil
    private var lastIfaceStats = [String: (ibytes: Int64, obytes: Int64)]()

    private let telephony = CTTelephonyNetworkInfo()
    private var pollTimer: Timer?
    private var dnsTimer: Timer?

    private static let dnsProbeHostnames = ["google.com", "apple.com", "amazon.com", "cloudflare.com"]
    private var dnsProbeIndex = 0

    private override init() { super.init() }

    // MARK: - Start / Stop

    public func start() {
        startNetworkPathMonitor()
        startBluetoothScanning()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.captureWiFiState()
            self?.captureInterfaceStats()
            self?.captureCellularInfo()
        }

        dnsTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.probeDNS()
        }

        captureWiFiState()
        captureInterfaceStats()
        captureCellularInfo()
    }

    public func stop() {
        pathMonitor?.cancel()
        pollTimer?.invalidate()
        dnsTimer?.invalidate()
    }

    // MARK: - NWPathMonitor (interface up/down events)

    private func startNetworkPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in self?.logNetworkPath(path) }
        monitor.start(queue: monitorQueue)
    }

    private func logNetworkPath(_ path: NWPath) {
        var interfaces: [String] = []
        if path.usesInterfaceType(.wifi)          { interfaces.append("wifi") }
        if path.usesInterfaceType(.cellular)      { interfaces.append("cellular") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("ethernet") }
        if path.usesInterfaceType(.loopback)      { interfaces.append("loopback") }

        let statusStr: String
        switch path.status {
        case .satisfied:          statusStr = "connected"
        case .unsatisfied:        statusStr = "disconnected"
        case .requiresConnection: statusStr = "requiresConnection"
        @unknown default:         statusStr = "unknown"
        }

        ImmutableLogStore.shared.append(
            source: .network,
            category: .deviceActivity,
            eventType: "pathChanged",
            payload: .networkRequest(NetworkRequestPayload(
                eventType: "pathChanged",
                sourceApp: nil, url: nil, domain: nil, httpMethod: nil,
                statusCode: nil, bytesSent: nil, bytesReceived: nil,
                isEncrypted: nil,
                certificateInfo: "status=\(statusStr) interfaces=[\(interfaces.joined(separator: ","))]"
            ))
        )
    }

    // MARK: - WiFi SSID polling

    private func captureWiFiState() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let ssid     = network?.ssid
            let bssid    = network?.bssid
            let isSecure = network?.isSecure ?? false

            guard ssid != self?.lastSSID else { return }
            self?.lastSSID = ssid

            let eventType = ssid != nil ? "connected" : "disconnected"
            ImmutableLogStore.shared.append(
                source: .wifi,
                category: .deviceActivity,
                eventType: eventType,
                payload: .wifiEvent(WiFiEventPayload(
                    eventType: eventType,
                    ssid: ssid,
                    bssid: bssid,
                    rssi: nil,
                    securityType: isSecure ? "secured" : "open",
                    frequency: nil,
                    ipAddress: self?.currentIPAddress()
                ))
            )
        }
    }

    // MARK: - Per-interface byte counters
    // Reads the cumulative ifi_ibytes / ifi_obytes from the kernel via getifaddrs.
    // Emits a log entry only when the delta since the last poll is > 0.

    private func captureInterfaceStats() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            // AF_LINK entries carry the if_data struct
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = current.pointee.ifa_data else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }   // skip loopback

            let ifdata  = dataPtr.load(as: if_data.self)
            let ibytes  = Int64(ifdata.ifi_ibytes)
            let obytes  = Int64(ifdata.ifi_obytes)
            let prev    = lastIfaceStats[name]
            let deltaIn = ibytes - (prev?.ibytes ?? ibytes)
            let deltaOut = obytes - (prev?.obytes ?? obytes)
            lastIfaceStats[name] = (ibytes, obytes)

            guard deltaIn > 0 || deltaOut > 0 else { continue }

            ImmutableLogStore.shared.append(
                source: .network,
                category: .deviceActivity,
                eventType: "interfaceStats",
                payload: .networkRequest(NetworkRequestPayload(
                    eventType: "interfaceStats",
                    sourceApp: nil,
                    url: nil,
                    domain: nil,
                    httpMethod: nil,
                    statusCode: nil,
                    bytesSent: deltaOut,
                    bytesReceived: deltaIn,
                    isEncrypted: nil,
                    certificateInfo: "iface=\(name) totalIn=\(ibytes) totalOut=\(obytes)"
                ))
            )
        }
    }

    // MARK: - Cellular carrier + radio technology

    private func captureCellularInfo() {
        guard let providers = telephony.serviceSubscriberCellularProviders,
              !providers.isEmpty else { return }

        let carrier    = providers.values.first
        let radioTechs = telephony.serviceCurrentRadioAccessTechnology ?? [:]
        let radioTech  = radioTechs.values.first ?? "unknown"

        guard radioTech != lastRadioTech else { return }
        lastRadioTech = radioTech

        let carrierName = carrier?.carrierName ?? "unknown"
        let mcc = carrier?.mobileCountryCode ?? ""
        let mnc = carrier?.mobileNetworkCode ?? ""

        ImmutableLogStore.shared.append(
            source: .network,
            category: .deviceActivity,
            eventType: "cellularInfo",
            payload: .networkRequest(NetworkRequestPayload(
                eventType: "cellularInfo",
                sourceApp: nil,
                url: nil,
                domain: nil,
                httpMethod: nil,
                statusCode: nil,
                bytesSent: nil,
                bytesReceived: nil,
                isEncrypted: nil,
                certificateInfo: "carrier=\(carrierName) mcc=\(mcc) mnc=\(mnc) radioTech=\(radioTech)"
            ))
        )
    }

    // MARK: - DNS probe (resolution latency)
    // Measures time from NWConnection creation to the .ready state, which includes
    // DNS lookup + TCP handshake to port 443.  Rotates through a list of hostnames.

    private func probeDNS() {
        let hostname = Self.dnsProbeHostnames[dnsProbeIndex % Self.dnsProbeHostnames.count]
        dnsProbeIndex += 1
        let start = Date()

        let conn = NWConnection(
            to: NWEndpoint.hostPort(host: NWEndpoint.Host(hostname), port: 443),
            using: NWParameters.tcp
        )

        conn.stateUpdateHandler = { [weak conn] state in
            switch state {
            case .ready:
                let ms = Date().timeIntervalSince(start) * 1000
                ImmutableLogStore.shared.append(
                    source: .dnsQuery,
                    category: .deviceActivity,
                    eventType: "dnsProbe",
                    payload: .dnsQuery(DNSQueryPayload(
                        hostname: hostname,
                        queryType: "A",
                        resolvedAddresses: nil,
                        responseTimeMs: ms,
                        ttl: nil,
                        sourceApp: Bundle.main.bundleIdentifier,
                        error: nil
                    ))
                )
                conn?.cancel()

            case .failed(let err):
                let ms = Date().timeIntervalSince(start) * 1000
                ImmutableLogStore.shared.append(
                    source: .dnsQuery,
                    category: .deviceActivity,
                    eventType: "dnsProbe",
                    payload: .dnsQuery(DNSQueryPayload(
                        hostname: hostname,
                        queryType: "A",
                        resolvedAddresses: nil,
                        responseTimeMs: ms,
                        ttl: nil,
                        sourceApp: Bundle.main.bundleIdentifier,
                        error: err.localizedDescription
                    ))
                )
                conn?.cancel()

            default: break
            }
        }
        conn.start(queue: monitorQueue)
    }

    // MARK: - Bluetooth scanning

    private func startBluetoothScanning() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    public func centralManager(_ central: CBCentralManager,
                                didDiscover peripheral: CBPeripheral,
                                advertisementData: [String: Any],
                                rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString }

        ImmutableLogStore.shared.append(
            source: .bluetooth,
            category: .deviceActivity,
            eventType: "discovered",
            payload: .bluetoothEvent(BluetoothEventPayload(
                eventType: "discovered",
                deviceName: name,
                deviceAddress: peripheral.identifier.uuidString,
                deviceClass: classifyBluetooth(serviceUUIDs: serviceUUIDs),
                rssi: RSSI.intValue,
                serviceUUIDs: serviceUUIDs,
                pairingLatencySeconds: nil
            ))
        )
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        ImmutableLogStore.shared.append(
            source: .bluetooth,
            category: .deviceActivity,
            eventType: "connected",
            payload: .bluetoothEvent(BluetoothEventPayload(
                eventType: "connected",
                deviceName: peripheral.name,
                deviceAddress: peripheral.identifier.uuidString,
                deviceClass: nil, rssi: nil, serviceUUIDs: nil, pairingLatencySeconds: nil
            ))
        )
    }

    public func centralManager(_ central: CBCentralManager,
                                didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ImmutableLogStore.shared.append(
            source: .bluetooth,
            category: .deviceActivity,
            eventType: "disconnected",
            payload: .bluetoothEvent(BluetoothEventPayload(
                eventType: "disconnected",
                deviceName: peripheral.name,
                deviceAddress: peripheral.identifier.uuidString,
                deviceClass: nil, rssi: nil, serviceUUIDs: nil, pairingLatencySeconds: nil
            ))
        )
    }

    // MARK: - Helpers

    private func currentIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let family = current.pointee.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            guard String(cString: current.pointee.ifa_name) == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(current.pointee.ifa_addr,
                        socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }

    private func classifyBluetooth(serviceUUIDs: [String]?) -> String? {
        let known: [String: String] = [
            "110B": "audioSink", "110A": "audioSource",
            "1812": "hid",       "180D": "heartRate",
            "1800": "genericAccess", "180F": "batteryService",
            "FE9A": "airpods",   "FD5A": "appleWatch",
        ]
        guard let uuids = serviceUUIDs else { return nil }
        for uuid in uuids {
            let short = uuid.components(separatedBy: "-").first?.uppercased() ?? ""
            if let cls = known[short] { return cls }
        }
        return nil
    }
}
