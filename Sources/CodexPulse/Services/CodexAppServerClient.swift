import AppKit
import Combine
import Foundation
import Security

// MARK: - Dependency-injectable protocol primitives

public enum CodexJSONValue: Codable, Equatable, Sendable {
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case string(String)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodexJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CodexJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .unsignedInteger(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    fileprivate var integerID: Int? {
        switch self {
        case let .integer(value): Int(exactly: value)
        case let .unsignedInteger(value): Int(exactly: value)
        default: nil
        }
    }
}

public struct CodexAppServerRPCError: Codable, Equatable, Sendable {
    public let code: Int
    public let message: String
}

public struct CodexAppServerMessage: Equatable, Sendable {
    public let id: CodexJSONValue?
    public let method: String?
    public let params: CodexJSONValue?
    public let result: CodexJSONValue?
    public let error: CodexAppServerRPCError?

    public init(
        id: CodexJSONValue? = nil,
        method: String? = nil,
        params: CodexJSONValue? = nil,
        result: CodexJSONValue? = nil,
        error: CodexAppServerRPCError? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public protocol CodexAppServerMessageParsing: Sendable {
    func parse(line: Data) throws -> CodexAppServerMessage
}

public struct JSONCodexAppServerMessageParser: CodexAppServerMessageParsing {
    public init() {}

    public func parse(line: Data) throws -> CodexAppServerMessage {
        struct WireMessage: Decodable {
            let id: CodexJSONValue?
            let method: String?
            let params: CodexJSONValue?
            let result: CodexJSONValue?
            let error: CodexAppServerRPCError?
        }

        let decoded = try JSONDecoder().decode(WireMessage.self, from: line)
        return CodexAppServerMessage(
            id: decoded.id,
            method: decoded.method,
            params: decoded.params,
            result: decoded.result,
            error: decoded.error
        )
    }
}

public enum CodexAppServerTransportTermination: Equatable, Sendable {
    case exited(status: Int32)
    case protocolFailure
}

public protocol CodexAppServerTransport: AnyObject, Sendable {
    func start(
        onLine: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (CodexAppServerTransportTermination) -> Void
    ) throws
    func send(line: Data) throws
    func stop()
}

public protocol CodexExecutableResolving: Sendable {
    func resolveCodexExecutable() throws -> URL
}

// MARK: - Executable resolution

public struct DefaultCodexExecutableResolver: CodexExecutableResolving {
    private let explicitURL: URL?
    private let environment: [String: String]
    private let homeDirectory: URL
    private let applicationDirectories: [URL]
    private let registeredApplicationURLs: [URL]
    private let applicationValidator: @Sendable (URL) -> Bool

    public init(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationDirectories: [URL]? = nil,
        registeredApplicationURLs: [URL]? = nil,
        applicationValidator: (@Sendable (URL) -> Bool)? = nil
    ) {
        self.explicitURL = explicitURL
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        if let registeredApplicationURLs {
            self.registeredApplicationURLs = registeredApplicationURLs
        } else if let registeredApplication = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) {
            self.registeredApplicationURLs = [registeredApplication]
        } else {
            self.registeredApplicationURLs = []
        }
        self.applicationValidator = applicationValidator ?? {
            Self.isTrustedOpenAIApplication($0)
        }
    }

    public func resolveCodexExecutable() throws -> URL {
        var candidates: [URL] = []
        if let explicitURL {
            candidates.append(explicitURL)
        }

        // GUI applications often inherit a minimal PATH, so include common Codex
        // installation locations without invoking a shell.
        candidates.append(contentsOf: [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent(".codex/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/usr/bin/codex")
        ])

        for pathEntry in environment["PATH", default: ""].split(separator: ":") {
            let directory = String(pathEntry)
            guard directory.hasPrefix("/") else { continue }
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("codex"))
        }

        var visited = Set<String>()
        var deferredNodeLaunchers: [URL] = []
        for candidate in candidates {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }

            guard isExecutableFile(resolved) else { continue }

            // The npm launcher is a `#!/usr/bin/env node` script. Apps opened
            // from Finder inherit a minimal PATH, so that launcher can be found
            // while its Node interpreter cannot. Prefer the native binary that
            // ships in the same Codex package; it is also what the launcher
            // ultimately executes.
            if let nativeExecutable = packagedNativeExecutable(backing: resolved) {
                return nativeExecutable
            }

            // A JavaScript launcher is the least reliable choice for a GUI app:
            // even a visible Node executable can still be broken or mismatched.
            // Keep it only as the final fallback after all native candidates.
            if resolved.pathExtension == "js" {
                if environmentCanRunNode() {
                    deferredNodeLaunchers.append(resolved)
                }
                continue
            }

            return resolved
        }

