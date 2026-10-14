//
//  ProcessRunner.swift
//  AccessibilityScanner
//
//  Runs command-line tools (xcrun, adb). Both output pipes are drained while
//  the process runs, so large output (simctl listapps is ~60 KB) cannot fill a
//  pipe and deadlock, and a process that hangs (an unauthorised adb device, a
//  locked iPhone) is terminated after a timeout.
//
//  Nonisolated: callers run it off the main actor so the UI stays responsive.
//

import Foundation

nonisolated enum ProcessRunner {

    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool

        var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
        var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    enum RunnerError: LocalizedError {
        case timedOut(command: String, seconds: Int)

        var errorDescription: String? {
            switch self {
            case .timedOut(let command, let seconds):
                return "\(command) did not finish within \(seconds) seconds and was stopped. Check that the device is connected, unlocked and trusted."
            }
        }
    }

    private final class Box: @unchecked Sendable {
        var data = Data()
        var timedOut = false
    }

    /// Runs the executable and returns its output. Throws when it cannot be
    /// started or exceeds `timeout`; a non-zero exit status is returned, not
    /// thrown, so callers can word their own error.
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 60
    ) throws -> Output {

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let errorBox = Box()
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorRead.leave()
        }

        let state = Box()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                state.timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        errorRead.wait()
        process.waitUntilExit()
        watchdog.cancel()

        if state.timedOut {
            let name = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments.prefix(2))
                .joined(separator: " ")
            throw RunnerError.timedOut(command: name, seconds: Int(timeout))
        }

        return Output(
            status: process.terminationStatus,
            stdout: outputData,
            stderr: errorBox.data,
            timedOut: false
        )
    }

    /// Runs blocking work on a background thread and awaits the result, so a
    /// main-actor caller does not freeze the UI while a command runs.
    static func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
