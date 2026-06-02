// MARK: - PacketFlowLogger.swift
// NEFilterDataProvider — system-wide TCP/UDP flow logging.
//
// This file lives in a separate App Extension target (not the main app target).
// It runs in its own process and sees every network flow opened by every app
// on the device, including flows that never go through URLSession.
//
// Required entitlements (in the extension's .entitlements file):
//   com.apple.developer.networking.networkextension: ["content-filter-provider"]
//
// Required Info.plist keys (extension's Info.plist):
//   NSExtension > NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).PacketFlowLogger
//   NSExtension > NSExtensionPointIdentifier: com.apple.networkextension.filter-data
//
// Setup in the main app (call once, e.g. in AppDelegate):
//   PacketFlowLogger.activateFilter { error in ... }
//
// What gets logged per flow:
//   • "open"     — when a new TCP connection or UDP session is created:
//                  app bundle ID, source IP:port, dest IP:port, protocol
//   • "outbound" — first chunk of outbound payload bytes (up to 512 bytes base64)
//   • "inbound"  — first chunk of inbound payload bytes (up to 512 bytes base64)
//   • "close"    — when the flow ends: cumulative bytes sent + received
//
// All verdicts are .allow() — this logger never blocks traffic.

import NetworkExtension
import Foundation

public final class PacketFlowLogger: NEFilterDataProvider {

    // Per-flow byte counters, keyed by flow identifier
    private var flowStats = [String: FlowStats]()
    private let statsQueue = DispatchQueue(label: "com.selfsurveillance.flowstats")

    private struct FlowStats {
        var bytesSent: Int64 = 0
        var bytesReceived: Int64 = 0
        var outboundPeeked = false
        var inboundPeeked  = false
    }

    // MARK: - NEFilterDataProvider lifecycle

