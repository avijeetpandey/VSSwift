import Foundation

/// The result of running a `git` subprocess.
public struct GitCommandResult: Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Errors surfaced by the git layer.
public enum GitError: Error, Sendable, Equatable {
    case notARepository
    case launchFailed(String)
    case commandFailed(code: Int32, message: String)
}

/// Runs the `git` executable as a subprocess in a given working directory. Kept off
/// the main thread (callers are actor-isolated) so the UI never blocks on git I/O.
struct GitRunner: Sendable {
    let gitPath: String

    init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    /// Invokes `git <arguments>` inside `directory` and captures its output.
    func run(_ arguments: [String], in directory: URL) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory

        // Keep git non-interactive and free of the sandbox's injected config so it
        // behaves predictably regardless of the host environment.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_CONFIG_COUNT"] = "0"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return GitCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self))
    }
}
