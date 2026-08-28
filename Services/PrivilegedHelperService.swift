import Foundation
import ServiceManagement

enum PrivilegedHelperRegistrationState: String, Sendable {
    case unavailable
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum PrivilegedHelperClientError: LocalizedError {
    case unavailable
    case invalidResponse
    case remote(String)
    case protocolMismatch

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Privileged helper is unavailable."
        case .invalidResponse: return "Privileged helper returned an invalid response."
        case .remote(let message): return message
        case .protocolMismatch: return "Privileged helper protocol version does not match MemWatch."
        }
    }
}

struct PrivilegedHelperClient: Sendable {
    func ping() async throws -> PrivilegedPingResponse {
        try await withConnection { proxy, finish in
            proxy.ping { data in
                finish(Self.decode(PrivilegedPingResponse.self, from: data))
            }
        }
    }

    func scan(ruleIDs: [CleanupRuleID]) async throws -> PrivilegedScanResponse {
        let request = PrivilegedScanRequest(ruleIDs: ruleIDs.map(\.rawValue))
        let data = try JSONEncoder().encode(request)
        return try await withConnection { proxy, finish in
            proxy.scan(data) { responseData in
                finish(Self.decode(PrivilegedScanResponse.self, from: responseData))
            }
        }
    }

    func execute(_ request: PrivilegedOperationRequest) async throws -> PrivilegedOperationResponse {
        let data = try JSONEncoder().encode(request)
        let response: PrivilegedOperationResponse = try await withConnection { proxy, finish in
            proxy.execute(data) { responseData in
                finish(Self.decode(PrivilegedOperationResponse.self, from: responseData))
            }
        }
        guard response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion else {
            throw PrivilegedHelperClientError.protocolMismatch
        }
        guard response.success else {
            throw PrivilegedHelperClientError.remote(response.message)
        }
        return response
    }

    private func withConnection<T: Sendable>(
        _ body: @escaping (MemWatchPrivilegedHelperXPC, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: MemWatchPrivilegedHelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: MemWatchPrivilegedHelperXPC.self)

            let lock = NSLock()
            var completed = false
            func finish(_ result: Result<T, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !completed else { return }
                completed = true
                connection.invalidate()
                continuation.resume(with: result)
            }

            connection.interruptionHandler = {
                finish(.failure(PrivilegedHelperClientError.unavailable))
            }
            connection.invalidationHandler = {
                lock.lock()
                let shouldFail = !completed
                lock.unlock()
                if shouldFail {
                    finish(.failure(PrivilegedHelperClientError.unavailable))
                }
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(.failure(error))
            }) as? MemWatchPrivilegedHelperXPC else {
                finish(.failure(PrivilegedHelperClientError.unavailable))
                return
            }
            body(proxy, finish)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, Error> {
        do {
            let value = try JSONDecoder().decode(type, from: data)
            if let ping = value as? PrivilegedPingResponse,
               ping.protocolVersion != MemWatchPrivilegedHelperConstants.protocolVersion {
                return .failure(PrivilegedHelperClientError.protocolMismatch)
            }
            if let scan = value as? PrivilegedScanResponse,
               scan.protocolVersion != MemWatchPrivilegedHelperConstants.protocolVersion {
                return .failure(PrivilegedHelperClientError.protocolMismatch)
            }
            return .success(value)
        } catch {
            return .failure(PrivilegedHelperClientError.invalidResponse)
        }
    }
}

@MainActor
final class PrivilegedHelperService: ObservableObject {
    @Published private(set) var state: PrivilegedHelperRegistrationState = .unavailable
    @Published private(set) var lastError: String?

    private let service = SMAppService.daemon(
        plistName: MemWatchPrivilegedHelperConstants.daemonPlistName
    )
    let client = PrivilegedHelperClient()

    init() {
        refreshStatus()
    }

    var isAvailableForCleanup: Bool {
        state == .enabled
    }

    func refreshStatus() {
        switch service.status {
        case .notRegistered:
            state = .notRegistered
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            state = .notFound
        @unknown default:
            state = .unavailable
        }
    }

    func register() {
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func unregister() {
        lastError = nil
        do {
            try service.unregister()
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func verifyConnection() async -> Bool {
        do {
            let response = try await client.ping()
            return response.protocolVersion == MemWatchPrivilegedHelperConstants.protocolVersion &&
                response.effectiveUID == 0
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