        // A package manager can leave the native optional dependency installed
        // while its public bin symlink is temporarily absent during an update.
        // Search those native package locations directly instead of depending
        // on the launcher as the only route into the package.
        for candidate in directNativeExecutableCandidates() {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }
            if isExecutableFile(resolved) {
                return resolved
            }
        }

        // ChatGPT includes a native Codex executable. Only use it after the
        // containing application passes strict code-signature validation for
        // OpenAI's bundle identifier and Team ID.
        for candidate in bundledApplicationCandidates() {
            let application = candidate
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard applicationValidator(application) else { continue }

            let resources = application
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let applicationPrefix = application.path + "/"
            let executable = resources
                .appendingPathComponent("codex")
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard resources.path.hasPrefix(applicationPrefix),
                  executable.path.hasPrefix(resources.path + "/"),
                  visited.insert(executable.path).inserted,
                  isExecutableFile(executable)
            else { continue }

            return executable
        }

        if let nodeLauncher = deferredNodeLaunchers.first {
            return nodeLauncher
        }

        throw CodexAppServerClientError.executableNotFound
    }

    private func packagedNativeExecutable(backing executable: URL) -> URL? {
        guard executable.lastPathComponent == "codex.js",
              executable.deletingLastPathComponent().lastPathComponent == "bin",
              let nativePlatform
        else { return nil }

        let packageRoot = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return packagedNativeCandidates(
            packageRoot: packageRoot,
            platform: nativePlatform
        )
        .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        .first(where: isExecutableFile)
    }

    private func directNativeExecutableCandidates() -> [URL] {
        guard let nativePlatform else { return [] }

        var packageRoots = [
            homeDirectory.appendingPathComponent(
                ".npm-global/lib/node_modules/@openai/codex",
                isDirectory: true
            ),
            homeDirectory.appendingPathComponent(
                ".local/lib/node_modules/@openai/codex",
                isDirectory: true
            ),
            URL(
                fileURLWithPath: "/opt/homebrew/lib/node_modules/@openai/codex",
                isDirectory: true
            ),
            URL(
                fileURLWithPath: "/usr/local/lib/node_modules/@openai/codex",
                isDirectory: true
            )
        ]

        for variable in ["npm_config_prefix", "NPM_CONFIG_PREFIX"] {
            guard let prefix = environment[variable], prefix.hasPrefix("/") else { continue }
            packageRoots.append(
                URL(fileURLWithPath: prefix, isDirectory: true)
                    .appendingPathComponent("lib/node_modules/@openai/codex", isDirectory: true)
            )
        }

        for pathEntry in environment["PATH", default: ""].split(separator: ":") {
            let directory = String(pathEntry)
            guard directory.hasPrefix("/") else { continue }
            let prefix = URL(fileURLWithPath: directory, isDirectory: true)
                .deletingLastPathComponent()
            packageRoots.append(
                prefix.appendingPathComponent(
                    "lib/node_modules/@openai/codex",
                    isDirectory: true
                )
            )
        }

        var visitedRoots = Set<String>()
        return packageRoots
            .map { $0.standardizedFileURL }
            .filter { visitedRoots.insert($0.path).inserted }
            .flatMap {
                packagedNativeCandidates(packageRoot: $0, platform: nativePlatform)
            }
    }

    private func bundledApplicationCandidates() -> [URL] {
        registeredApplicationURLs + applicationDirectories.flatMap { directory in
            ["ChatGPT.app", "Codex.app"].map { applicationName in
                directory
                    .appendingPathComponent(applicationName, isDirectory: true)
            }
        }
    }

    private static func isTrustedOpenAIApplication(_ applicationURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode
        else { return false }

        let requirementText = """
        anchor apple generic and identifier "com.openai.codex" \
        and certificate leaf[subject.OU] = "2DC432GLL2"
        """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
        let requirement
        else { return false }

        let validationFlags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures
                | kSecCSCheckNestedCode
                | kSecCSStrictValidate
        )
        return SecStaticCodeCheckValidity(
            staticCode,
            validationFlags,
            requirement
        ) == errSecSuccess
    }

    private func packagedNativeCandidates(
        packageRoot: URL,
        platform: (packageName: String, targetTriple: String)
    ) -> [URL] {
        let relativeBinary = "vendor/\(platform.targetTriple)/bin/codex"
        return [
            packageRoot
                .appendingPathComponent("node_modules/@openai/\(platform.packageName)")
                .appendingPathComponent(relativeBinary),
            packageRoot
                .deletingLastPathComponent()
                .appendingPathComponent(platform.packageName)
                .appendingPathComponent(relativeBinary),
            packageRoot.appendingPathComponent(relativeBinary)
        ]
    }

    private var nativePlatform: (packageName: String, targetTriple: String)? {
        #if arch(arm64)
        return ("codex-darwin-arm64", "aarch64-apple-darwin")
        #elseif arch(x86_64)
        return ("codex-darwin-x64", "x86_64-apple-darwin")
        #else
        return nil
        #endif
    }

    private func environmentCanRunNode() -> Bool {
        environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map {
                URL(fileURLWithPath: $0, isDirectory: true)
                    .appendingPathComponent("node")
            }
            .contains(where: isExecutableFile)
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

// MARK: - Process transport

/// A single long-lived `codex app-server --stdio` process. Stdout is interpreted
/// strictly as newline-delimited JSON; stderr is drained and intentionally never
/// logged or retained.
public final class ProcessCodexAppServerTransport: CodexAppServerTransport, @unchecked Sendable {
    private let executableURL: URL
    private let maximumLineBytes: Int
    private let stateLock = NSLock()
    private let writeLock = NSLock()

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var receiveBuffer = Data()
    private var onLine: (@Sendable (Data) -> Void)?
    private var onTermination: (@Sendable (CodexAppServerTransportTermination) -> Void)?
    private var didTerminate = false

    public init(executableURL: URL, maximumLineBytes: Int = 8 * 1_024 * 1_024) {
        self.executableURL = executableURL
        self.maximumLineBytes = maximumLineBytes
    }

    public func start(
        onLine: @escaping @Sendable (Data) -> Void,
        onTermination: @escaping @Sendable (CodexAppServerTransportTermination) -> Void
    ) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        stateLock.lock()
        guard self.process == nil else {
            stateLock.unlock()
            throw CodexAppServerClientError.transportAlreadyStarted
        }
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        errorHandle = errorPipe.fileHandleForReading
        self.onLine = onLine
        self.onTermination = onTermination
        didTerminate = false
        receiveBuffer.removeAll(keepingCapacity: true)
        stateLock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty {
                self?.handleStandardOutputEOF()
            } else {
                self?.consumeStandardOutput(bytes)
            }
        }

        // Draining stderr prevents the child from blocking on a full pipe. The
        // bytes are discarded: auth/config output must never reach logs or UI.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.finish(with: .exited(status: terminatedProcess.terminationStatus))
        }

        do {
            try process.run()
        } catch {
            tearDownHandles()
            stateLock.lock()
            self.process = nil
            stateLock.unlock()
            throw CodexAppServerClientError.processLaunchFailed
        }
    }

    public func send(line: Data) throws {
        var framed = line
        if framed.last != 0x0A {
            framed.append(0x0A)
        }

        writeLock.lock()
        defer { writeLock.unlock() }

        stateLock.lock()
        let handle = inputHandle
        let running = process?.isRunning == true
        stateLock.unlock()

        guard running, let handle else {
            throw CodexAppServerClientError.disconnected
        }

        do {
            try handle.write(contentsOf: framed)
        } catch {
            throw CodexAppServerClientError.transportWriteFailed
        }
    }

    public func stop() {
        stateLock.lock()
        let process = self.process
        self.process = nil
        let inputHandle = self.inputHandle
        self.inputHandle = nil
        stateLock.unlock()

        try? inputHandle?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        tearDownHandles()
    }

    private func consumeStandardOutput(_ bytes: Data) {
        var completedLines: [Data] = []
        var exceededMaximum = false

        stateLock.lock()
        receiveBuffer.append(bytes)
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            var line = Data(receiveBuffer[..<newline])
            receiveBuffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty { completedLines.append(line) }
        }
        if receiveBuffer.count > maximumLineBytes {
            receiveBuffer.removeAll(keepingCapacity: false)
            exceededMaximum = true
        }
        let callback = onLine
        stateLock.unlock()

        completedLines.forEach { callback?($0) }
        if exceededMaximum {
            finish(with: .protocolFailure)
            stop()
        }
    }

    private func handleStandardOutputEOF() {
        stateLock.lock()
        let trailing = receiveBuffer
        receiveBuffer.removeAll(keepingCapacity: false)
        let callback = onLine
        outputHandle?.readabilityHandler = nil
        stateLock.unlock()

        if !trailing.isEmpty { callback?(trailing) }
    }

    private func finish(with termination: CodexAppServerTransportTermination) {
        stateLock.lock()
        guard !didTerminate else {
            stateLock.unlock()
            return
        }
        didTerminate = true
        let callback = onTermination
        stateLock.unlock()
        callback?(termination)
    }

    private func tearDownHandles() {
        stateLock.lock()
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        let outputHandle = self.outputHandle
        let errorHandle = self.errorHandle
        self.outputHandle = nil
        self.errorHandle = nil
        stateLock.unlock()

        try? outputHandle?.close()
        try? errorHandle?.close()
    }

    deinit {
        stop()
    }
}

