import AppKit
import Foundation

// MARK: - Model

/// One `WordsStyle` row from a UDL v2.1 file.
struct UDLStyle: Equatable {
    var name: String
    var fgColor: String = "000000"
    var bgColor: String = "FFFFFF"
    var colorStyle: Int = 1
    var fontName: String = ""
    /// Bitmask: bold=1, italic=2, underline=4.
    var fontStyle: Int = 0
    var fontSize: String = ""
    /// Nesting bitmask (`UInt32`, matches `SCE_USER_MASK_NESTING_*`).
    var nesting: UInt32 = 0

    static func blank(name: String) -> UDLStyle {
        UDLStyle(name: name)
    }
}

/// Swift-side User Defined Language model (UI binding layer).
/// Swift-side CRUD + XML I/O; highlight engine syncs via `npp_udl_replace_all` / `npp_udl_load`.
struct UDLLanguage: Equatable {
    var name: String
    var ext: String = ""
    var udlVersion: String = "2.1"
    var darkModeTheme: Bool = false

    var caseIgnored: Bool = false
    var allowFoldOfComments: Bool = false
    var foldCompact: Bool = false
    var forcePureLC: Int = 0
    var decimalSeparator: Int = 0

    /// Prefix mode for Keywords1…Keywords8.
    var prefix: [Bool] = Array(repeating: false, count: 8)

    /// Keyword list name → content (preserves v2.1 names).
    var keywords: [String: String] = [:]

    /// Styles in document order.
    var styles: [UDLStyle] = []

    static let keywordListNames: [String] = [
        "Comments",
        "Numbers, prefix1", "Numbers, prefix2",
        "Numbers, extras1", "Numbers, extras2",
        "Numbers, suffix1", "Numbers, suffix2",
        "Numbers, range",
        "Operators1", "Operators2",
        "Folders in code1, open", "Folders in code1, middle", "Folders in code1, close",
        "Folders in code2, open", "Folders in code2, middle", "Folders in code2, close",
        "Folders in comment, open", "Folders in comment, middle", "Folders in comment, close",
        "Keywords1", "Keywords2", "Keywords3", "Keywords4",
        "Keywords5", "Keywords6", "Keywords7", "Keywords8",
        "Delimiters",
    ]

    static let styleNames: [String] = [
        "DEFAULT", "COMMENTS", "LINE COMMENTS", "NUMBERS",
        "KEYWORDS1", "KEYWORDS2", "KEYWORDS3", "KEYWORDS4",
        "KEYWORDS5", "KEYWORDS6", "KEYWORDS7", "KEYWORDS8",
        "OPERATORS",
        "FOLDER IN CODE1", "FOLDER IN CODE2", "FOLDER IN COMMENT",
        "DELIMITERS1", "DELIMITERS2", "DELIMITERS3", "DELIMITERS4",
        "DELIMITERS5", "DELIMITERS6", "DELIMITERS7", "DELIMITERS8",
    ]

    /// 21 nesting checkboxes shown in the styler sheet (label + bit).
    static let nestingFlags: [(label: String, mask: UInt32)] = [
        ("Delimiter 1", 0x1),
        ("Delimiter 2", 0x2),
        ("Delimiter 3", 0x4),
        ("Delimiter 4", 0x8),
        ("Delimiter 5", 0x10),
        ("Delimiter 6", 0x20),
        ("Delimiter 7", 0x40),
        ("Delimiter 8", 0x80),
        ("Comment", 0x100),
        ("Comment line", 0x200),
        ("Keyword 1", 0x400),
        ("Keyword 2", 0x800),
        ("Keyword 3", 0x1000),
        ("Keyword 4", 0x2000),
        ("Keyword 5", 0x4000),
        ("Keyword 6", 0x8000),
        ("Keyword 7", 0x10000),
        ("Keyword 8", 0x20000),
        ("Operators 1", 0x1000000),
        ("Operators 2", 0x2000000),
        ("Numbers", 0x4000000),
    ]

