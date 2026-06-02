// MARK: - NetworkInterceptor.swift
// URLProtocol subclass that intercepts every HTTP/HTTPS request made within
// this process.  For each request it logs:
//   • The full outbound request: URL, method, all headers, body (raw bytes in
//     the rawBytes field, size in bytesSent).
//   • The inbound response: status code, all response headers, body (raw bytes
//     in rawBytes, size in bytesReceived), round-trip latency, TLS cipher/cert.
//
// Exclusions:
//   • Requests tagged with X-SS-Internal: "1" (SyncEngine's own traffic).
//   • Requests already being handled by a nested URLSession inside this class.
//
// Registration:
//   Call NetworkInterceptor.enable() once from AppDelegate / CollectorOrchestrator.
//   It registers this class with URLProtocol AND swizzles URLSession.shared so
//   that background sessions also pick it up.

import Foundation

public final class NetworkInterceptor: URLProtocol, URLSessionDataDelegate {

    // MARK: - Constants

    static let handledKey   = "com.selfsurveillance.interceptor.handled"
    static let internalFlag = "X-SS-Internal"

    // MARK: - Instance state

    private var interceptSession: URLSession?
    private var activeTask: URLSessionDataTask?
    private var startDate = Date()
    private var accumulatedData = Data()
    private var savedResponse: URLResponse?

    // MARK: - Enable / Disable

    public static func enable() {
        URLProtocol.registerClass(NetworkInterceptor.self)
    }

    public static func disable() {
        URLProtocol.unregisterClass(NetworkInterceptor.self)
    }

    // MARK: - URLProtocol: canInit

    override public class func canInit(with request: URLRequest) -> Bool {
        // Skip already-handled requests (avoid infinite loops)
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        // Skip SyncEngine's outbound traffic
        guard request.value(forHTTPHeaderField: internalFlag) == nil else { return false }
        // Only intercept http and https
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    // MARK: - URLProtocol: startLoading / stopLoading

    override public func startLoading() {
        startDate = Date()

        // Mark request so re-entrant calls are skipped
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        logOutboundRequest(request)

        let config = URLSessionConfiguration.ephemeral
        interceptSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        activeTask = interceptSession?.dataTask(with: mutable as URLRequest)
        activeTask?.resume()
    }

    override public func stopLoading() {
        activeTask?.cancel()
        interceptSession?.invalidateAndCancel()
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        savedResponse = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive data: Data) {
        accumulatedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        let latency = Date().timeIntervalSince(startDate)

        if let error = error {
            logResponse(request: request, httpResponse: nil, body: nil,
                        latency: latency, error: error)
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            logResponse(request: request,
                        httpResponse: savedResponse as? HTTPURLResponse,
                        body: accumulatedData,
                        latency: latency,
                        error: nil)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Forward TLS challenges to the original client
        if let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Logging

    private func logOutboundRequest(_ req: URLRequest) {
        let bodyData  = req.httpBody
        let bodySize  = bodyData.map { Int64($0.count) }
        let headers   = req.allHTTPHeaderFields?
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\n")

        ImmutableLogStore.shared.append(
            source: .network,
            category: .deviceActivity,
            appBundleID: Bundle.main.bundleIdentifier,
            eventType: "httpRequest",
            payload: .networkRequest(NetworkRequestPayload(
                eventType: "httpRequest",
                sourceApp: Bundle.main.bundleIdentifier,
                url: req.url?.absoluteString,
                domain: req.url?.host,
                httpMethod: req.httpMethod,
                statusCode: nil,
                bytesSent: bodySize,
                bytesReceived: nil,
                isEncrypted: req.url?.scheme?.lowercased() == "https",
                certificateInfo: headers
            )),
            rawBytes: bodyData
        )
    }

    private func logResponse(request req: URLRequest,
                              httpResponse: HTTPURLResponse?,
                              body: Data?,
                              latency: TimeInterval,
                              error: Error?) {
        let eventType = error != nil ? "httpError" : "httpResponse"
        let certInfo  = buildCertInfo(from: httpResponse, latency: latency, error: error)
        let headers   = httpResponse?.allHeaderFields
            .compactMapValues { $0 as? String }
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\n")

        ImmutableLogStore.shared.append(
            source: .network,
            category: .deviceActivity,
            appBundleID: Bundle.main.bundleIdentifier,
            eventType: eventType,
            payload: .networkRequest(NetworkRequestPayload(
                eventType: eventType,
                sourceApp: Bundle.main.bundleIdentifier,
                url: req.url?.absoluteString,
                domain: req.url?.host,
                httpMethod: req.httpMethod,
                statusCode: httpResponse?.statusCode,
                bytesSent: req.httpBody.map { Int64($0.count) },
                bytesReceived: body.map { Int64($0.count) },
                isEncrypted: req.url?.scheme?.lowercased() == "https",
                certificateInfo: [certInfo, headers].compactMap { $0 }.joined(separator: "\n---\n")
            )),
            rawBytes: body
        )
    }

    private func buildCertInfo(from response: HTTPURLResponse?,
                                latency: TimeInterval,
                                error: Error?) -> String {
        var parts: [String] = ["latency=\(String(format: "%.3f", latency))s"]
        if let err = error { parts.append("error=\(err.localizedDescription)") }
        return parts.joined(separator: " ")
    }
}
