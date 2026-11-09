import Foundation

/// Runs a git command in a directory and returns its standard output.
protocol GitRunner: Sendable {
    func run(_ args: [String], cwd: String, timeout: TimeInterval) async throws -> String
}

enum GitRunnerError: Error {
    case timedOut
    case failed(Int32)
}

/// Runs `/usr/bin/git -C <cwd> <args>` and kills it after `timeout`.
struct ProcessGitRunner: GitRunner {
    func run(_ args: [String], cwd: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Self.runBlocking(args, cwd: cwd, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ args: [String], cwd: String, timeout: TimeInterval) -> Result<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(GitRunnerError.failed(-1))
        }

        let killed = NSLock()
        var didKill = false
        let killer = DispatchWorkItem {
            killed.withLock {
                guard process.isRunning else { return }
                didKill = true
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        if killed.withLock({ didKill }) { return .failure(GitRunnerError.timedOut) }
        guard process.terminationStatus == 0 else {
            return .failure(GitRunnerError.failed(process.terminationStatus))
        }
        return .success(String(decoding: data, as: UTF8.self))
    }
}

/// Counting semaphore for async tasks.
private actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { available = max(1, count) }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Resolves each cwd's repo root, reads its git status and feeds both into the store.
@MainActor
final class GitStatusService {
    private let store: WorkbenchStore
    private let runner: GitRunner
    private let timeout: TimeInterval
    private let interval: TimeInterval
    private let slots: AsyncSemaphore
    private var timer: Timer?
    private var inFlight: Set<String> = []

    init(
        store: WorkbenchStore,
        runner: GitRunner = ProcessGitRunner(),
        maxConcurrent: Int = 4,
        timeout: TimeInterval = 2,
        interval: TimeInterval = 5
    ) {
        self.store = store
        self.runner = runner
        self.timeout = timeout
        self.interval = interval
        self.slots = AsyncSemaphore(maxConcurrent)
    }

    func refresh(cwd: String) async {
        await slots.acquire()
        defer { Task { await slots.release() } }

        let root: String
        do {
            let out = try await runner.run(["rev-parse", "--show-toplevel"], cwd: cwd, timeout: timeout)
            root = out.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch GitRunnerError.timedOut {
            // A slow repo is still a repo: keep the root we already know and show "?".
            if let previous = store.repoRoots[cwd] {
                store.applyGit(cwd: cwd, repoRoot: previous, state: timedOutState(root: previous))
            } else {
                store.applyGit(cwd: cwd, repoRoot: nil, state: nil)
            }
            return
        } catch {
            store.applyGit(cwd: cwd, repoRoot: nil, state: nil)
            return
        }
        guard !root.isEmpty else {
            store.applyGit(cwd: cwd, repoRoot: nil, state: nil)
            return
        }

        do {
            let out = try await runner.run(["status", "--porcelain=v2", "--branch"], cwd: root, timeout: timeout)
            store.applyGit(cwd: cwd, repoRoot: root, state: GitPorcelain.parse(out))
        } catch GitRunnerError.timedOut {
            store.applyGit(cwd: cwd, repoRoot: root, state: timedOutState(root: root))
        } catch {
            store.applyGit(cwd: cwd, repoRoot: root, state: nil)
        }
    }

    /// The "?" state: previous branch kept, counts zeroed, timedOut set.
    private func timedOutState(root: String) -> GitState {
        GitState(
            branch: store.git[root]?.branch ?? "",
            ahead: 0, behind: 0, staged: 0, unstaged: 0, untracked: 0,
            timedOut: true)
    }

    func startPolling(visibleCwds: @escaping @MainActor () -> [String]) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for cwd in Set(visibleCwds()) where !self.inFlight.contains(cwd) {
                    self.inFlight.insert(cwd)
                    Task { @MainActor [weak self] in
                        await self?.refresh(cwd: cwd)
                        self?.inFlight.remove(cwd)
                    }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
