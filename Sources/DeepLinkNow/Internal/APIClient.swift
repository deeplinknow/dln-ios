import Foundation

/// HTTP client for `/api/v1/sdk/*` (SDK-01/02/52/53/55, IOS-05/06).
struct APIClient {
    static let defaultBaseUrl = "https://deeplinknow.com"
    static let defaultTimeout: TimeInterval = 10
    static let defaultRetryAttempts = 2
    /// SDK-53 / IOS-06: `retryAttempts` is clamped to 0...maxRetryAttempts.
    static let maxRetryAttempts = 5
    /// SDK-53: no single backoff delay (exponential or Retry-After) exceeds this.
    static let maxRetryDelay: TimeInterval = 5

    let baseUrl: String
    let apiKey: String
    let timeout: TimeInterval
    let retryAttempts: Int
    let session: URLSessionProtocol
    let logger: Logger
    /// Multiplier for backoff delays (tests set 0).
    let delayScale: Double

    /// Validates and normalizes the config. Throws `.invalidConfiguration` instead of crashing.
    init(config: DLNConfig, session: URLSessionProtocol, logger: Logger, delayScale: Double) throws {
        var base = (config.baseUrl ?? Self.defaultBaseUrl).trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.query == nil, components.fragment == nil else {
            throw DeepLinkNowError(.invalidConfiguration, message: "baseUrl is not a valid absolute URL")
        }
        let devHosts: Set<String> = ["localhost", "127.0.0.1", "10.0.2.2", "::1"]
        guard scheme == "https" || (scheme == "http" && devHosts.contains(host.lowercased())) else {
            throw DeepLinkNowError(.invalidConfiguration, message: "baseUrl must use https (http is allowed only for localhost)")
        }
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepLinkNowError(.invalidConfiguration, message: "apiKey is empty")
        }
        self.baseUrl = base
        self.apiKey = config.apiKey
        self.timeout = (config.timeout ?? 0) > 0 ? config.timeout! : Self.defaultTimeout
        self.retryAttempts = min(max(0, config.retryAttempts ?? Self.defaultRetryAttempts), Self.maxRetryAttempts)
        self.session = session
        self.logger = logger
        self.delayScale = delayScale
    }

    func url(for endpoint: String) throws -> URL {
        guard let url = URL(string: "\(baseUrl)/api/v1/sdk/\(endpoint)") else {
            throw DeepLinkNowError(.invalidConfiguration, message: "Could not build URL for \(endpoint)")
        }
        return url
    }

    /// POSTs a JSON body, retrying transient failures, and returns the 2xx body.
    func post(_ endpoint: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: try url(for: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = timeout
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw DeepLinkNowError(.invalidConfiguration, message: "Request body is not valid JSON", underlying: error)
        }

        var attempt = 0
        while true {
            do {
                return try await send(request, endpoint: endpoint)
            } catch let error as Failure {
                guard error.error.isTransient, attempt < retryAttempts else { throw error.error }
                let delay = Self.backoff(attempt: attempt, retryAfter: error.retryAfter, delayScale: delayScale)
                logger.debug("\(endpoint) failed (\(error.error.code.rawValue)); retry \(attempt + 1)/\(retryAttempts) in \(String(format: "%.2f", delay))s")
                attempt += 1
                let nanoseconds = Self.sleepNanoseconds(delay)
                if nanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                }
            }
        }
    }

    private struct Failure: Error {
        let error: DeepLinkNowError
        let retryAfter: TimeInterval?
    }

    /// SDK-53: 0.5 s, 1 s, 2 s, 4 s, then 5 s; a finite `Retry-After` replaces it. Every delay
    /// is capped at `maxRetryDelay`.
    static func backoff(attempt: Int, retryAfter: TimeInterval?, delayScale: Double) -> TimeInterval {
        let exponential = 0.5 * pow(2.0, Double(min(max(attempt, 0), 16)))
        let requested = retryAfter.flatMap { $0.isFinite ? max($0, 0) : nil } ?? exponential
        return min(requested, maxRetryDelay) * delayScale
    }

    /// Converts a delay for `Task.sleep` without trapping on NaN, infinity or huge values.
    static func sleepNanoseconds(_ delay: TimeInterval) -> UInt64 {
        guard delay.isFinite, delay > 0 else { return 0 }
        return UInt64(min(delay, maxRetryDelay) * 1_000_000_000)
    }

    private func send(_ request: URLRequest, endpoint: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure(error: DeepLinkNowError(.network, message: (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? "Transport error", underlying: error),
                          retryAfter: nil)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Failure(error: DeepLinkNowError(.invalidResponse, message: "Not an HTTP response"), retryAfter: nil)
        }
        if (200...299).contains(http.statusCode) {
            return data
        }
        let message = Self.errorMessage(from: data)
        logger.debug("\(endpoint) returned HTTP \(http.statusCode)\(message.map { ": \($0)" } ?? "")")
        let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
        throw Failure(error: Self.error(forStatus: http.statusCode, message: message), retryAfter: retryAfter)
    }

    /// SDK-55 mapping.
    static func error(forStatus status: Int, message: String?) -> DeepLinkNowError {
        let code: DeepLinkNowError.Code
        switch status {
        case 400: code = .badRequest
        case 401: code = .invalidApiKey
        case 403:
            code = (message?.lowercased().contains("credit") ?? false) ? .noCredits : .accountInactive
        case 429: code = .rateLimited
        case 500...599: code = .server
        default: code = .badRequest
        }
        return DeepLinkNowError(code, statusCode: status, message: message)
    }

    /// Reads `error` (or `message`) from a JSON error body. Non-JSON bodies yield nil.
    static func errorMessage(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (object["error"] as? String) ?? (object["message"] as? String)
    }
}
