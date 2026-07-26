//
//  DiagnosticsLog.swift
//  ZStream
//
//  In-memory capture of everything the app prints (source resolution, player
//  status, errors -- any print() call anywhere), so it can be exported from
//  within the app. Needed because sideloaded builds only expose the OS's
//  legacy syslog relay, which doesn't carry os_log/os.Logger output at all,
//  and nobody has a debugger attached -- an in-app export is the only
//  reliable way for an external user to hand us logs.
//
//  Captures by redirecting stdout/stderr at the file-descriptor level (same
//  technique AppLogger uses for its file), so no call site anywhere needs to
//  be edited to route through this. Clears on relaunch (memory only, never
//  written to disk) and caps at a fixed number of lines.
//

import Foundation

final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let lock = NSLock()
    private var lines: [String] = []
    // Byte budget, not a line count -- a single resolve attempt can print a
    // lot (per-source status, player pipeline chatter), so cap by size
    // instead of guessing a "reasonable" line count. 8MB is generous for a
    // whole debugging session while staying well under what ShareLink/Data
    // handles comfortably in memory.
    private let byteBudget = 8 * 1024 * 1024
    private var currentBytes = 0

    private let queue = DispatchQueue(label: "diagnostics.log", qos: .utility)
    // Retained for the app's lifetime -- a Pipe whose FileHandles aren't held
    // anywhere else can be deallocated (closing its fds and dropping the
    // readabilityHandler) right after setup, silently ending capture.
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    /// Call once, as early as possible in app startup, after any other stdout/stderr
    /// redirection (whichever redirects last "wins" the file descriptor).
    func start() {
        pipeStandardStream(STDOUT_FILENO, buffer: stdout, pipe: &stdoutPipe)
        pipeStandardStream(STDERR_FILENO, buffer: stderr, pipe: &stderrPipe)
    }

    private func pipeStandardStream(_ fd: Int32, buffer: UnsafeMutablePointer<FILE>, pipe pipeSlot: inout Pipe?) {
        setvbuf(buffer, nil, _IONBF, 0)
        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        pipeSlot = pipe
    }

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        var trimmed = text
        if trimmed.hasSuffix("\n") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return }
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            log(String(line))
        }
    }

    func log(_ message: String) {
        let stamped = "\(Self.timestampFormatter.string(from: Date())) \(message)"
        lock.lock()
        lines.append(stamped)
        currentBytes += stamped.utf8.count
        while currentBytes > byteBudget, !lines.isEmpty {
            currentBytes -= lines.removeFirst().utf8.count
        }
        lock.unlock()
    }

    /// The full captured buffer, oldest first, one line per entry.
    /// Hand this to whatever writes it to a user-picked file location.
    var exportText: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        currentBytes = 0
        lock.unlock()
    }
}