    static func blank(name: String = "new user define") -> UDLLanguage {
        var lang = UDLLanguage(name: name)
        for n in keywordListNames { lang.keywords[n] = "" }
        lang.styles = styleNames.map { UDLStyle.blank(name: $0) }
        return lang
    }

    /// Engine key matching Rust `udl_slug`.
    var engineKey: String {
        var s = "udl_"
        for c in name {
            if c.isASCII && (c.isLetter || c.isNumber) {
                s.append(c.lowercased())
            } else if c == " " || c == "-" || c == "_" {
                if !s.hasSuffix("_") { s.append("_") }
            }
        }
        while s.hasSuffix("_") { s.removeLast() }
        if s == "udl" { s.append("_lang") }
        return s
    }

    func keyword(_ name: String) -> String { keywords[name] ?? "" }

    mutating func setKeyword(_ name: String, _ value: String) {
        keywords[name] = value
    }

    mutating func ensureDefaults() {
        for n in Self.keywordListNames where keywords[n] == nil {
            keywords[n] = ""
        }
        let byName = Dictionary(uniqueKeysWithValues: styles.map { ($0.name, $0) })
        styles = Self.styleNames.map { byName[$0] ?? UDLStyle.blank(name: $0) }
        if prefix.count < 8 {
            prefix.append(contentsOf: Array(repeating: false, count: 8 - prefix.count))
        } else if prefix.count > 8 {
            prefix = Array(prefix.prefix(8))
        }
    }

    mutating func style(named name: String) -> UDLStyle {
        if let i = styles.firstIndex(where: { $0.name == name }) {
            return styles[i]
        }
        let s = UDLStyle.blank(name: name)
        styles.append(s)
        return s
    }

    mutating func updateStyle(named name: String, _ update: (inout UDLStyle) -> Void) {
        if let i = styles.firstIndex(where: { $0.name == name }) {
            update(&styles[i])
        } else {
            var s = UDLStyle.blank(name: name)
            update(&s)
            styles.append(s)
        }
    }
}

// MARK: - Encoded keyword helpers (Comments / Delimiters)

/// Encode/decode N++ UDL prefixed lists (`00token 01…`).
enum UDLEncodedList {
    /// Pull field text for a two-digit (or more) prefix from an encoded keyword string.
    static func retrieve(from encoded: String, prefix: String) -> String {
        guard prefix.count >= 2 else { return "" }
        let chars = Array(encoded)
        var out = ""
        var begin2Copy = false
        var inGroup = false
        var i = 0
        while i < chars.count {
            let atTokenStart = (i == 0 || chars[i - 1] == " ")
            if atTokenStart,
               i + 1 < chars.count,
               chars[i] == prefix[prefix.startIndex],
               chars[i + 1] == prefix[prefix.index(after: prefix.startIndex)],
               (prefix.count == 2 || matchesPrefix(chars, at: i, prefix: prefix))
            {
                if !out.isEmpty { out.append(" ") }
                begin2Copy = true
                i += prefix.count
                continue
            }

            if i + 1 < chars.count,
               chars[i] == "(",
               chars[i + 1] == "(",
               !inGroup,
               begin2Copy
            {
                inGroup = true
            }
            if i >= 2,
               chars[i] != ")",
               chars[i - 1] == ")",
               chars[i - 2] == ")",
               inGroup
            {
                inGroup = false
            }
            if chars[i] == " ", begin2Copy {
                begin2Copy = false
            }
            if begin2Copy || inGroup {
                out.append(chars[i])
            }
            i += 1
        }
        return out
    }

    /// Encode field texts with sequential prefixes `00`, `01`, … into one keyword string.
    static func convert(fields: [String]) -> String {
        var dest = ""
        for (idx, field) in fields.enumerated() {
            let prefix = String(format: "%02d", idx)
            if !dest.isEmpty { dest.append(" ") }
            dest.append(prefix)
            appendConverted(field, prefix: prefix, into: &dest)
        }
        return dest
    }