// MARK: - Account client

public enum CodexAppServerConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed
}

public enum CodexAppServerClientError: Error, Equatable, LocalizedError, Sendable {
    case executableNotFound
    case transportAlreadyStarted
    case processLaunchFailed
    case transportWriteFailed
    case disconnected
    case invalidResponse
    case requestTimedOut(method: String)
    case processTerminated(status: Int32)
    case transportProtocolFailure
    case rpcFailure(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI could not be found."
        case .transportAlreadyStarted:
            "The Codex app-server transport is already running."
        case .processLaunchFailed:
            "Codex app-server could not be launched."
        case .transportWriteFailed:
            "A request could not be sent to Codex app-server."
        case .disconnected:
            "Codex app-server is disconnected."
        case .invalidResponse:
            "Codex app-server returned an invalid response."
        case let .requestTimedOut(method):
            "Codex app-server timed out while handling \(method)."
        case let .processTerminated(status):
            "Codex app-server exited with status \(status)."
        case .transportProtocolFailure:
            "Codex app-server exceeded the JSONL transport limit."
        case let .rpcFailure(code, message):
            "Codex app-server error \(code): \(message)"
        }
    }
}

@MainActor
public final class CodexAppServerClient: ObservableObject {
    public typealias TransportFactory = @Sendable (URL) -> any CodexAppServerTransport

