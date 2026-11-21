import Foundation

/// Host call errors. Messages are shown to the user, so they go through L().
enum HostCallError: Error {
    case unreachable
    case timeout
    case failed(String)
    case unauthorized(String)
    case upgradeRequired
    case tooLarge
    case rejected(code: String?, message: String?)
}

/// What a stream subscribes to. Only `events` is used in Phase 1.
enum HostStreamRequest {
    case events(since: Int64, client: String)
    case term(String)
}

extension ChannelConnection {
    // MARK: - Id allocation

    private func nextId() -> UInt32 {
        nextRequestId &+= 1
        if nextRequestId == 0 { nextRequestId = 1 }
        return nextRequestId
    }

    // MARK: - Call

    /// One request/response. The body is the method's JSON object as Data.
    /// Waits for the channel to be ready (bounded by the timeout), enforces
    /// the 32-concurrent-request limit, and cancels on timeout or task
    /// cancellation. A timeout resumes throwing `unreachable` (§4.2) — the
    /// caller decides whether to retry; `send` is deduped by clientNonce.
    func call(method: String, body: Data?, timeout: TimeInterval = 20) async throws -> Data {
        try await ready(within: min(timeout, 10))
        guard calls.count < 32 else { throw HostCallError.tooLarge }
        let id = nextId()
        var payload = Data()
        payload.append("{\"id\":\(id),\"m\":\"".utf8)
        payload.append(method.utf8)
        payload.append("\",\"b\":".utf8)
        payload.append(body ?? Data("{}".utf8))
        payload.append("}".utf8)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                calls[id] = continuation
                do {
                    try enqueueInner(payload)
                } catch {
                    calls.removeValue(forKey: id)
                    continuation.resume(throwing: HostCallError.unreachable)
                    return
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    await self.timeoutCall(id: id)
                }
            }
        } onCancel: {
            Task { await self.cancelCall(id: id) }
        }
    }

    private func timeoutCall(id: UInt32) {
        guard let continuation = calls.removeValue(forKey: id) else { return }
        continuation.resume(throwing: HostCallError.unreachable)
        sendCancel(id: id)
    }

    private func cancelCall(id: UInt32) {
        guard let continuation = calls.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        sendCancel(id: id)
    }

    // MARK: - Stream

    /// A subscription. Sends `{"id":N,"sub":…,"b":…}`; later `ev` messages
    /// are yielded as raw JSON Data. The consumer's termination sends
    /// `cancel` and drops the stream.
    func stream(_ request: HostStreamRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.ready(within: 10)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                guard self.streams.count < 4 else {
                    continuation.finish(throwing: HostCallError.tooLarge)
                    return
                }
                let id = self.nextId()
                self.streams[id] = continuation
                var payload = Data()
                payload.append("{\"id\":\(id),\"sub\":\"".utf8)
                switch request {
                case .events(let since, let client):
                    payload.append("events".utf8)
                    payload.append("\",\"b\":{\"since\":\(since),\"client\":\"\(client)\"}".utf8)
                case .term(let termId):
                    payload.append("term".utf8)
                    payload.append("\",\"b\":{\"term\":\"\(termId)\"}".utf8)
                }
                payload.append("}".utf8)
                do {
                    try self.enqueueInner(payload)
                } catch {
                    self.streams.removeValue(forKey: id)
                    continuation.finish(throwing: HostCallError.unreachable)
                    return
                }
                continuation.onTermination = { @Sendable _ in
                    Task { await self.cancelStream(id: id) }
                }
            }
        }
    }

    private func cancelStream(id: UInt32) {
        streams.removeValue(forKey: id)
        sendCancel(id: id)
    }

    private func sendCancel(id: UInt32) {
        let payload = Data("{\"id\":\(id),\"cancel\":true}".utf8)
        try? enqueueInner(payload)
    }

    // MARK: - Dispatch

    /// Dispatches one decrypted inner JSON object.
    func dispatchInner(_ inner: [String: Any]) {
        guard let idNumber = inner["id"] as? NSNumber else { return }
        let id = idNumber.uint32Value
        if let ok = inner["ok"] {
            guard let continuation = calls.removeValue(forKey: id) else { return }
            if let data = try? JSONSerialization.data(withJSONObject: ok) {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: HostCallError.failed(L("电脑回了一条看不懂的消息。")))
            }
            return
        }
        if let err = inner["err"] as? [String: Any] {
            guard let continuation = calls.removeValue(forKey: id) else { return }
            let code = err["code"] as? String
            let message = err["message"] as? String
            switch code {
            case "not_found":
                continuation.resume(throwing: HostCallError.failed(message ?? L("找不到。")))
            case "not_permitted", "unauthorized":
                continuation.resume(throwing: HostCallError.unauthorized(message ?? L("没有权限。")))
            case "too_large":
                continuation.resume(throwing: HostCallError.tooLarge)
            case "timeout":
                continuation.resume(throwing: HostCallError.timeout)
            default:
                continuation.resume(throwing: HostCallError.failed(message ?? L("电脑出错了。")))
            }
            return
        }
        if let ev = inner["ev"] {
            guard let continuation = streams[id],
                  let data = try? JSONSerialization.data(withJSONObject: ev) else { return }
            continuation.yield(data)
            return
        }
        if inner["end"] != nil {
            guard let continuation = streams.removeValue(forKey: id) else { return }
            continuation.finish()
            return
        }
    }

    // MARK: - Teardown

    func failAllCalls(with error: Error) {
        let pending = calls
        calls.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    func failAllStreams(with error: Error) {
        let pending = streams
        streams.removeAll()
        for (_, continuation) in pending {
            continuation.finish(throwing: error)
        }
    }
}