    private static func matchesPrefix(_ chars: [Character], at i: Int, prefix: String) -> Bool {
        let p = Array(prefix)
        guard i + p.count <= chars.count else { return false }
        for j in 0..<p.count where chars[i + j] != p[j] { return false }
        return true
    }

    private static func appendConverted(_ toConvert: String, prefix: String, into dest: inout String) {
        let chars = Array(toConvert)
        var inGroup = false
        var i = 0
        while i < chars.count {
            if i == 0, i + 1 < chars.count, chars[i] == "(", chars[i + 1] == "(" {
                inGroup = true
            } else if i + 2 < chars.count,
                      chars[i] == " ",
                      chars[i + 1] == "(",
                      chars[i + 2] == "("
            {
                inGroup = true
                dest.append(" ")
                dest.append(prefix)
                i += 1
                continue
            }
            if i >= 2, inGroup, chars[i - 1] == ")", chars[i - 2] == ")" {
                inGroup = false
            }
            if chars[i] == " " {
                if i + 1 < chars.count, chars[i + 1] != " " {
                    dest.append(" ")
                    if !inGroup { dest.append(prefix) }
                }
            } else {
                dest.append(chars[i])
            }
            i += 1
        }
    }
}

extension UDLLanguage {
    /// Comment tab fields: line open / continue / close, block open / close.
    var commentFields: [String] {
        get {
            let enc = keyword("Comments")
            return (0..<5).map { UDLEncodedList.retrieve(from: enc, prefix: String(format: "%02d", $0)) }
        }
        set {
            var fields = newValue
            while fields.count < 5 { fields.append("") }
            setKeyword("Comments", UDLEncodedList.convert(fields: Array(fields.prefix(5))))
        }
    }

    /// Eight delimiter rows: open / escape / close each.
    var delimiterFields: [[String]] {
        get {
            let enc = keyword("Delimiters")
            return (0..<8).map { d in
                (0..<3).map { part in
                    UDLEncodedList.retrieve(from: enc, prefix: String(format: "%02d", d * 3 + part))
                }
            }
        }
        set {
            var flat: [String] = []
            for d in 0..<8 {
                let row = d < newValue.count ? newValue[d] : ["", "", ""]
                for p in 0..<3 {
                    flat.append(p < row.count ? row[p] : "")
                }
            }
            setKeyword("Delimiters", UDLEncodedList.convert(fields: flat))
        }
    }
}

// MARK: - XML parse / write

enum UDLXML {
    static func parse(data: Data) throws -> [UDLLanguage] {
        let parser = UDLXMLParser()
        return try parser.parse(data: data)
    }

