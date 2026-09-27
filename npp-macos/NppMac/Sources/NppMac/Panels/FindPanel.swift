import AppKit
import Foundation

/// Find/Replace bar + Find-in-Files (Search menu parity).
final class FindPanel: NSView {
    struct Options {
        var caseSensitive = false
        var wholeWord = false
        var regex = false
    }

    struct Request {
        var find: String
        var replace: String
        var replaceAll: Bool
        var replaceOne: Bool
        var findNext: Bool
        var countOnly: Bool
        var options: Options
    }

    struct Hit {
        var file: URL
        var line: Int
        var preview: String
    }

    private let onFind: (Request) -> Void
    private let onHide: () -> Void
    private var findField = NSTextField()
    private var replaceField = NSTextField()
    private var caseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private var wordBox = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    private var regexBox = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private var nextButton: NSButton!
    private var replaceOneButton: NSButton!
    private var replaceAllButton: NSButton!
    private var countButton: NSButton!
    private var hideButton: NSButton!

    var findText: String { findField.stringValue }

    init(onFind: @escaping (Request) -> Void, onHide: @escaping () -> Void) {
        self.onFind = onFind
        self.onHide = onHide
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        findField.placeholderString = "Find"
        replaceField.placeholderString = "Replace"
        // Return in the find field = Find Next.
        findField.target = self
        findField.action = #selector(nextClicked(_:))
        for field in [findField, replaceField] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        stack.addArrangedSubview(findField)
        stack.addArrangedSubview(replaceField)
        stack.addArrangedSubview(caseBox)
        stack.addArrangedSubview(wordBox)
        stack.addArrangedSubview(regexBox)

        nextButton = NSButton(title: "Find Next", target: self, action: #selector(nextClicked(_:)))
        nextButton.bezelStyle = .rounded
        stack.addArrangedSubview(nextButton)
        replaceOneButton = NSButton(title: "Replace", target: self, action: #selector(replaceOneClicked(_:)))
        replaceOneButton.bezelStyle = .rounded
        stack.addArrangedSubview(replaceOneButton)
        replaceAllButton = NSButton(title: "Replace All", target: self, action: #selector(replaceAllClicked(_:)))
        replaceAllButton.bezelStyle = .rounded
        stack.addArrangedSubview(replaceAllButton)
        countButton = NSButton(title: "Count", target: self, action: #selector(countClicked(_:)))
        countButton.bezelStyle = .rounded
        stack.addArrangedSubview(countButton)
        hideButton = NSButton(title: "Hide", target: self, action: #selector(hideClicked(_:)))
        hideButton.bezelStyle = .inline
        stack.addArrangedSubview(hideButton)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nativeLangDidChange(_:)),
            name: NativeLang.didChangeNotification,
            object: nil
        )
        applyLocalizedStrings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func nativeLangDidChange(_ note: Notification) {
        applyLocalizedStrings()
    }

    private func applyLocalizedStrings() {
        findField.placeholderString = NativeLang.dialogTitle(
            dialogId: "Find", attribute: "titleFind", fallback: "Find"
        )
        replaceField.placeholderString = NativeLang.dialogTitle(
            dialogId: "Find", attribute: "titleReplace", fallback: "Replace"
        )
        caseBox.title = NativeLang.dialogString(dialogId: "Find", itemId: "1604", fallback: "Match case")
        wordBox.title = NativeLang.dialogString(dialogId: "Find", itemId: "1603", fallback: "Whole word")
        regexBox.title = NativeLang.dialogString(dialogId: "Find", itemId: "1605", fallback: "Regex")
        nextButton.title = NativeLang.dialogString(dialogId: "Find", itemId: "1", fallback: "Find Next")
        replaceOneButton.title = NativeLang.dialogString(dialogId: "Find", itemId: "1608", fallback: "Replace")
        replaceAllButton.title = NativeLang.dialogString(dialogId: "Find", itemId: "1609", fallback: "Replace All")
        countButton.title = NativeLang.dialogString(dialogId: "Find", itemId: "1614", fallback: "Count")
        hideButton.title = NativeLang.dialogString(dialogId: "Global", itemId: "6134", fallback: "Hide")
    }

    func focusFind() {
        window?.makeFirstResponder(findField)
    }

    func focusReplace() {
        window?.makeFirstResponder(replaceField)
    }

    var options: Options {
        Options(caseSensitive: caseBox.state == .on, wholeWord: wordBox.state == .on, regex: regexBox.state == .on)
    }

    @objc private func nextClicked(_ sender: Any?) {
        onFind(Request(find: findField.stringValue, replace: replaceField.stringValue, replaceAll: false, replaceOne: false, findNext: true, countOnly: false, options: options))
    }

    @objc private func replaceOneClicked(_ sender: Any?) {
        onFind(Request(find: findField.stringValue, replace: replaceField.stringValue, replaceAll: false, replaceOne: true, findNext: false, countOnly: false, options: options))
    }

    @objc private func replaceAllClicked(_ sender: Any?) {
        onFind(Request(find: findField.stringValue, replace: replaceField.stringValue, replaceAll: true, replaceOne: false, findNext: false, countOnly: false, options: options))
    }

    @objc private func countClicked(_ sender: Any?) {
        onFind(Request(find: findField.stringValue, replace: replaceField.stringValue, replaceAll: false, replaceOne: false, findNext: false, countOnly: true, options: options))
    }

    @objc private func hideClicked(_ sender: Any?) {
        onHide()
    }

    /// Recursive find-in-files with filters / excludes and Find-panel options.
    func findInFiles(
        directory: URL,
        filters: String,
        excludes: String,
        options: Options,
        done: @escaping ([Hit]) -> Void
    ) {
        let needle = findField.stringValue
        let includeGlobs = Self.splitList(filters)
        let excludeParts = Self.splitList(excludes).map { $0.lowercased() }
        DispatchQueue.global(qos: .userInitiated).async {
            var hits: [Hit] = []
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                DispatchQueue.main.async { done([]) }
                return
            }
            for case let url as URL in enumerator {
                if hits.count > 2000 { break }
                // Skip excluded directory names (prune by telling enumerator to skip descendants).
                let pathLower = url.path.lowercased()
                if excludeParts.contains(where: { part in
                    guard !part.isEmpty else { return false }
                    return pathLower.contains("/\(part)/") || pathLower.hasSuffix("/\(part)")
                }) {
                    enumerator.skipDescendants()
                    continue
                }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                if !includeGlobs.isEmpty, !Self.matchesAnyGlob(url.lastPathComponent, globs: includeGlobs) {
                    continue
                }
                guard let data = try? Data(contentsOf: url), data.count < 5_000_000,
                      let text = String(data: data, encoding: .utf8)
                else { continue }
                guard !needle.isEmpty else { continue }
                let lineHits = Self.matchLines(in: text, needle: needle, options: options)
                for (line, preview) in lineHits {
                    hits.append(Hit(file: url, line: line, preview: preview))
                    if hits.count > 2000 { break }
                }
            }
            let result = hits
            DispatchQueue.main.async { done(result) }
        }
    }

    private static func splitList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func matchesAnyGlob(_ name: String, globs: [String]) -> Bool {
        for g in globs {
            if g == "*" || g == "*.*" { return true }
            if g.hasPrefix("*.") {
                let ext = String(g.dropFirst(2))
                if name.lowercased().hasSuffix("." + ext.lowercased()) { return true }
            } else if g.contains("*") {
                let pattern = NSRegularExpression.escapedPattern(for: g)
                    .replacingOccurrences(of: "\\*", with: ".*")
                if let re = try? NSRegularExpression(pattern: "^\(pattern)$", options: .caseInsensitive),
                   re.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) != nil
                {
                    return true
                }
            } else if name.caseInsensitiveCompare(g) == .orderedSame {
                return true
            }
        }
        return false
    }

    private static func matchLines(in text: String, needle: String, options: Options) -> [(Int, String)] {
        var out: [(Int, String)] = []
        let lines = text.components(separatedBy: "\n")
        if options.regex {
            var pattern = needle
            if options.wholeWord { pattern = "\\b(?:\(needle))\\b" }
            let reOpts: NSRegularExpression.Options = options.caseSensitive ? [] : .caseInsensitive
            guard let re = try? NSRegularExpression(pattern: pattern, options: reOpts) else { return [] }
            for (i, line) in lines.enumerated() {
                let range = NSRange(location: 0, length: (line as NSString).length)
                if re.firstMatch(in: line, range: range) != nil {
                    out.append((i + 1, String(line.prefix(160))))
                }
            }
            return out
        }
        let cmp: String.CompareOptions = options.caseSensitive ? [] : .caseInsensitive
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        for (i, line) in lines.enumerated() {
            var from = line.startIndex
            var matched = false
            while let r = line.range(of: needle, options: cmp, range: from..<line.endIndex) {
                if options.wholeWord {
                    let leftOK = r.lowerBound == line.startIndex || !isWord(line[line.index(before: r.lowerBound)])
                    let rightOK = r.upperBound == line.endIndex || !isWord(line[r.upperBound])
                    if leftOK, rightOK { matched = true; break }
                } else {
                    matched = true
                    break
                }
                from = r.upperBound
                if from == line.endIndex { break }
            }
            if matched {
                out.append((i + 1, String(line.prefix(160))))
            }
        }
        return out
    }
}
