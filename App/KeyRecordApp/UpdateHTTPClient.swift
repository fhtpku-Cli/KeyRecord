import Foundation

final class UpdateHTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    static let endpoint = URL(string: "https://api.github.com/repos/fhtpku-Cli/KeyRecord/releases/latest")!
    static let releasePrefix = "https://github.com/fhtpku-Cli/KeyRecord/releases/tag/"
    static let maximumBytes = 262_144

    static func fetch(protocolClasses: [AnyClass] = []) async throws -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        let delegate = UpdateHTTPClient()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("KeyRecord-update-check", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (bytes, rawResponse) = try await session.bytes(for: request)
        guard let response = rawResponse as? HTTPURLResponse, response.url == endpoint else { throw UpdateHTTPError.response }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, response.expectedContentLength <= maximumBytes,
              response.mimeType == "application/json" else { throw UpdateHTTPError.response }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw UpdateHTTPError.tooLarge }
            data.append(byte)
        }
        return data
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

enum UpdateHTTPError: Error { case response, tooLarge }