    static func parse(contentsOf url: URL) throws -> [UDLLanguage] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func serialize(_ languages: [UDLLanguage]) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n"
        for lang in languages {
            out += serializeUserLang(lang, indent: "    ")
        }
        out += "</NotepadPlus>\n"
        return out
    }

    static func serializeSingle(_ lang: UDLLanguage) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n"
        out += serializeUserLang(lang, indent: "    ")
        out += "</NotepadPlus>\n"
        return out
    }

    private static func serializeUserLang(_ lang: UDLLanguage, indent: String) -> String {
        var L = lang
        L.ensureDefaults()
        var s = ""
        s += "\(indent)<UserLang name=\"\(escAttr(L.name))\" ext=\"\(escAttr(L.ext))\""
        if L.darkModeTheme { s += " darkModeTheme=\"yes\"" }
        s += " udlVersion=\"\(escAttr(L.udlVersion))\">\n"
        s += "\(indent)    <Settings>\n"
        s += "\(indent)        <Global"
        s += " caseIgnored=\"\(yesNo(L.caseIgnored))\""
        s += " allowFoldOfComments=\"\(yesNo(L.allowFoldOfComments))\""
        s += " foldCompact=\"\(yesNo(L.foldCompact))\""
        s += " forcePureLC=\"\(L.forcePureLC)\""
        s += " decimalSeparator=\"\(L.decimalSeparator)\" />\n"
        s += "\(indent)        <Prefix"
        for i in 0..<8 {
            s += " Keywords\(i + 1)=\"\(yesNo(L.prefix[i]))\""
        }
        s += " />\n"
        s += "\(indent)    </Settings>\n"
        s += "\(indent)    <KeywordLists>\n"
        for name in UDLLanguage.keywordListNames {
            let body = escText(L.keyword(name))
            s += "\(indent)        <Keywords name=\"\(escAttr(name))\">\(body)</Keywords>\n"
        }
        s += "\(indent)    </KeywordLists>\n"
        s += "\(indent)    <Styles>\n"
        for st in L.styles {
            s += "\(indent)        <WordsStyle"
            s += " name=\"\(escAttr(st.name))\""
            s += " fgColor=\"\(escAttr(st.fgColor))\""
            s += " bgColor=\"\(escAttr(st.bgColor))\""
            s += " colorStyle=\"\(st.colorStyle)\""
            s += " fontName=\"\(escAttr(st.fontName))\""
            s += " fontStyle=\"\(st.fontStyle)\""
            if !st.fontSize.isEmpty {
                s += " fontSize=\"\(escAttr(st.fontSize))\""
            }
            s += " nesting=\"\(st.nesting)\" />\n"
        }
        s += "\(indent)    </Styles>\n"
        s += "\(indent)</UserLang>\n"
        return s
    }

    private static func yesNo(_ v: Bool) -> String { v ? "yes" : "no" }

    private static func escAttr(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escText(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class UDLXMLParser: NSObject, XMLParserDelegate {
    private var languages: [UDLLanguage] = []
    private var current: UDLLanguage?
    private var inKeywords = false
    private var currentKeywordName: String?
    private var textBuffer = ""
    private var parseError: Error?

    func parse(data: Data) throws -> [UDLLanguage] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.shouldProcessNamespaces = false
        guard p.parse() else {
            throw p.parserError ?? NSError(
                domain: "UDLXML",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "UDL XML parse failed"]
            )
        }
        if let parseError { throw parseError }
        return languages
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""
        switch elementName {
        case "UserLang":
            var lang = UDLLanguage.blank(name: attributeDict["name"] ?? "unnamed")
            lang.name = attributeDict["name"] ?? lang.name
            lang.ext = attributeDict["ext"] ?? ""
            lang.udlVersion = attributeDict["udlVersion"] ?? "2.1"
            lang.darkModeTheme = isYes(attributeDict["darkModeTheme"])
            current = lang
        case "Global":
            guard current != nil else { return }
            current!.caseIgnored = isYes(attributeDict["caseIgnored"])
            current!.allowFoldOfComments = isYes(attributeDict["allowFoldOfComments"])
            current!.foldCompact = isYes(attributeDict["foldCompact"])
            current!.forcePureLC = Int(attributeDict["forcePureLC"] ?? "0") ?? 0
            current!.decimalSeparator = Int(attributeDict["decimalSeparator"] ?? "0") ?? 0
        case "Prefix":
            guard current != nil else { return }
            for i in 0..<8 {
                current!.prefix[i] = isYes(attributeDict["Keywords\(i + 1)"])
            }
        case "Keywords":
            inKeywords = true
            currentKeywordName = attributeDict["name"]
            textBuffer = ""
        case "WordsStyle":
            guard current != nil else { return }
            var st = UDLStyle.blank(name: attributeDict["name"] ?? "DEFAULT")
            st.name = attributeDict["name"] ?? st.name
            st.fgColor = attributeDict["fgColor"] ?? st.fgColor
            st.bgColor = attributeDict["bgColor"] ?? st.bgColor
            st.colorStyle = Int(attributeDict["colorStyle"] ?? "1") ?? 1
            st.fontName = attributeDict["fontName"] ?? ""
            st.fontStyle = Int(attributeDict["fontStyle"] ?? "0") ?? 0
            st.fontSize = attributeDict["fontSize"] ?? ""
            st.nesting = UInt32(attributeDict["nesting"] ?? "0") ?? 0
            if let idx = current!.styles.firstIndex(where: { $0.name == st.name }) {
                current!.styles[idx] = st
            } else {
                current!.styles.append(st)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inKeywords { textBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "Keywords":
            if let name = currentKeywordName, current != nil {
                current!.keywords[name] = textBuffer
            }
            inKeywords = false
            currentKeywordName = nil
            textBuffer = ""
        case "UserLang":
            if var lang = current {
                lang.ensureDefaults()
                languages.append(lang)
            }
            current = nil
        default:
            break
        }
    }

    private func isYes(_ v: String?) -> Bool {
        guard let v else { return false }
        return v == "yes" || v == "true" || v == "1"
    }
}

// MARK: - Store

/// App Support persistence for user-defined languages (Swift XML I/O).
/// Engine highlight sync: `npp_udl_replace_all` on the multi-lang store path.
final class UDLStore {
    static let shared = UDLStore()
    static let didChangeNotification = Notification.Name("NppMac.UDLStore.didChange")

    private(set) var languages: [UDLLanguage] = []

    var names: [String] { languages.map(\.name) }

    private init() {
        reloadFromDisk()
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NppMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `~/Library/Application Support/NppMac/userDefineLang.xml`
    static var multiLangURL: URL {
        supportDir.appendingPathComponent("userDefineLang.xml")
    }

    /// `~/Library/Application Support/NppMac/userDefineLangs/`
    static var langsFolderURL: URL {
        let dir = supportDir.appendingPathComponent("userDefineLangs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func reloadFromDisk() {
        let url = Self.multiLangURL
        guard FileManager.default.fileExists(atPath: url.path),
              let parsed = try? UDLXML.parse(contentsOf: url)
        else {
            languages = []
            return
        }
        languages = parsed
    }

    func language(named name: String) -> UDLLanguage? {
        languages.first { $0.name == name }
    }

    func index(named name: String) -> Int? {
        languages.firstIndex { $0.name == name }
    }

    @discardableResult
    func upsert(_ lang: UDLLanguage) -> Int {
        var L = lang
        L.ensureDefaults()
        if let i = index(named: L.name) {
            languages[i] = L
            return i
        }
        languages.append(L)
        return languages.count - 1
    }

    func remove(named name: String) {
        languages.removeAll { $0.name == name }
    }

    func rename(from old: String, to new: String) throws {
        guard !new.isEmpty else {
            throw NSError(domain: "UDLStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        guard index(named: new) == nil || old == new else {
            throw NSError(domain: "UDLStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "A language named “\(new)” already exists"])
        }
        guard let i = index(named: old) else { return }
        languages[i].name = new
    }

    /// Write multi-lang store to App Support.
    func save() throws {
        let xml = UDLXML.serialize(languages)
        try xml.write(to: Self.multiLangURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Import one or more UserLang entries from a `.udl.xml` / multi-lang file.
    /// Same `name` replaces the existing entry (Load UDL / re-import).
    @discardableResult
    func importFile(at url: URL) throws -> [String] {
        let parsed = try UDLXML.parse(contentsOf: url)
        var imported: [String] = []
        for var lang in parsed {
            lang.ensureDefaults()
            upsert(lang)
            let dest = Self.langsFolderURL
                .appendingPathComponent("\(sanitizeFileName(lang.name)).udl.xml")
            try UDLXML.serializeSingle(lang).write(to: dest, atomically: true, encoding: .utf8)
            imported.append(lang.name)
        }
        try save()
        return imported
    }

    func export(named name: String, to url: URL) throws {
        guard let lang = language(named: name) else {
            throw NSError(domain: "UDLStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Language not found"])
        }
        try UDLXML.serializeSingle(lang).write(to: url, atomically: true, encoding: .utf8)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
