import Foundation

enum HTTPError: Error, CustomStringConvertible {
    case badStatus(Int)
    case decoding
    case transport(Error)

    var description: String {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .decoding: return "decoding failed"
        case .transport(let e):    return "transport: \(e.localizedDescription)"
        }
    }
}

/// 极简 HTTPClient,负责构造请求 + 注入通用 header + 解码。
struct HTTPClient {
    let session: URLSession
    let defaultHeaders: [String: String]

    init(session: URLSession = .shared, defaultHeaders: [String: String] = [:]) {
        self.session = session
        var headers = defaultHeaders
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = Self.defaultUA
        }
        self.defaultHeaders = headers
    }

    static let defaultUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15 PanBar/0.1"

    func fetchData(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 8) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in headers        { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HTTPError.badStatus(http.statusCode)
            }
            return data
        } catch let e as HTTPError {
            throw e
        } catch {
            throw HTTPError.transport(error)
        }
    }

    func fetchString(url: URL, encoding: String.Encoding = .utf8, headers: [String: String] = [:]) async throws -> String {
        let data = try await fetchData(url: url, headers: headers)
        if encoding == .utf8 {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return GBKDecoder.decode(data) ?? String(data: data, encoding: .utf8) ?? ""
    }
}
