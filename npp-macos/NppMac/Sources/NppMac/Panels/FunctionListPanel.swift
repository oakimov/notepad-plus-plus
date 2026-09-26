import AppKit

/// Extracted symbol for the Function List panel.
struct FunctionSymbol {
    var name: String
    var line: Int // 1-based
}

/// Right-side list of functions/classes for the current language.
final class FunctionListPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var symbols: [FunctionSymbol] = []
    var onJump: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = NSTextField(labelWithString: "Function List")
        header.font = NSFont.boldSystemFont(ofSize: 11)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Symbol"
        col.width = 180
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 20
        table.style = .plain
        table.action = #selector(rowClicked)
        table.target = self
        table.doubleAction = #selector(rowClicked)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func reload(text: String, language: String) {
        symbols = Self.extract(from: text, language: language)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { symbols.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.translatesAutoresizingMaskIntoConstraints = false
            t.lineBreakMode = .byTruncatingTail
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let sym = symbols[row]
        cell.textField?.stringValue = "\(sym.name)  · \(sym.line)"
        return cell
    }

    @objc private func rowClicked() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard symbols.indices.contains(row) else { return }
        onJump?(symbols[row].line)
    }

    /// Language-keyed patterns; group 1 = display name when present.
    static func extract(from text: String, language: String) -> [FunctionSymbol] {
        let patterns: [String]
        switch language {
        case "rust":
            patterns = [#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:const\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)"#]
        case "python", "gdscript":
            patterns = [
                #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                #"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            ]
        case "javascript", "javascript.js", "typescript":
            patterns = [
                #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)"#,
                #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\("#,
                #"^\s*(?:export\s+)?class\s+([A-Za-z_$][\w$]*)"#,
            ]
        case "go":
            patterns = [#"^\s*func\s+(?:\([^)]+\)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\("#]
        case "java", "cs", "cpp", "c", "objc", "swift":
            patterns = [
                #"^\s*(?:public|private|protected|internal|static|final|override|virtual|async|export)?(?:\s+\w+)*\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*\{?\s*$"#,
                #"^\s*(?:public|private|protected)?\s*(?:static\s+)?(?:class|struct|enum|interface|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            ]
        case "ruby":
            patterns = [
                #"^\s*def\s+([A-Za-z_][A-Za-z0-9_?!]*)"#,
                #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            ]
        case "lua":
            patterns = [#"^\s*(?:local\s+)?function\s+([A-Za-z_][A-Za-z0-9_.:]*)"#]
        case "bash":
            patterns = [#"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"#]
        default:
            patterns = [
                #"^\s*(?:def|fn|function|func)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            ]
        }

        var out: [FunctionSymbol] = []
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            for pat in patterns {
                guard let re = try? NSRegularExpression(pattern: pat, options: []) else { continue }
                let range = NSRange(location: 0, length: (line as NSString).length)
                if let m = re.firstMatch(in: line, range: range) {
                    let name: String
                    if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                        name = (line as NSString).substring(with: m.range(at: 1))
                    } else {
                        name = line.trimmingCharacters(in: .whitespaces)
                    }
                    if !name.isEmpty {
                        out.append(FunctionSymbol(name: name, line: i + 1))
                        break
                    }
                }
            }
        }
        return out
    }
}
