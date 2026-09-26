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

        let next = NSButton(title: "Find Next", target: self, action: #selector(nextClicked(_:)))
        next.bezelStyle = .rounded
        stack.addArrangedSubview(next)
        let replaceOne = NSButton(title: "Replace", target: self, action: #selector(replaceOneClicked(_:)))
        replaceOne.bezelStyle = .rounded
        stack.addArrangedSubview(replaceOne)
        let all = NSButton(title: "Replace All", target: self, action: #selector(replaceAllClicked(_:)))
        all.bezelStyle = .rounded
        stack.addArrangedSubview(all)
        let count = NSButton(title: "Count", target: self, action: #selector(countClicked(_:)))
        count.bezelStyle = .rounded
        stack.addArrangedSubview(count)
        let hide = NSButton(title: "Hide", target: self, action: #selector(hideClicked(_:)))
        hide.bezelStyle = .inline
        stack.addArrangedSubview(hide)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

    /// Recursive literal find-in-files over `directory`.
    func findInFiles(directory: URL, done: @escaping ([Hit]) -> Void) {
        let needle = findField.stringValue
        let caseSensitive = caseBox.state == .on
        DispatchQueue.global(qos: .userInitiated).async {
            var hits: [Hit] = []
            let fm = FileManager.default
            if let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator {
                    if hits.count > 2000 { break }
                    guard let data = try? Data(contentsOf: url), data.count < 5_000_000,
                          let text = String(data: data, encoding: .utf8)
                    else { continue }
                    let cmp: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
                    if text.range(of: needle, options: cmp) == nil || needle.isEmpty { continue }
                    for (i, line) in text.components(separatedBy: "\n").enumerated() {
                        if line.range(of: needle, options: cmp) != nil {
                            hits.append(Hit(file: url, line: i + 1, preview: String(line.prefix(160))))
                            if hits.count > 2000 { break }
                        }
                    }
                }
            }
            let result = hits
            DispatchQueue.main.async { done(result) }
        }
    }
}