    override public func startFilter(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    override public func stopFilter(with reason: NEProviderStopReason,
                                    completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - Flow events

    /// Called for every new TCP connection or UDP socket before any data is sent.
    override public func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let key = flow.identifier.uuidString
        statsQueue.sync { flowStats[key] = FlowStats() }

        logFlowEvent(flow, event: "open", bytes: nil, payloadSnippet: nil)

        // Ask the OS to deliver the first 512 bytes of outbound payload so we can
        // log the start of the request (HTTP verb / TLS client-hello / etc.)
        return NEFilterNewFlowVerdict.filterData(peekBytes: 512)
    }

    /// Called with outbound payload bytes (up to peekBytes from handleNewFlow).
    override public func handleOutboundData(
        from flow: NEFilterFlow,
        readBytesStartOffset offset: Int,
        readBytes: Data
    ) -> NEFilterDataVerdict {
        let key = flow.identifier.uuidString
        var snippet: String? = nil

        statsQueue.sync {
            flowStats[key]?.bytesSent += Int64(readBytes.count)
            if flowStats[key]?.outboundPeeked == false {
                flowStats[key]?.outboundPeeked = true
                snippet = readBytes.prefix(256).base64EncodedString()
            }
        }

        logFlowEvent(flow, event: "outbound", bytes: Int64(readBytes.count),
                     payloadSnippet: snippet)
        return NEFilterDataVerdict.allow()
    }

    /// Called with inbound payload bytes.
    override public func handleInboundData(
        from flow: NEFilterFlow,
        readBytesStartOffset offset: Int,
        readBytes: Data
    ) -> NEFilterDataVerdict {
        let key = flow.identifier.uuidString
        var snippet: String? = nil

        statsQueue.sync {
            flowStats[key]?.bytesReceived += Int64(readBytes.count)
            if flowStats[key]?.inboundPeeked == false {
                flowStats[key]?.inboundPeeked = true
                snippet = readBytes.prefix(256).base64EncodedString()
            }
        }

        logFlowEvent(flow, event: "inbound", bytes: Int64(readBytes.count),
                     payloadSnippet: snippet)
        return NEFilterDataVerdict.allow()
    }

    override public func handleOutboundDataComplete(from flow: NEFilterFlow) -> NEFilterDataVerdict {
        logFlowClose(flow)
        return NEFilterDataVerdict.allow()
    }

    override public func handleInboundDataComplete(from flow: NEFilterFlow) -> NEFilterDataVerdict {
        logFlowClose(flow)
        return NEFilterDataVerdict.allow()
    }

    // MARK: - Private helpers

    private func logFlowEvent(_ flow: NEFilterFlow, event: String,
                               bytes: Int64?, payloadSnippet: String?) {
        let (sourceIP, sourcePort, destIP, destPort, proto) = endpoints(from: flow)

        ImmutableLogStore.shared.append(
            source: .packetFlow,
            category: .deviceActivity,
            appBundleID: flow.sourceAppIdentifier,
            eventType: event,
            payload: .packetFlow(PacketFlowPayload(
                event: event,
                proto: proto,
                direction: event == "outbound" ? "out" : (event == "inbound" ? "in" : nil),
                sourceIP: sourceIP,
                sourcePort: sourcePort,
                destIP: destIP,
                destPort: destPort,
                byteCount: bytes,
                totalBytesSent: nil,
                totalBytesReceived: nil,
                appBundleID: flow.sourceAppIdentifier,
                payloadSnippetBase64: payloadSnippet
            ))
        )
    }

    private func logFlowClose(_ flow: NEFilterFlow) {
        let key = flow.identifier.uuidString
        var sent: Int64 = 0
        var received: Int64 = 0

        statsQueue.sync {
            sent     = flowStats[key]?.bytesSent     ?? 0
            received = flowStats[key]?.bytesReceived ?? 0
            flowStats.removeValue(forKey: key)
        }

        let (sourceIP, sourcePort, destIP, destPort, proto) = endpoints(from: flow)

        ImmutableLogStore.shared.append(
            source: .packetFlow,
            category: .deviceActivity,
            appBundleID: flow.sourceAppIdentifier,
            eventType: "close",
            payload: .packetFlow(PacketFlowPayload(
                event: "close",
                proto: proto,
                direction: nil,
                sourceIP: sourceIP,
                sourcePort: sourcePort,
                destIP: destIP,
                destPort: destPort,
                byteCount: nil,
                totalBytesSent: sent,
                totalBytesReceived: received,
                appBundleID: flow.sourceAppIdentifier,
                payloadSnippetBase64: nil
            ))
        )
    }

    private func endpoints(from flow: NEFilterFlow)
        -> (sourceIP: String?, sourcePort: Int?, destIP: String?, destPort: Int?, proto: String?) {
        guard let socketFlow = flow as? NEFilterSocketFlow else {
            return (nil, nil, nil, nil, nil)
        }

        let proto: String?
        switch socketFlow.socketProtocol {
        case IPPROTO_TCP: proto = "TCP"
        case IPPROTO_UDP: proto = "UDP"
        default:          proto = nil
        }

        func parseEndpoint(_ ep: NWEndpoint?) -> (String?, Int?) {
            guard let ep = ep else { return (nil, nil) }
            if case let NWEndpoint.hostPort(host, port) = ep {
                let hostStr: String
                switch host {
                case .name(let name, _):    hostStr = name
                case .ipv4(let addr):       hostStr = "\(addr)"
                case .ipv6(let addr):       hostStr = "\(addr)"
                @unknown default:           hostStr = ep.debugDescription
                }
                return (hostStr, Int(port.rawValue))
            }
            return (ep.debugDescription, nil)
        }

        let (srcIP, srcPort) = parseEndpoint(socketFlow.localEndpoint)
        let (dstIP, dstPort) = parseEndpoint(socketFlow.remoteEndpoint)
        return (srcIP, srcPort, dstIP, dstPort, proto)
    }
}

// MARK: - Main-app helper to activate the content filter

extension PacketFlowLogger {

    /// Call once from the main app to present the system prompt that enables
    /// the content filter.  The user must approve in Settings > VPN & Device Mgmt.
    public static func activateFilter(completion: @escaping (Error?) -> Void) {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            if let error = error {
                completion(error)
                return
            }

            if manager.providerConfiguration == nil {
                let config = NEFilterProviderConfiguration()
                config.username          = UIDevice.current.name
                config.organization      = "SelfSurveillance"
                config.filterBrowsers    = true
                config.filterSockets     = true
                manager.providerConfiguration = config
            }

            manager.isEnabled = true
            manager.saveToPreferences { saveError in
                completion(saveError)
            }
        }
    }
}

import UIKit   // for UIDevice in activateFilter
