import AppKit
import Foundation
import Cnpp_ffi

/// Swift wrapper around the Rust `npp_ffi` engine (main-thread only).
final class NppEngine {
    private let ptr: OpaquePointer

    /// `langsModel`: path to `langs.model.xml` for keyword highlighting (nil ⇒ in-repo fallback).
    init(langsModel: String? = nil) {
        let created = langsModel.map { $0.withCString { npp_engine_create_with_langs($0) } } ?? npp_engine_create()
        guard let p = created else {
            fatalError("npp_engine_create failed")
        }
        ptr = p
    }

    deinit {
        npp_engine_destroy(ptr)
    }

    var count: Int { Int(npp_doc_count(ptr)) }

    var selectedIndex: Int {
        Int(npp_doc_selected(ptr))
    }

    @discardableResult
    func newDocument() -> Int {
        Int(npp_doc_new(ptr))
    }

    @discardableResult
    func open(path: String) -> Int? {
        let idx = path.withCString { npp_doc_open(ptr, $0) }
        return idx >= 0 ? Int(idx) : nil
    }

    @discardableResult
    func close(at index: Int) -> Bool {
        npp_doc_close(ptr, Int32(index))
    }

    @discardableResult
    func select(at index: Int) -> Bool {
        npp_doc_select(ptr, Int32(index))
    }

    @discardableResult
    func moveTab(from: Int, to: Int) -> Bool {
        npp_doc_move(ptr, Int32(from), Int32(to))
    }

    func title(at index: Int) -> String {
        Self.takeString(npp_doc_title(ptr, Int32(index)))
    }

    func path(at index: Int) -> String? {
        let s = Self.takeString(npp_doc_path(ptr, Int32(index)))
        return s.isEmpty ? nil : s
    }

    func text(at index: Int) -> String {
        Self.takeString(npp_doc_text(ptr, Int32(index)))
    }

    func language(at index: Int) -> String {
        let s = Self.takeString(npp_doc_language(ptr, Int32(index)))
        return s.isEmpty ? "normal" : s
    }

    @discardableResult
    func setLanguage(at index: Int, _ language: String) -> Bool {
        language.withCString { npp_doc_set_language(ptr, Int32(index), $0) }
    }