    @Published public private(set) var snapshot: AccountUsageSnapshot = .empty
    @Published public private(set) var connectionState: CodexAppServerConnectionState = .disconnected
    @Published public private(set) var lastError: CodexAppServerClientError?

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<CodexJSONValue, Error>
        var timeoutTask: Task<Void, Never>?
    }

    private struct RateLimitsUpdatedNotification: Decodable {
        let rateLimits: CodexRateLimitSnapshot
    }

    private let parser: any CodexAppServerMessageParsing
    private let executableResolver: any CodexExecutableResolving
    private let transportFactory: TransportFactory
    private let requestTimeout: TimeInterval
    private let now: @Sendable () -> Date
    private let clientVersion: String

    private var transport: (any CodexAppServerTransport)?
    private var transportGeneration: UUID?
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var connectionWaiters: [CheckedContinuation<Void, Error>] = []
    private var nextRequestID = 1
    private var monitorTask: Task<Void, Never>?

    public init(
        parser: any CodexAppServerMessageParsing = JSONCodexAppServerMessageParser(),
        executableResolver: any CodexExecutableResolving = DefaultCodexExecutableResolver(),
        transportFactory: @escaping TransportFactory = { ProcessCodexAppServerTransport(executableURL: $0) },
        requestTimeout: TimeInterval = 12,
        clientVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.parser = parser
        self.executableResolver = executableResolver
        self.transportFactory = transportFactory
        self.requestTimeout = max(0.001, requestTimeout)
        self.clientVersion = clientVersion
        self.now = now
    }

    /// Starts one app-server process and completes the mandatory initialize / initialized handshake.
    public func connect() async throws {
        if connectionState == .connected { return }
        if connectionState == .connecting {
            try await withCheckedThrowingContinuation { continuation in
                connectionWaiters.append(continuation)
            }
            return
        }

        connectionState = .connecting
        lastError = nil

        do {
            let resolver = executableResolver
            let executableURL = try await Task.detached(priority: .userInitiated) {
                try resolver.resolveCodexExecutable()
            }.value
            let newTransport = transportFactory(executableURL)
            let generation = UUID()
            transport = newTransport
            transportGeneration = generation

            try newTransport.start(
                onLine: { [weak self] line in
                    Task { @MainActor [weak self] in
                        self?.receive(line: line, generation: generation)
                    }
                },
                onTermination: { [weak self] termination in
                    Task { @MainActor [weak self] in
                        self?.transportTerminated(termination, generation: generation)
                    }
                }
            )

            let initializeParams: CodexJSONValue = .object([
                "clientInfo": .object([
                    "name": .string("codex_pulse"),
                    "title": .string("Codex Pulse"),
                    "version": .string(clientVersion)
                ])
            ])
            _ = try await request(method: "initialize", params: initializeParams)
            try sendNotification(method: "initialized")
            connectionState = .connected
            finishConnectionWaiters(with: .success(()))
        } catch {
            let clientError = normalized(error)
            lastError = clientError
            connectionState = .failed
            disconnectTransport(failingPendingWith: clientError)
            finishConnectionWaiters(with: .failure(clientError))
            throw clientError
        }
    }

    /// Compatibility-friendly synonym used by app lifecycle code.
    public func start() async throws {
        try await connect()
    }

    /// Reads both stable account endpoints over the existing process.
    @discardableResult
    public func refresh() async throws -> AccountUsageSnapshot {
        if connectionState != .connected {
            try await connect()
        }

        do {
            let rateLimitsValue = try await request(method: "account/rateLimits/read")
            let usageValue = try await request(method: "account/usage/read")
            let rateLimits: CodexAccountRateLimitsResponse = try decode(
                CodexAccountRateLimitsResponse.self,
                from: rateLimitsValue
            )
            let usage: CodexAccountUsageResponse = try decode(
                CodexAccountUsageResponse.self,
                from: usageValue
            )

            var updated = snapshot
            updated.apply(rateLimits: rateLimits, usage: usage, observedAt: now())
            snapshot = updated
            lastError = nil
            return updated
        } catch {
            let clientError = normalized(error)
            lastError = clientError
            throw clientError
        }
    }

    /// Connects immediately, then periodically refreshes lifetime/daily usage.
    /// Rolling rate-limit notifications continue to update `snapshot` between polls.
    public func startMonitoring(refreshInterval: TimeInterval = 60) {
        monitorTask?.cancel()
        let interval = max(1, refreshInterval)
        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.connect()
                _ = try await self.refresh()
            } catch {
                // `lastError` is set by connect/refresh; monitoring can retry on
                // the next tick without printing potentially sensitive output.
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(interval))
                guard !Task.isCancelled else { break }
                do {
                    _ = try await self.refresh()
                } catch {
                    // Keep the last successful snapshot visible.
                }
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    public func disconnect() {
        stopMonitoring()
        disconnectTransport(failingPendingWith: .disconnected)
        finishConnectionWaiters(with: .failure(CodexAppServerClientError.disconnected))
        connectionState = .disconnected
    }

    public func stop() {
        disconnect()
    }

    private func request(method: String, params: CodexJSONValue? = nil) async throws -> CodexJSONValue {
        guard let transport else { throw CodexAppServerClientError.disconnected }

        let requestID = nextRequestID
        nextRequestID += 1
        var object: [String: CodexJSONValue] = [
            "id": .integer(Int64(requestID)),
            "method": .string(method)
        ]
        if let params { object["params"] = params }
        let wireData = try JSONEncoder().encode(CodexJSONValue.object(object))

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = PendingRequest(
                method: method,
                continuation: continuation,
                timeoutTask: nil
            )

            let timeoutTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: Self.nanoseconds(self.requestTimeout))
                guard !Task.isCancelled else { return }
                self.timeoutRequest(id: requestID)
            }
            pendingRequests[requestID]?.timeoutTask = timeoutTask

            do {
                try transport.send(line: wireData)
            } catch {
                guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
                pending.timeoutTask?.cancel()
                pending.continuation.resume(throwing: normalized(error))
            }
        }
    }

    private func sendNotification(method: String) throws {
        guard let transport else { throw CodexAppServerClientError.disconnected }
        let data = try JSONEncoder().encode(CodexJSONValue.object(["method": .string(method)]))
        try transport.send(line: data)
    }

    private func receive(line: Data, generation: UUID) {
        guard transportGeneration == generation else { return }

        let message: CodexAppServerMessage
        do {
            message = try parser.parse(line: line)
        } catch {
            lastError = .invalidResponse
            return
        }

        if message.method == nil,
           let requestID = message.id?.integerID,
           let pending = pendingRequests.removeValue(forKey: requestID) {
            pending.timeoutTask?.cancel()
            if let error = message.error {
                pending.continuation.resume(
                    throwing: CodexAppServerClientError.rpcFailure(code: error.code, message: error.message)
                )
            } else if let result = message.result {
                pending.continuation.resume(returning: result)
            } else {
                pending.continuation.resume(throwing: CodexAppServerClientError.invalidResponse)
            }
            return
        }

        guard message.method == "account/rateLimits/updated", let params = message.params else { return }
        do {
            let notification: RateLimitsUpdatedNotification = try decode(
                RateLimitsUpdatedNotification.self,
                from: params
            )
            var updated = snapshot
            updated.mergeSparseRateLimitUpdate(notification.rateLimits, observedAt: now())
            snapshot = updated
        } catch {
            lastError = .invalidResponse
        }
    }

    private func timeoutRequest(id: Int) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(
            throwing: CodexAppServerClientError.requestTimedOut(method: pending.method)
        )
    }

    private func transportTerminated(
        _ termination: CodexAppServerTransportTermination,
        generation: UUID
    ) {
        guard transportGeneration == generation else { return }
        let error: CodexAppServerClientError
        switch termination {
        case let .exited(status): error = .processTerminated(status: status)
        case .protocolFailure: error = .transportProtocolFailure
        }
        lastError = error
        connectionState = .failed
        disconnectTransport(failingPendingWith: error)
    }

    private func disconnectTransport(failingPendingWith error: CodexAppServerClientError) {
        transportGeneration = nil
        let oldTransport = transport
        transport = nil

        let pending = pendingRequests.values
        pendingRequests.removeAll()
        pending.forEach {
            $0.timeoutTask?.cancel()
            $0.continuation.resume(throwing: error)
        }
        oldTransport?.stop()
    }

    private func finishConnectionWaiters(with result: Result<Void, Error>) {
        let waiters = connectionWaiters
        connectionWaiters.removeAll()
        waiters.forEach { continuation in
            switch result {
            case .success:
                continuation.resume()
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: CodexJSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    private func normalized(_ error: Error) -> CodexAppServerClientError {
        if let clientError = error as? CodexAppServerClientError { return clientError }
        if error is DecodingError || error is EncodingError { return .invalidResponse }
        return .transportWriteFailed
    }

    private nonisolated static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        let capped = min(max(interval, 0), TimeInterval(UInt64.max) / 1_000_000_000)
        return UInt64(capped * 1_000_000_000)
    }

    deinit {
        monitorTask?.cancel()
        transport?.stop()
        pendingRequests.values.forEach {
            $0.timeoutTask?.cancel()
            $0.continuation.resume(throwing: CodexAppServerClientError.disconnected)
        }
        connectionWaiters.forEach {
            $0.resume(throwing: CodexAppServerClientError.disconnected)
        }
    }
}
