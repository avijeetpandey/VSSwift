import Foundation
import Darwin

/// A pseudo-terminal (PTY) session hosting an interactive shell. Output is streamed
/// asynchronously; input is written to the master device. Mirrors VSCode's integrated
/// terminal using a native PTY (no embedded browser required).
public final class PseudoTerminal: @unchecked Sendable {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.vsswift.pty", qos: .userInitiated)

    private var continuation: AsyncStream<Data>.Continuation?
    public let output: AsyncStream<Data>

    public let shellPath: String

    public init(shellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
        self.shellPath = shellPath
        var cont: AsyncStream<Data>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    @discardableResult
    public func start(columns: UInt16 = 80, rows: UInt16 = 24) -> Bool {
        var master: Int32 = 0
        var slave: Int32 = 0
        var winsize = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &winsize) == 0 else { return false }

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
        posix_spawn_file_actions_addclose(&fileActions, master)
        posix_spawn_file_actions_addclose(&fileActions, slave)

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let args = [shellPath, "-il"]
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for case let p? in argv { free(p) } }

        var pid: pid_t = 0
        let env = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for case let p? in env { free(p) } }

        let result = posix_spawn(&pid, shellPath, &fileActions, &attr, argv, env)
        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attr)
        close(slave)

        guard result == 0 else { close(master); return false }
        self.masterFD = master
        self.childPID = pid

        let src = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(self.masterFD, &buffer, buffer.count)
            if n > 0 {
                self.continuation?.yield(Data(buffer[0..<n]))
            } else if n == 0 {
                self.stop()
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd >= 0 { close(fd) }
        }
        self.source = src
        src.resume()
        return true
    }

    public func write(_ text: String) {
        guard masterFD >= 0 else { return }
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(masterFD, $0.baseAddress, $0.count) }
    }

    public func resize(columns: UInt16, rows: UInt16) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    public func stop() {
        source?.cancel()
        source = nil
        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = -1
        }
        masterFD = -1
        continuation?.finish()
    }

    deinit { stop() }
}
