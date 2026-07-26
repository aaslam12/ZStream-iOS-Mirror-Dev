//
//  MinimalMPVClient.swift
//  ZStream
//
//  Phase 0 spike: the smallest possible libmpv wrapper, using mpv's software
//  render API (no OpenGL/EAGL context juggling) so the only real unknowns are
//  "does mpv demux/decode this stream" — the actual question this spike
//  exists to answer — not render-pipeline plumbing. Lower performance than a
//  GPU-backed renderer, acceptable for proving feasibility.
//

import Foundation
import Libmpv

enum MPVSpikeError: Error, CustomStringConvertible {
    case createFailed
    case initFailed(Int32)
    case renderContextFailed(Int32)
    case commandFailed(Int32)

    var description: String {
        switch self {
        case .createFailed: return "mpv_create failed"
        case .initFailed(let code): return "mpv_initialize failed (\(code))"
        case .renderContextFailed(let code): return "mpv_render_context_create failed (\(code))"
        case .commandFailed(let code): return "mpv command failed (\(code))"
        }
    }
}

final class MinimalMPVClient {
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?

    func start(url: URL, headers: [String: String]?) throws {
        print("[mpv] start() url=\(url.absoluteString) headers=\(headers?.keys.sorted() ?? [])")
        guard let handle = mpv_create() else { throw MPVSpikeError.createFailed }
        mpv = handle

        mpv_set_option_string(handle, "vo", "libmpv")
        mpv_set_option_string(handle, "video-sync", "audio")
        mpv_set_option_string(handle, "hwdec", "no") // sw render path only decodes to CPU frames either way
        // "warn" swallows connection-establishment activity (DNS/TLS/HTTP
        // handshake) — a network-layer stall (blocked/rejected non-browser
        // client, hanging connect) produces zero output at that level, which
        // is indistinguishable from "nothing happened yet". "v" surfaces the
        // demuxer/network open attempts so a silent hang is actually visible.
        mpv_set_option_string(handle, "msg-level", "all=v")
        // Fail loud instead of hanging forever if the origin never responds.
        mpv_set_option_string(handle, "network-timeout", "15")
        // Route mpv's internal log messages into MPV_EVENT_LOG_MESSAGE so
        // pollEvents() can surface them via print() — otherwise a failure to
        // load/decode is invisible (no crash, no error, just a black frame
        // forever), which is exactly the "debugging blind" trap this spike
        // exists to avoid repeating.
        mpv_request_log_messages(handle, "v")

        let initResult = mpv_initialize(handle)
        guard initResult >= 0 else { throw MPVSpikeError.initFailed(initResult) }

        if let headers, !headers.isEmpty {
            let joined = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            mpv_set_option_string(handle, "http-header-fields", joined)
        }

        var ctx: OpaquePointer?
        let renderResult: Int32 = "sw".withCString { apiTypeCStr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypeCStr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&ctx, handle, &params)
        }
        guard renderResult >= 0, let ctx else { throw MPVSpikeError.renderContextFailed(renderResult) }
        renderContext = ctx

        let commandResult = command(["loadfile", url.absoluteString])
        print("[mpv] loadfile issued, result=\(commandResult)")
        guard commandResult >= 0 else { throw MPVSpikeError.commandFailed(commandResult) }
    }

    @discardableResult
    func command(_ args: [String]) -> Int32 {
        guard let mpv else { return -1 }
        let owned: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { owned.forEach { if let p = $0 { free(p) } } }
        var cArgs: [UnsafePointer<CChar>?] = owned.map { ptr -> UnsafePointer<CChar>? in
            guard let ptr else { return nil }
            return UnsafePointer(ptr)
        }
        cArgs.append(nil)
        return mpv_command(mpv, &cArgs)
    }

    func setProperty(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, name, value)
    }

    /// Renders exactly one frame into a freshly-allocated 32bpp BGRA buffer.
    /// Returns nil if there's no render context or nothing to render yet.
    func renderFrame(width: Int, height: Int) -> (bytes: [UInt8], bytesPerRow: Int)? {
        guard let renderContext else { return nil }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        var size: [Int32] = [Int32(width), Int32(height)]
        var stride = bytesPerRow

        let result: Int32 = "bgr0".withCString { formatCStr in
            withUnsafeMutablePointer(to: &size[0]) { sizePtr in
                withUnsafeMutablePointer(to: &stride) { stridePtr in
                    buffer.withUnsafeMutableBytes { bufPtr in
                        var params = [
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePtr)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: formatCStr)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePtr)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: bufPtr.baseAddress),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                        ]
                        return mpv_render_context_render(renderContext, &params)
                    }
                }
            }
        }
        guard result >= 0 else { return nil }
        return (buffer, bytesPerRow)
    }

    /// Drains and logs every pending mpv event since the last call — call
    /// this regularly (e.g. once per display-link tick) so log messages,
    /// load/decode errors, and end-of-file reasons actually reach
    /// DiagnosticsLog instead of silently vanishing.
    func pollEvents() {
        guard let mpv else { return }
        while true {
            guard let eventPtr = mpv_wait_event(mpv, 0) else { break }
            let event = eventPtr.pointee
            if event.event_id == MPV_EVENT_NONE { break }

            switch event.event_id {
            case MPV_EVENT_LOG_MESSAGE:
                if let data = event.data {
                    let msg = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    let prefix = msg.prefix.map { String(cString: $0) } ?? "?"
                    let level = msg.level.map { String(cString: $0) } ?? "?"
                    let text = msg.text.map { String(cString: $0) } ?? ""
                    print("[mpv/\(prefix)/\(level)] \(text.trimmingCharacters(in: .newlines))")
                }
            case MPV_EVENT_END_FILE:
                if let data = event.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    print("[mpv] END_FILE reason=\(end.reason.rawValue) error=\(end.error)")
                }
            case MPV_EVENT_FILE_LOADED:
                print("[mpv] FILE_LOADED")
            case MPV_EVENT_PLAYBACK_RESTART:
                print("[mpv] PLAYBACK_RESTART")
            default:
                break
            }
        }
    }

    func play() { setProperty("pause", "no") }
    func pause() { setProperty("pause", "yes") }

    func stop() {
        if let renderContext { mpv_render_context_free(renderContext) }
        renderContext = nil
        if let mpv { mpv_terminate_destroy(mpv) }
        mpv = nil
    }

    deinit { stop() }
}