    /// Stock languages for the Language menu (`(key, displayName)`).
    func languages() -> [(key: String, display: String)] {
        let n = Int(npp_lang_count(ptr))
        var out: [(String, String)] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let key = Self.takeString(npp_lang_name(ptr, Int32(i)))
            let display = Self.takeString(npp_lang_display_name(ptr, Int32(i)))
            if !key.isEmpty {
                out.append((key, display.isEmpty ? key : display))
            }
        }
        return out
    }

    static func displayName(for language: String) -> String {
        language.withCString { c in
            let s = takeString(npp_lang_display_name_for(c))
            return s.isEmpty ? language : s
        }
    }

    func isDirty(at index: Int) -> Bool {
        npp_doc_is_dirty(ptr, Int32(index))
    }

    func encoding(at index: Int) -> DocEncoding {
        DocEncoding(rawValue: Int32(npp_doc_encoding(ptr, Int32(index)).rawValue)) ?? .utf8
    }

    func setEncoding(at index: Int, _ enc: DocEncoding) {
        let cEnc = NppEncoding(rawValue: UInt32(enc.rawValue))
        _ = npp_doc_set_encoding(ptr, Int32(index), cEnc)
    }

    func eol(at index: Int) -> DocEol {
        DocEol(rawValue: Int32(npp_doc_eol(ptr, Int32(index)).rawValue)) ?? .crlf
    }

    func setEol(at index: Int, _ eol: DocEol) {
        let cEol = NppEol(rawValue: UInt32(eol.rawValue))
        _ = npp_doc_set_eol(ptr, Int32(index), cEol)
    }

    func setText(at index: Int, _ text: String) {
        // withCString truncates on interior NUL — strip first.
        let safe = text.replacingOccurrences(of: "\0", with: "\u{FFFD}")
        safe.withCString { _ = npp_doc_set_text(ptr, Int32(index), $0) }
    }

    func save(at index: Int, path: String?) throws {
        var err: UnsafeMutablePointer<CChar>?
        let ok: Bool
        if let path {
            ok = path.withCString { npp_doc_save(ptr, Int32(index), $0, &err) }
        } else {
            ok = npp_doc_save(ptr, Int32(index), nil, &err)
        }
        if let err {
            let msg = Self.takeString(err)
            throw NSError(domain: "NppEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        if !ok {
            throw NSError(domain: "NppEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Save failed"])
        }
    }

    func markSaved(at index: Int, title: String?, path: String?) {
        if let t = title, let p = path {
            t.withCString { tp in
                p.withCString { pp in
                    npp_doc_mark_saved(ptr, Int32(index), tp, pp)
                }
            }
        } else if let t = title {
            t.withCString { npp_doc_mark_saved(ptr, Int32(index), $0, nil) }
        } else if let p = path {
            p.withCString { npp_doc_mark_saved(ptr, Int32(index), nil, $0) }
        } else {
            npp_doc_mark_saved(ptr, Int32(index), nil, nil)
        }
    }

    static func language(forPath path: String) -> String {
        path.withCString { c in
            let s = takeString(npp_language_for_path(c))
            return s.isEmpty ? "normal" : s
        }
    }

    func language(forPath path: String) -> String {
        path.withCString { c in
            let s = Self.takeString(npp_language_for_path_ex(ptr, c))
            return s.isEmpty ? "normal" : s
        }
    }

    /// RGB color from stylers.model.xml for `scope` under `language`.
    func color(forScope scope: Int32, language: String) -> NSColor {
        let hex: String = language.withCString { langC in
            Self.takeString(npp_scope_fg(ptr, langC, UInt32(scope)))
        }
        return Self.color(fromRGBHex: hex) ?? Self.fallbackColor(forScope: scope)
    }

    struct Token {
        var range: NSRange
        var scope: Int32
    }

    func highlight(language: String, text: String) -> [Token] {
        if text.utf8.count > 2 * 1024 * 1024 { return [] }
        let safeText = text.replacingOccurrences(of: "\0", with: "\u{FFFD}")
        var out: UnsafeMutablePointer<NppToken>?
        let n = language.withCString { langC in
            safeText.withCString { textC in
                npp_highlight(ptr, langC, textC, &out)
            }
        }
        guard n > 0, let out else { return [] }
        defer { npp_tokens_free(out, n) }
        return Self.tokensFromUTF8(out, count: Int(n), text: safeText)
    }

    private static func takeString(_ c: UnsafeMutablePointer<CChar>?) -> String {
        guard let c else { return "" }
        defer { npp_string_free(c) }
        return String(validatingCString: c) ?? String(cString: c)
    }

    private static func color(fromRGBHex hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func fallbackColor(forScope scope: Int32) -> NSColor {
        switch scope {
        case 1: return NSColor.systemPurple
        case 2: return NSColor.systemTeal
        case 3: return NSColor.systemRed
        case 4: return NSColor.systemGray
        case 5: return NSColor.systemOrange
        case 6: return NSColor.systemBrown
        case 7: return NSColor.systemBlue
        case 8: return NSColor.systemPink
        default: return NSColor.textColor
        }
    }

    private static func tokensFromUTF8(_ out: UnsafeMutablePointer<NppToken>, count: Int, text: String) -> [Token] {
        var utf8ToUTF16 = [Int](repeating: -1, count: text.utf8.count + 1)
        var u8 = 0
        var u16 = 0
        utf8ToUTF16[0] = 0
        for ch in text {
            u8 += ch.utf8.count
            u16 += ch.utf16.count
            if u8 <= text.utf8.count {
                utf8ToUTF16[u8] = u16
            }
        }
        var tokens: [Token] = []
        tokens.reserveCapacity(count)
        for i in 0..<count {
            let t = out[i]
            let start8 = Int(t.start)
            let end8 = Int(t.end)
            guard start8 <= end8,
                  start8 < utf8ToUTF16.count,
                  end8 < utf8ToUTF16.count,
                  utf8ToUTF16[start8] >= 0,
                  utf8ToUTF16[end8] >= 0
            else { continue }
            let loc = utf8ToUTF16[start8]
            let len = utf8ToUTF16[end8] - loc
            guard len >= 0 else { continue }
            tokens.append(Token(range: NSRange(location: loc, length: len), scope: Int32(t.scope.rawValue)))
        }
        return tokens
    }
}

enum DocEncoding: Int32 {
    case utf8 = 0
    case utf8Bom = 1
    case utf16Le = 2
    case utf16Be = 3
    case ansi = 4

    var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8Bom: return "UTF-8-BOM"
        case .utf16Le: return "UTF-16LE"
        case .utf16Be: return "UTF-16BE"
        case .ansi: return "windows-1252"
        }
    }
}

enum DocEol: Int32 {
    case crlf = 0
    case lf = 1
    case cr = 2

    var label: String {
        switch self {
        case .crlf: return "CRLF"
        case .lf: return "LF"
        case .cr: return "CR"
        }
    }
}
