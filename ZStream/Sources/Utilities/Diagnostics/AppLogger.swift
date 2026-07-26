//
//  AppLogger.swift
//  ZStream
//
//  Persists everything the app would normally only show in Xcode's console —
//  print()/NSLog output plus system-level warnings and errors emitted via
//  the unified logging system (AVFoundation, URLSession, etc.) — to a single
//  rotating file capped at ~2MB. The only way to see what happened in a
//  Release build that was never attached to a debugger.
//
//  stdout/stderr are re-piped rather than simply redirected: everything
//  written to them is also re-emitted through os_log, so Xcode's console
//  still shows it live during a normal debug session.
//

import Foundation
import OSLog

final class AppLogger {
    static let shared = AppLogger()

    let fileURL: URL

    private let maxBytes = 2 * 1024 * 1024
    private let queue = DispatchQueue(label: "app.logger", qos: .utility)
    private let oslog: OSLog

    private var fileHandle: FileHandle?
    private var bytesSinceTrim = 0
    private var lastSystemLogDate = Date().addingTimeInterval(-10)
    private var systemLogTimer: DispatchSourceTimer?

    // Retained for the app's lifetime — a Pipe whose FileHandles aren't held
    // anywhere else can be deallocated (closing its fds and dropping the
    // readabilityHandler) right after setup, silently ending capture.
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        // Documents, not Application Support -- with UIFileSharingEnabled +
        // LSSupportsOpeningDocumentsInPlace, this is what shows up in the
        // Files app / Finder, so the log can be pulled off-device even if
        // the app itself is frozen and the in-app viewer is unreachable.
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("app.log")
        oslog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "ZStream", category: "console")
    }

    /// Call once, as early as possible in app startup — before anything else prints.
    /// The fd redirection itself happens synchronously so no print() between this
    /// call and app startup finishing slips out through the original stdout/stderr.
    func start() {
        pipeStandardStream(STDOUT_FILENO, buffer: stdout)
        pipeStandardStream(STDERR_FILENO, buffer: stderr)
        queue.async { [weak self] in
            self?.openFile()
            self?.startSystemLogPolling()
        }
    }

    /// Empties the log file in place — used by the "Clear" action in the log viewer.
    func clear() {
        queue.async { [weak self] in
            self?.fileHandle?.truncateFile(atOffset: 0)
            self?.bytesSinceTrim = 0
        }
    }

    // MARK: - stdout/stderr capture

    private func pipeStandardStream(_ fd: Int32, buffer: UnsafeMutablePointer<FILE>) {
        // Unbuffered so each print()/fprintf flushes immediately instead of
        // sitting in libc's buffer (which defaults to fully-buffered once
        // stdout/stderr are no longer a tty, i.e. as soon as we pipe them).
        setvbuf(buffer, nil, _IONBF, 0)

        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, fd)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }

        if fd == STDOUT_FILENO {
            stdoutPipe = pipe
        } else {
            stderrPipe = pipe
        }
    }

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            append(data)
            return
        }

        var trimmed = text
        if trimmed.hasSuffix("\n") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return }

        // The OS's own logging subsystem periodically dumps raw progress
        // lines like "OSLOG-<uuid> 7 80 L 22fbf {t:...,lines:N}" straight to
        // stderr — internal log-flush bookkeeping, not app output. It's noisy
        // enough to crowd out everything real within the size cap, so drop it.
        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("OSLOG-") }
        guard !lines.isEmpty else { return }

        // Re-emit through the unified logging system so Xcode's console
        // (which streams os_log entries, not raw stdout, once a debugger is
        // attached) still shows everything live.
        os_log("%{public}@", log: oslog, type: .default, lines.joined(separator: "\n"))

        let stamp = Self.timestampFormatter.string(from: Date())
        let stamped = lines.map { "[\(stamp)] \($0)\n" }.joined()
        append(Data(stamped.utf8))
    }

    // MARK: - System log capture

    /// Polls OSLogStore for this process's own error/fault-level entries —
    /// the closest thing to a push API the unified logging system offers.
    private func startSystemLogPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 30)
        timer.setEventHandler { [weak self] in self?.pollSystemLog() }
        timer.resume()
        systemLogTimer = timer
    }

    private func pollSystemLog() {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let position = try? store.position(date: lastSystemLogDate),
              let entries = try? store.getEntries(at: position) else { return }

        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog,
                  logEntry.level == .error || logEntry.level == .fault,
                  logEntry.category != "console" else { continue }
            let stamp = Self.timestampFormatter.string(from: logEntry.date)
            let level = logEntry.level == .fault ? "FAULT" : "ERROR"
            lines.append("[\(stamp)] [\(level)] \(logEntry.subsystem)/\(logEntry.category): \(logEntry.composedMessage)")
        }
        lastSystemLogDate = Date()
        guard !lines.isEmpty else { return }
        append(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    // MARK: - File I/O (queue-serialized)

    private func openFile() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }

    private func append(_ data: Data) {
        guard let fileHandle else { return }
        fileHandle.write(data)
        bytesSinceTrim += data.count
        guard bytesSinceTrim > 256 * 1024 else { return }
        bytesSinceTrim = 0
        trimIfNeeded()
    }

    /// Keeps only the most recent `maxBytes` of the file, rewritten in place
    /// through the same handle so its write offset stays correct afterwards.
    private func trimIfNeeded() {
        guard let fileHandle, Int(fileHandle.offsetInFile) > maxBytes else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let tail = data.suffix(maxBytes)
        fileHandle.truncateFile(atOffset: 0)
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(tail)
    }
}
