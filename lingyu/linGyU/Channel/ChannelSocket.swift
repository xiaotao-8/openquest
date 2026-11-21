import Foundation

/// One WebSocket: text send/receive, close with a code. No protocol knowledge.
/// The 1 MiB message cap matches the host's WS limit.
struct SocketClosed: Error {
    let code: Int
}

protocol ChannelSocket: AnyObject {
    var closeCode: Int { get }
    func sendText(_ text: String) async throws
    func receiveText() async throws -> String
    func close(code: Int)
}

final class URLSessionChannelSocket: ChannelSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    var closeCode: Int {
        let code = task.closeCode
        if code == .invalid { return 1006 }
        return code.rawValue
    }

    init(url: URL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 1_048_576
    }

    func connect() {
        task.resume()
    }

    func sendText(_ text: String) async throws {
        do {
            try await task.send(.string(text))
        } catch {
            throw SocketClosed(code: closeCode)
        }
    }

    func receiveText() async throws -> String {
        do {
            let message = try await task.receive()
            switch message {
            case .string(let text):
                return text
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8) else {
                    throw SocketClosed(code: 4002)
                }
                return text
            @unknown default:
                throw SocketClosed(code: 4002)
            }
        } catch let closed as SocketClosed {
            throw closed
        } catch {
            throw SocketClosed(code: closeCode)
        }
    }

    func close(code: Int) {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code)
        task.cancel(with: closeCode, reason: nil)
    }
}

enum Dialer {
    /// Dials one direct URL and returns a connected socket. Throws
    /// SocketClosed on failure (transient — the supervisor retries).
    static func dial(_ baseURL: String) throws -> URLSessionChannelSocket {
        guard let url = channelURL(baseURL: baseURL) else {
            throw SocketClosed(code: 1006)
        }
        let socket = URLSessionChannelSocket(url: url)
        socket.connect()
        return socket
    }

    static func channelURL(baseURL: String) -> URL? {
        guard var parts = URLComponents(string: baseURL) else { return nil }
        switch parts.scheme {
        case "http":
            parts.scheme = "ws"
        case "https":
            parts.scheme = "wss"
        default:
            return nil
        }
        parts.path = "/channel"
        parts.queryItems = [URLQueryItem(name: "v", value: "1")]
        return parts.url
    }
}
