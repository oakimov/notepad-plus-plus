//! Syntax highlighting: tree-sitter registry with keyword fallback.
//!
//! Cached grammars (offline build) cover rust/python/javascript/typescript/
//! go/java/ruby/html/css/json/toml/xml/yaml. Languages without a grammar
//! tokenize via keyword lists + comment/string/number/operator scanners from
//! `langs.model.xml`, styled by `stylers.model.xml` colors.

mod queries;

use std::collections::{BTreeMap, BTreeSet};

/// Scope class for a token range (maps to WordsStyle rows / theme keys).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub enum Scope {
    /// Plain text.
    #[default]
    Default,
    /// Keywords (`INSTRUCTION WORD`, `TYPE WORD`).
    Keyword,
    /// `TYPE WORD`-class keywords.
    Type,
    /// String literals.
    Str,
    /// Comments.
    Comment,
    /// Numbers.
    Number,
    /// Operators.
    Operator,
    /// Function/method names.
    Function,
    /// Preprocessor / directives.
    Preproc,
}

/// A styled token range (byte offsets, char boundaries).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Token {
    /// Start byte.
    pub start: usize,
    /// End byte.
    pub end: usize,
    /// Scope class.
    pub scope: Scope,
}

/// Upstream `_shortName` display labels keyed by `langs.model.xml` `name`.
const DISPLAY_NAMES: &[(&str, &str)] = &[
    ("normal", "Normal text"),
    ("php", "PHP"),
    ("c", "C"),
    ("cpp", "C++"),
    ("cs", "C#"),
    ("objc", "Objective-C"),
    ("java", "Java"),
    ("rc", "RC"),
    ("html", "HTML"),
    ("xml", "XML"),
    ("makefile", "Makefile"),
    ("pascal", "Pascal"),
    ("batch", "Batch"),
    ("ini", "ini"),
    ("nfo", "NFO"),
    ("asp", "ASP"),
    ("sql", "SQL"),
    ("vb", "Visual Basic"),
    ("javascript", "Embedded JS"),
    ("css", "CSS"),
    ("perl", "Perl"),
    ("python", "Python"),
    ("lua", "Lua"),
    ("tex", "TeX"),
    ("fortran", "Fortran free form"),
    ("bash", "Shell"),
    ("actionscript", "ActionScript"),
    ("nsis", "NSIS"),
    ("tcl", "TCL"),
    ("lisp", "Lisp"),
    ("scheme", "Scheme"),
    ("asm", "Assembly"),
    ("diff", "Diff"),
    ("props", "Properties file"),
    ("postscript", "PostScript"),
    ("ruby", "Ruby"),
    ("smalltalk", "Smalltalk"),
    ("vhdl", "VHDL"),
    ("kix", "KiXtart"),
    ("autoit", "AutoIt"),
    ("caml", "CAML"),
    ("ada", "Ada"),
    ("verilog", "Verilog"),
    ("matlab", "MATLAB"),
    ("haskell", "Haskell"),
    ("inno", "Inno Setup"),
    ("cmake", "CMake"),
    ("yaml", "YAML"),
    ("cobol", "COBOL"),
    ("gui4cli", "Gui4Cli"),
    ("d", "D"),
    ("powershell", "PowerShell"),
    ("r", "R"),
    ("jsp", "JSP"),
    ("coffeescript", "CoffeeScript"),
    ("json", "json"),
    ("javascript.js", "JavaScript"),
    ("fortran77", "Fortran fixed form"),
    ("baanc", "BaanC"),
    ("srec", "S-Record"),
    ("ihex", "Intel HEX"),
    ("tehex", "Tektronix extended HEX"),
    ("swift", "Swift"),
    ("asn1", "ASN.1"),
    ("avs", "AviSynth"),
    ("blitzbasic", "BlitzBasic"),
    ("purebasic", "PureBasic"),
    ("freebasic", "FreeBasic"),
    ("csound", "Csound"),
    ("erlang", "Erlang"),
    ("escript", "ESCRIPT"),
    ("forth", "Forth"),
    ("latex", "LaTeX"),
    ("mmixal", "MMIXAL"),
    ("nim", "Nim"),
    ("nncrontab", "Nncrontab"),
    ("oscript", "OScript"),
    ("rebol", "REBOL"),
    ("registry", "registry"),
    ("rust", "Rust"),
    ("spice", "Spice"),
    ("txt2tags", "txt2tags"),
    ("visualprolog", "Visual Prolog"),
    ("typescript", "TypeScript"),
    ("json5", "json5"),
    ("mssql", "mssql"),
    ("gdscript", "GDScript"),
    ("hollywood", "Hollywood"),
    ("go", "Go"),
    ("raku", "Raku"),
    ("toml", "TOML"),
    ("sas", "SAS"),
    ("errorlist", "ErrorList"),
    ("escseq", "EscapeSequence (ANSI)"),
];

/// Languages omitted from the Language menu (internal / placeholders).
#[must_use]
pub fn is_menu_language(name: &str) -> bool {
    !matches!(
        name,
        "searchResult" | "udf" | "ext" | "javascript" /* Embedded JS; menu uses javascript.js */
    )
}

/// Human-readable menu / status label for a language key.
#[must_use]
pub fn display_name(lang: &str) -> &str {
    DISPLAY_NAMES
        .iter()
        .find(|(k, _)| *k == lang)
        .map(|(_, v)| *v)
        .unwrap_or(lang)
}

/// Prefer specific language keys when several XML entries claim the same extension.
const EXT_OVERRIDES: &[(&str, &str)] = &[
    ("c", "c"),
    ("h", "cpp"),
    ("hpp", "cpp"),
    ("hh", "cpp"),
    ("hxx", "cpp"),
    ("cs", "cs"),
    ("js", "javascript.js"),
    ("mjs", "javascript.js"),
    ("jsx", "javascript.js"),
    ("jsm", "javascript.js"),
    ("vue", "javascript.js"),
    ("ts", "typescript"),
    ("tsx", "typescript"),
    ("rs", "rust"),
    ("py", "python"),
    ("go", "go"),
    ("swift", "swift"),
    ("md", "normal"),
    ("markdown", "normal"),
];

/// Build `extension → language name` from `langs.model.xml` entries.
///
/// Later languages overwrite earlier ones unless [`EXT_OVERRIDES`] forces a key.
#[must_use]
pub fn build_extension_map(langs: &[(String, String)]) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    for (name, ext_list) in langs {
        if name == "searchResult" || name == "udf" || name == "ext" {
            continue;
        }
        for ext in ext_list.split_whitespace() {
            let key = ext.trim_start_matches('.').to_ascii_lowercase();
            if key.is_empty() {
                continue;
            }
            map.insert(key, name.clone());
        }
    }
    for (ext, lang) in EXT_OVERRIDES {
        map.insert((*ext).to_owned(), (*lang).to_owned());
    }
    map
}

/// Language key guessed from a file extension using a pre-built map.
#[must_use]
pub fn language_for_extension_map(ext: &str, map: &BTreeMap<String, String>) -> String {
    let key = ext.trim_start_matches('.').to_ascii_lowercase();
    map.get(&key)
        .cloned()
        .unwrap_or_else(|| "normal".to_owned())
}

/// Fallback when no XML map is loaded (tests / early init).
#[must_use]
pub fn language_for_extension(ext: &str) -> &'static str {
    match ext.to_ascii_lowercase().as_str() {
        "rs" => "rust",
        "py" | "pyw" => "python",
        "js" | "mjs" | "cjs" | "jsm" | "vue" => "javascript.js",
        "ts" | "tsx" | "jsx" => "typescript",
        "go" => "go",
        "java" => "java",
        "rb" => "ruby",
        "html" | "htm" => "html",
        "css" => "css",
        "json" => "json",
        "toml" => "toml",
        "xml" | "plist" | "xib" | "storyboard" | "xsd" | "xsl" => "xml",
        "yaml" | "yml" => "yaml",
        "cpp" | "cxx" | "cc" | "hpp" | "hh" | "hxx" | "ino" => "cpp",
        "c" => "c",
        "h" => "cpp",
        "cs" => "cs",
        "swift" => "swift",
        "sh" | "bash" => "bash",
        "md" | "markdown" => "normal",
        _ => "normal",
    }
}

/// Canonical grammar key (aliases for tree-sitter / keyword tables).
#[must_use]
pub fn grammar_key(lang: &str) -> &str {
    match lang {
        "javascript.js" | "javascript" => "javascript",
        "json5" => "json",
        other => other,
    }
}

/// Whether a tree-sitter grammar is linked for `lang`.
#[must_use]
pub fn has_grammar(lang: &str) -> bool {
    matches!(
        grammar_key(lang),
        "rust"
            | "python"
            | "javascript"
            | "typescript"
            | "go"
            | "java"
            | "ruby"
            | "html"
            | "css"
            | "json"
            | "toml"
            | "xml"
            | "yaml"
    )
}

fn language_grammar(lang: &str) -> Option<tree_sitter::Language> {
    match grammar_key(lang) {
        "rust" => Some(tree_sitter_rust::LANGUAGE.into()),
        "python" => Some(tree_sitter_python::LANGUAGE.into()),
        "javascript" => Some(tree_sitter_javascript::LANGUAGE.into()),
        "typescript" => Some(tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into()),
        "go" => Some(tree_sitter_go::LANGUAGE.into()),
        "java" => Some(tree_sitter_java::LANGUAGE.into()),
        "ruby" => Some(tree_sitter_ruby::LANGUAGE.into()),
        "html" => Some(tree_sitter_html::LANGUAGE.into()),
        "css" => Some(tree_sitter_css::LANGUAGE.into()),
        "json" => Some(tree_sitter_json::LANGUAGE.into()),
        "toml" => Some(tree_sitter_toml_ng::LANGUAGE.into()),
        "xml" => Some(tree_sitter_xml::LANGUAGE_XML.into()),
        "yaml" => Some(tree_sitter_yaml::LANGUAGE.into()),
        _ => None,
    }
}

fn scope_for_capture(name: &str) -> Scope {
    let base = name.split('.').next().unwrap_or(name);
    match base {
        // Tags share Keyword so XML/HTML styler "TAG" (blue) applies.
        "keyword" | "include" | "tag" => Scope::Keyword,
        // Attributes / CSS properties share Type so "ATTRIBUTE" styler applies.
        "type" | "constructor" | "property" | "attribute" => Scope::Type,
        "string" | "character" | "escape" => Scope::Str,
        "comment" => Scope::Comment,
        "number" | "boolean" | "constant" => Scope::Number,
        "operator" | "punctuation" => Scope::Operator,
        "function" | "method" => Scope::Function,
        "preproc" | "label" => Scope::Preproc,
        _ => Scope::Default,
    }
}

/// Per-grammar queries: node names differ across grammars.
fn query_for(lang: &str) -> &'static str {
    queries::query_source(grammar_key(lang))
}

/// Highlight with tree-sitter when a grammar exists, else `None`.
/// Falls back to `None` if the query fails to compile for the linked grammar.
///
/// For XML, HTML nested inside `<![CDATA[...]]>` is highlighted with the HTML
/// grammar (appcasts / feeds store HTML release notes there).
#[must_use]
pub fn highlight_tree_sitter(lang: &str, text: &str) -> Option<Vec<Token>> {
    let mut out = highlight_tree_sitter_raw(lang, text)?;
    if grammar_key(lang) == "xml" {
        out = overlay_cdata_html(text, out);
    }
    Some(out)
}

fn highlight_tree_sitter_raw(lang: &str, text: &str) -> Option<Vec<Token>> {
    let grammar = language_grammar(lang)?;
    let mut parser = tree_sitter::Parser::new();
    parser.set_language(&grammar).ok()?;
    let tree = parser.parse(text, None)?;
    let query = tree_sitter::Query::new(&grammar, query_for(lang)).ok()?;
    let mut cursor = tree_sitter::QueryCursor::new();
    let mut out = Vec::new();
    let mut matches = cursor.matches(&query, tree.root_node(), text.as_bytes());
    use streaming_iterator::StreamingIterator;
    while let Some(m) = matches.next() {
        for cap in m.captures {
            let node = cap.node;
            let name = query.capture_names()[cap.index as usize];
            let scope = scope_for_capture(name);
            if scope == Scope::Default {
                continue;
            }
            out.push(Token {
                start: node.start_byte(),
                end: node.end_byte(),
                scope,
            });
        }
    }
    out.sort_by_key(|t| (t.start, t.end));
    Some(out)
}

/// `<![CDATA[ ... ]]>` content starts/ends (byte offsets of the inner slice).
fn cdata_inner_ranges(text: &str) -> Vec<(usize, usize)> {
    const OPEN: &[u8] = b"<![CDATA[";
    const CLOSE: &[u8] = b"]]>";
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i + OPEN.len() <= bytes.len() {
        if &bytes[i..i + OPEN.len()] == OPEN {
            let content_start = i + OPEN.len();
            let mut j = content_start;
            while j + CLOSE.len() <= bytes.len() && &bytes[j..j + CLOSE.len()] != CLOSE {
                j += 1;
            }
            let content_end = if j + CLOSE.len() <= bytes.len() {
                j
            } else {
                bytes.len()
            };
            out.push((content_start, content_end));
            i = content_end + CLOSE.len().min(bytes.len().saturating_sub(content_end));
            continue;
        }
        i += 1;
    }
    out
}

fn overlay_cdata_html(text: &str, base: Vec<Token>) -> Vec<Token> {
    let mut out = base;
    for (cs, ce) in cdata_inner_ranges(text) {
        // Delimiters: color `<![CDATA[` / `]]>` as preprocessor.
        let open_start = cs.saturating_sub(9); // len("<![CDATA[")
        if open_start < cs {
            out.push(Token {
                start: open_start,
                end: cs,
                scope: Scope::Preproc,
            });
        }
        if ce + 3 <= text.len() && text.as_bytes()[ce..ce + 3] == *b"]]>" {
            out.push(Token {
                start: ce,
                end: ce + 3,
                scope: Scope::Preproc,
            });
        }
        if cs >= ce {
            continue;
        }
        let inner = &text[cs..ce];
        if let Some(html_toks) = highlight_tree_sitter_raw("html", inner) {
            for t in html_toks {
                out.push(Token {
                    start: t.start + cs,
                    end: t.end + cs,
                    scope: t.scope,
                });
            }
        }
    }
    out.sort_by_key(|t| (t.start, t.end));
    // Drop earlier tokens fully covered by a later more-specific span? Keep all;
    // Swift paints in order so later addAttribute wins for overlaps — apply
    // shorter/inner tokens last by sorting end-start descending within same start.
    out.sort_by(|a, b| a.start.cmp(&b.start).then_with(|| b.end.cmp(&a.end)));
    out
}

/// Merge overlay tokens into base; base ranges win on overlap.
#[must_use]
pub fn merge_tokens(base: Vec<Token>, overlay: Vec<Token>) -> Vec<Token> {
    let mut out = base;
    for t in overlay {
        if t.end <= t.start {
            continue;
        }
        let overlaps = out.iter().any(|b| t.start < b.end && t.end > b.start);
        if !overlaps {
            out.push(t);
        }
    }
    out.sort_by_key(|t| (t.start, t.end));
    out
}

/// Keyword tokenizer from `langs.model.xml` word lists.
fn is_ident_start(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

/// Continue identifier: alnum / `_` / `-` (COBOL `PROGRAM-ID`, CSS vendor tokens).
fn is_ident_continue(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_' || c == b'-'
}

/// Matching is ASCII word-boundary (case-insensitive); skips ranges covered by `exclude`.
/// Keyword sets from [`groups_from_keywords`] are stored lowercased.
#[must_use]
pub fn highlight_keywords(
    text: &str,
    groups: &[(Scope, &BTreeSet<String>)],
    exclude: &[(usize, usize)],
) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if exclude.iter().any(|&(a, b)| i >= a && i < b) {
            i += 1;
            continue;
        }
        let c = bytes[i];
        if is_ident_start(c) {
            let start = i;
            i += 1;
            while i < bytes.len() && is_ident_continue(bytes[i]) {
                i += 1;
            }
            // Trim trailing `-` so `foo-` / `a - b` edge cases don't swallow ops.
            while i > start + 1 && bytes[i - 1] == b'-' {
                i -= 1;
            }
            if exclude.iter().any(|&(a, b)| start < b && i > a) {
                continue;
            }
            let word = text[start..i].to_ascii_lowercase();
            for (scope, set) in groups {
                if set.contains(&word) {
                    out.push(Token {
                        start,
                        end: i,
                        scope: *scope,
                    });
                    break;
                }
            }
        } else {
            i += 1;
        }
    }
    out
}

/// Scan line/block comments and double/single-quoted strings.
#[must_use]
pub fn scan_comments_and_strings(
    text: &str,
    comment_line: &str,
    comment_start: &str,
    comment_end: &str,
) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let line_pat = comment_line.as_bytes();
    let start_pat = comment_start.as_bytes();
    let end_pat = comment_end.as_bytes();
    while i < bytes.len() {
        // Line comment
        if !line_pat.is_empty()
            && i + line_pat.len() <= bytes.len()
            && &bytes[i..i + line_pat.len()] == line_pat
        {
            let start = i;
            i += line_pat.len();
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            out.push(Token {
                start,
                end: i,
                scope: Scope::Comment,
            });
            continue;
        }
        // Fixed-form COBOL: `*` after only spaces on the line (commentLine is `*>`).
        if line_pat == b"*>"
            && bytes[i] == b'*'
            && (i == 0 || bytes[i - 1] == b'\n' || {
                let mut j = i;
                while j > 0 && bytes[j - 1] == b' ' {
                    j -= 1;
                }
                j == 0 || bytes[j - 1] == b'\n'
            })
        {
            let start = i;
            i += 1;
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            out.push(Token {
                start,
                end: i,
                scope: Scope::Comment,
            });
            continue;
        }
        // Block comment
        if !start_pat.is_empty()
            && !end_pat.is_empty()
            && i + start_pat.len() <= bytes.len()
            && &bytes[i..i + start_pat.len()] == start_pat
        {
            let start = i;
            i += start_pat.len();
            while i + end_pat.len() <= bytes.len() && &bytes[i..i + end_pat.len()] != end_pat {
                i += 1;
            }
            if i + end_pat.len() <= bytes.len() {
                i += end_pat.len();
            } else {
                i = bytes.len();
            }
            out.push(Token {
                start,
                end: i,
                scope: Scope::Comment,
            });
            continue;
        }
        // Double-quoted string
        if bytes[i] == b'"' {
            let start = i;
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'"' {
                    i += 1;
                    break;
                }
                if bytes[i] == b'\n' {
                    break;
                }
                i += 1;
            }
            out.push(Token {
                start,
                end: i,
                scope: Scope::Str,
            });
            continue;
        }
        // Single-quoted string (skip if line comment uses ')
        if bytes[i] == b'\'' && line_pat != b"'" {
            let start = i;
            i += 1;
            while i < bytes.len() {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    i += 2;
                    continue;
                }
                if bytes[i] == b'\'' {
                    i += 1;
                    break;
                }
                if bytes[i] == b'\n' {
                    break;
                }
                i += 1;
            }
            out.push(Token {
                start,
                end: i,
                scope: Scope::Str,
            });
            continue;
        }
        i += 1;
    }
    out
}

fn in_exclude(i: usize, exclude: &[(usize, usize)]) -> bool {
    exclude.iter().any(|&(a, b)| i >= a && i < b)
}

fn overlaps_exclude(start: usize, end: usize, exclude: &[(usize, usize)]) -> bool {
    exclude.iter().any(|&(a, b)| start < b && end > a)
}

/// Scan integer / float / hex / binary literals outside `exclude` ranges.
#[must_use]
pub fn scan_numbers(text: &str, exclude: &[(usize, usize)]) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if in_exclude(i, exclude) {
            i += 1;
            continue;
        }
        let c = bytes[i];
        // Hex / binary / octal prefixes
        if c == b'0' && i + 2 < bytes.len() && !in_exclude(i + 1, exclude) {
            let p = bytes[i + 1].to_ascii_lowercase();
            if p == b'x' || p == b'b' || p == b'o' {
                let start = i;
                i += 2;
                while i < bytes.len()
                    && (bytes[i].is_ascii_hexdigit() || bytes[i] == b'_')
                    && !in_exclude(i, exclude)
                {
                    i += 1;
                }
                if i > start + 2 && !overlaps_exclude(start, i, exclude) {
                    out.push(Token {
                        start,
                        end: i,
                        scope: Scope::Number,
                    });
                }
                continue;
            }
        }
        if c.is_ascii_digit() {
            // Don't treat digits mid-identifier as numbers.
            if i > 0 {
                let prev = bytes[i - 1];
                if prev.is_ascii_alphabetic() || prev == b'_' {
                    i += 1;
                    continue;
                }
            }
            let start = i;
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'_') {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == b'.' && i + 1 < bytes.len() && bytes[i + 1].is_ascii_digit()
            {
                i += 1;
                while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'_') {
                    i += 1;
                }
            }
            // Exponent
            if i < bytes.len() && (bytes[i] == b'e' || bytes[i] == b'E') {
                let mut j = i + 1;
                if j < bytes.len() && (bytes[j] == b'+' || bytes[j] == b'-') {
                    j += 1;
                }
                if j < bytes.len() && bytes[j].is_ascii_digit() {
                    i = j;
                    while i < bytes.len() && (bytes[i].is_ascii_digit() || bytes[i] == b'_') {
                        i += 1;
                    }
                }
            }
            // Suffix letters (u, l, f, etc.)
            while i < bytes.len() && bytes[i].is_ascii_alphabetic() {
                i += 1;
            }
            if !overlaps_exclude(start, i, exclude) {
                out.push(Token {
                    start,
                    end: i,
                    scope: Scope::Number,
                });
            }
            continue;
        }
        i += 1;
    }
    out
}

/// Multi-char then single-char operators outside `exclude`.
#[must_use]
pub fn scan_operators(text: &str, exclude: &[(usize, usize)]) -> Vec<Token> {
    const MULTI: &[&[u8]] = &[
        b"<<=", b">>=", b">>>", b"===", b"!==", b"<=>", b"...", b"??=", b"&&=", b"||=", b"**=",
        b"<<=", b">>=", b"<<", b">>", b"==", b"!=", b"<=", b">=", b"&&", b"||", b"??", b"?.",
        b"+=", b"-=", b"*=", b"/=", b"%=", b"&=", b"|=", b"^=", b"->", b"=>", b"::", b"++", b"--",
        b":=", b"<-", b"**", b"//",
    ];
    const SINGLE: &[u8] = b"+-*/%=<>!&|^~?:.";
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if in_exclude(i, exclude) {
            i += 1;
            continue;
        }
        let mut matched = false;
        for op in MULTI {
            if i + op.len() <= bytes.len() && &bytes[i..i + op.len()] == *op {
                // Avoid treating // as operator when it's a line comment start —
                // those ranges should already be excluded.
                let end = i + op.len();
                if !overlaps_exclude(i, end, exclude) {
                    out.push(Token {
                        start: i,
                        end,
                        scope: Scope::Operator,
                    });
                }
                i = end;
                matched = true;
                break;
            }
        }
        if matched {
            continue;
        }
        if SINGLE.contains(&bytes[i]) {
            out.push(Token {
                start: i,
                end: i + 1,
                scope: Scope::Operator,
            });
            i += 1;
            continue;
        }
        i += 1;
    }
    out
}

/// C-like `#directive` at line start (after whitespace), outside `exclude`.
#[must_use]
pub fn scan_preproc(text: &str, exclude: &[(usize, usize)]) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut line_start = true;
    while i < bytes.len() {
        if bytes[i] == b'\n' {
            line_start = true;
            i += 1;
            continue;
        }
        if line_start {
            while i < bytes.len() && (bytes[i] == b' ' || bytes[i] == b'\t') {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == b'#' && !in_exclude(i, exclude) {
                let start = i;
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
                if !overlaps_exclude(start, i, exclude) {
                    out.push(Token {
                        start,
                        end: i,
                        scope: Scope::Preproc,
                    });
                }
                line_start = false;
                continue;
            }
            line_start = false;
        }
        i += 1;
    }
    out
}

/// Full keyword-language highlight: comments/strings + numbers/ops/preproc + keywords.
#[must_use]
pub fn highlight_keyword_lang(
    text: &str,
    comment_line: &str,
    comment_start: &str,
    comment_end: &str,
    groups: &[(Scope, &BTreeSet<String>)],
) -> Vec<Token> {
    let structural = scan_comments_and_strings(text, comment_line, comment_start, comment_end);
    let mut exclude: Vec<(usize, usize)> = structural.iter().map(|t| (t.start, t.end)).collect();
    let mut out = structural;

    let nums = scan_numbers(text, &exclude);
    for t in &nums {
        exclude.push((t.start, t.end));
    }
    out = merge_tokens(out, nums);

    // Preproc before operators so `#include <foo>` is one directive, not ops.
    if comment_line != "#" {
        let pp = scan_preproc(text, &exclude);
        for t in &pp {
            exclude.push((t.start, t.end));
        }
        out = merge_tokens(out, pp);
    }

    // Keywords before operators so `PROGRAM-ID` / `working-storage` keep their hyphens.
    let kws = highlight_keywords(text, groups, &exclude);
    for t in &kws {
        exclude.push((t.start, t.end));
    }
    out = merge_tokens(out, kws);

    let ops = scan_operators(text, &exclude);
    merge_tokens(out, ops)
}

/// Build keyword groups from a parsed `langs.model.xml` entry:
/// `instre*` → Keyword, `type*` → Type.
#[must_use]
pub fn groups_from_keywords(
    keywords: &BTreeMap<String, String>,
) -> Vec<(Scope, BTreeSet<String>)> {
    let mut kw = BTreeSet::new();
    let mut ty = BTreeSet::new();
    for (class, words) in keywords {
        let set = if class.starts_with("instre") {
            &mut kw
        } else if class.starts_with("type") {
            &mut ty
        } else {
            continue;
        };
        set.extend(
            words
                .split_whitespace()
                .map(|w| w.to_ascii_lowercase()),
        );
    }
    vec![(Scope::Keyword, kw), (Scope::Type, ty)]
}

/// Line-oriented diff / patch highlighting (`---`, `+++`, `@@`, `+`/`-` lines).
#[must_use]
pub fn scan_diff(text: &str) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let line_start = i;
        while i < bytes.len() && bytes[i] != b'\n' {
            i += 1;
        }
        let line_end = i;
        if i < bytes.len() {
            i += 1; // skip '\n'
        }
        if line_end <= line_start {
            continue;
        }
        let line = &bytes[line_start..line_end];
        let scope = if line.starts_with(b"diff ")
            || line.starts_with(b"index ")
            || line.starts_with(b"---")
            || line.starts_with(b"+++")
        {
            // HEADER / COMMAND
            Some(Scope::Preproc)
        } else if line.starts_with(b"@@") {
            Some(Scope::Number)
        } else if line.starts_with(b"\\") {
            Some(Scope::Comment)
        } else if line.first() == Some(&b'-') {
            Some(Scope::Type) // DELETED
        } else if line.first() == Some(&b'+') {
            Some(Scope::Keyword) // ADDED
        } else {
            None
        };
        if let Some(scope) = scope {
            out.push(Token {
                start: line_start,
                end: line_end,
                scope,
            });
        }
    }
    out
}

/// TeX / LaTeX: `\`commands as keywords (comments via `%` commentLine).
#[must_use]
pub fn scan_tex_commands(text: &str, exclude: &[(usize, usize)]) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if in_exclude(i, exclude) {
            i += 1;
            continue;
        }
        if bytes[i] == b'\\' && i + 1 < bytes.len() {
            let start = i;
            i += 1;
            if bytes[i].is_ascii_alphabetic() {
                while i < bytes.len() && bytes[i].is_ascii_alphabetic() {
                    i += 1;
                }
            } else {
                // Short command: `\{`, `\%`, `\\`, etc.
                i += 1;
            }
            if !overlaps_exclude(start, i, exclude) {
                out.push(Token {
                    start,
                    end: i,
                    scope: Scope::Keyword,
                });
            }
            continue;
        }
        i += 1;
    }
    out
}

/// Extra scanners for langs that need more than keywords + comments.
#[must_use]
pub fn highlight_special(lang: &str, text: &str) -> Option<Vec<Token>> {
    match grammar_key(lang) {
        "diff" => Some(scan_diff(text)),
        "latex" | "tex" => {
            // Comments first via `%`, then commands.
            let comments = scan_comments_and_strings(text, "%", "", "");
            let exclude: Vec<(usize, usize)> =
                comments.iter().map(|t| (t.start, t.end)).collect();
            let cmds = scan_tex_commands(text, &exclude);
            Some(merge_tokens(comments, cmds))
        }
        _ => None,
    }
}

/// Map a styler `WordsStyle` name to a [`Scope`].
#[must_use]
pub fn scope_from_style_name(name: &str) -> Option<Scope> {
    let u = name.to_ascii_uppercase();
    // Markup lexers (XML/HTML): TAG / ATTRIBUTE before generic TYPE (DOCTYPE contains "TYPE").
    if u.contains("ATTRIBUTE") {
        Some(Scope::Type)
    } else if u.contains("TAG") {
        Some(Scope::Keyword)
    } else if u.contains("INSTRUCTION")
        || u == "KEYWORD"
        || u.contains("KEYWORD1")
        || u.contains("KEYWORD2")
        || u.contains("KEYWORD3")
        || u.contains("KEYWORD4")
        || u.contains("KEYWORD5")
        || u.contains("KEYWORD6")
        || u == "WORD"
        || u.contains("RESERVED")
        || u == "COMMAND"
        || u == "ADDED"
    {
        Some(Scope::Keyword)
    } else if (u.contains("TYPE") && !u.contains("DOCTYPE"))
        || u.contains("IDENTIFIER")
        || u.contains("CLASSNAME")
        || u.contains("CLASS NAME")
        || u == "CLASS"
        || u.contains("VARIABLE")
        || u == "KEY"
        || u.contains("ADDED KEY")
        || u.contains("SCALAR")
        || u.contains("LABEL")
        || u.contains("PROPERTY")
        || u == "DELETED"
    {
        Some(Scope::Type)
    } else if u.contains("STRING")
        || u.contains("CHARACTER")
        || u.contains("LITERAL")
        || u == "CDATA"
        || u == "VALUE"
        || u.contains("VERBATIM")
        || u.contains("REGEX")
        || u.contains("BACKTICK")
    {
        Some(Scope::Str)
    } else if u.contains("COMMENT") || u.contains("TASKMARKER") {
        Some(Scope::Comment)
    } else if u.contains("NUMBER")
        || u.contains("ENTITY")
        || u.contains("DIGIT")
        || u == "POSITION"
    {
        Some(Scope::Number)
    } else if u.contains("OPERATOR")
        || u.contains("XML START")
        || u.contains("XML END")
        || u.contains("SYMBOL")
        || u.contains("PUNCTUATION")
    {
        Some(Scope::Operator)
    } else if u.contains("FUNCTION") || u.contains("METHOD") || u.contains("PROCEDURE") {
        Some(Scope::Function)
    } else if u.contains("PREPROCESSOR")
        || u.contains("PREPROC")
        || u.contains("DIRECTIVE")
        || u.contains("#IFDEF")
        || u.contains("SENDER")
        || u == "HEADER"
    {
        Some(Scope::Preproc)
    } else {
        None
    }
}

/// Convert NPP BGR hex (`stylers.model.xml` `fgColor`) to RGB hex (`RRGGBB`).
#[must_use]
pub fn bgr_to_rgb(hex: &str) -> String {
    if hex.len() == 6 {
        format!("{}{}{}", &hex[4..6], &hex[2..4], &hex[0..2])
    } else {
        hex.to_owned()
    }
}

/// Default RGB hex per scope when stylers are missing.
#[must_use]
pub fn default_scope_rgb(scope: Scope) -> &'static str {
    match scope {
        Scope::Default => "000000",
        Scope::Keyword => "0000FF",
        Scope::Type => "8000FF",
        Scope::Str => "808080",
        Scope::Comment => "008000",
        Scope::Number => "FF8000",
        Scope::Operator => "000080",
        Scope::Function => "0080C0",
        Scope::Preproc => "804000",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tree_sitter_rust_rich_scopes() {
        let text = r#"
/// doc
fn main() {
    // hi
    let s = "x";
    let n = 42;
    foo(n);
}
"#;
        let toks = highlight_tree_sitter("rust", text).expect("rust grammar + query");
        assert!(toks.iter().any(|t| t.scope == Scope::Comment));
        assert!(toks.iter().any(|t| t.scope == Scope::Str));
        assert!(toks.iter().any(|t| t.scope == Scope::Keyword), "expected keywords: {toks:?}");
        assert!(toks.iter().any(|t| t.scope == Scope::Number), "expected numbers: {toks:?}");
        assert!(toks.iter().any(|t| t.scope == Scope::Function), "expected functions: {toks:?}");
        for t in &toks {
            assert!(text.is_char_boundary(t.start) && text.is_char_boundary(t.end));
        }
    }

    #[test]
    fn all_grammar_queries_compile() {
        for lang in [
            "rust",
            "python",
            "javascript",
            "javascript.js",
            "typescript",
            "go",
            "java",
            "ruby",
            "html",
            "css",
            "json",
            "toml",
            "xml",
            "yaml",
        ] {
            let grammar = language_grammar(lang).unwrap_or_else(|| panic!("grammar {lang}"));
            tree_sitter::Query::new(&grammar, query_for(lang))
                .unwrap_or_else(|e| panic!("query compile failed for {lang}: {e}"));
            // Smoke parse
            let sample = match grammar_key(lang) {
                "html" => "<div class=\"a\">x</div>",
                "xml" => r#"<?xml version="1.0"?><root attr="v">t</root>"#,
                "css" => "body { color: #fff; }",
                "json" => r#"{"a": 1, "b": true}"#,
                "toml" => "a = 1\n# c\n",
                "yaml" => "a: 1\n# c\n",
                _ => "fn main() { let x = 1; }\n",
            };
            let toks = highlight_tree_sitter(lang, sample).unwrap_or_else(|| panic!("hl {lang}"));
            assert!(
                !toks.is_empty() || sample.trim().is_empty(),
                "{lang} produced no tokens for {sample:?}"
            );
        }
    }

    #[test]
    fn tree_sitter_rust_strings_and_comments() {
        let text = "fn main() {\n// hi\nlet s = \"x\";\n}\n";
        let toks = highlight_tree_sitter("rust", text).expect("rust grammar");
        assert!(toks.iter().any(|t| t.scope == Scope::Comment));
        assert!(toks.iter().any(|t| t.scope == Scope::Str));
        for t in &toks {
            assert!(text.is_char_boundary(t.start) && text.is_char_boundary(t.end));
        }
    }

    #[test]
    fn keyword_fallback_cpp_numbers_and_preproc() {
        let mut keywords = BTreeMap::new();
        keywords.insert("instre1".into(), "int return if".into());
        let groups = groups_from_keywords(&keywords);
        let refs: Vec<(Scope, &BTreeSet<String>)> =
            groups.iter().map(|(s, set)| (*s, set)).collect();
        let text = "#include <stdio.h>\nint main() { return 42; }\n";
        let toks = highlight_keyword_lang(text, "//", "/*", "*/", &refs);
        assert!(toks.iter().any(|t| t.scope == Scope::Preproc));
        assert!(toks.iter().any(|t| t.scope == Scope::Number));
        assert!(toks.iter().any(|t| t.scope == Scope::Keyword));
    }

    #[test]
    fn keyword_fallback_cpp_with_comments() {
        assert!(!has_grammar("cpp"));
        let mut keywords = BTreeMap::new();
        keywords.insert("instre1".into(), "int return if".into());
        keywords.insert("type1".into(), "size_t".into());
        let groups = groups_from_keywords(&keywords);
        let refs: Vec<(Scope, &BTreeSet<String>)> =
            groups.iter().map(|(s, set)| (*s, set)).collect();
        let text = "// skip int\nint main() { return size_t; \"x\"; }\n";
        let toks = highlight_keyword_lang(text, "//", "/*", "*/", &refs);
        assert!(toks.iter().any(|t| t.scope == Scope::Comment));
        assert!(toks.iter().any(|t| t.scope == Scope::Str));
        // `int` inside the comment must not be a keyword token.
        let comment = toks.iter().find(|t| t.scope == Scope::Comment).unwrap();
        assert!(!toks.iter().any(|t| {
            t.scope == Scope::Keyword && t.start >= comment.start && t.end <= comment.end
        }));
        assert!(toks.iter().any(|t| t.scope == Scope::Keyword));
        assert!(toks.iter().any(|t| t.scope == Scope::Type));
    }

    #[test]
    fn merge_keeps_base() {
        let base = vec![Token {
            start: 0,
            end: 5,
            scope: Scope::Comment,
        }];
        let overlay = vec![
            Token {
                start: 2,
                end: 4,
                scope: Scope::Keyword,
            },
            Token {
                start: 6,
                end: 8,
                scope: Scope::Keyword,
            },
        ];
        let m = merge_tokens(base, overlay);
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].scope, Scope::Comment);
        assert_eq!(m[1].start, 6);
    }

    #[test]
    fn extension_map_overrides() {
        let langs = vec![
            ("cpp".into(), "cpp cxx h".into()),
            ("c".into(), "c".into()),
            ("cs".into(), "cs".into()),
            ("javascript.js".into(), "js".into()),
        ];
        let map = build_extension_map(&langs);
        assert_eq!(map.get("c").map(String::as_str), Some("c"));
        assert_eq!(map.get("cs").map(String::as_str), Some("cs"));
        assert_eq!(map.get("js").map(String::as_str), Some("javascript.js"));
        assert_eq!(map.get("h").map(String::as_str), Some("cpp"));
    }

    #[test]
    fn display_names_known() {
        assert_eq!(display_name("cpp"), "C++");
        assert_eq!(display_name("javascript.js"), "JavaScript");
        assert!(is_menu_language("cpp"));
        assert!(!is_menu_language("searchResult"));
    }

    #[test]
    fn bgr_swaps() {
        assert_eq!(bgr_to_rgb("0000FF"), "FF0000");
    }

    #[test]
    fn javascript_js_has_grammar() {
        assert!(has_grammar("javascript.js"));
    }

    #[test]
    fn xml_tags_use_keyword_attrs_use_type() {
        let text = r#"<?xml version="1.0"?>
<!-- c -->
<root attr="v">text &amp; x</root>
"#;
        let toks = highlight_tree_sitter("xml", text).expect("xml");
        assert!(toks.iter().any(|t| t.scope == Scope::Keyword)); // tag names + xml
        assert!(toks.iter().any(|t| t.scope == Scope::Type)); // attr
        assert!(toks.iter().any(|t| t.scope == Scope::Str)); // "v" / "1.0"
        assert!(toks.iter().any(|t| t.scope == Scope::Comment));
        assert!(toks.iter().any(|t| t.scope == Scope::Number)); // &amp;
        // Element text must not be painted as strings.
        assert!(!toks.iter().any(|t| {
            t.scope == Scope::Str && text[t.start..t.end].contains("text")
        }));
        assert_eq!(scope_from_style_name("TAG"), Some(Scope::Keyword));
        assert_eq!(scope_from_style_name("ATTRIBUTE"), Some(Scope::Type));
        assert_eq!(scope_from_style_name("DOUBLE STRING"), Some(Scope::Str));
        assert_eq!(scope_from_style_name("COMMAND"), Some(Scope::Keyword));
        assert_eq!(scope_from_style_name("ADDED"), Some(Scope::Keyword));
        assert_eq!(scope_from_style_name("DELETED"), Some(Scope::Type));
        assert_eq!(scope_from_style_name("HEADER"), Some(Scope::Preproc));
        assert_eq!(scope_from_style_name("POSITION"), Some(Scope::Number));
    }

    #[test]
    fn keywords_match_case_insensitively_and_hyphens() {
        let mut keywords = BTreeMap::new();
        keywords.insert(
            "instre1".into(),
            "select from where program-id identification".into(),
        );
        let groups = groups_from_keywords(&keywords);
        let refs: Vec<(Scope, &BTreeSet<String>)> =
            groups.iter().map(|(s, set)| (*s, set)).collect();
        let text = "SELECT * FROM t WHERE id=1;\nPROGRAM-ID. HELLO.\n";
        let toks = highlight_keywords(text, &refs, &[]);
        assert!(toks.iter().any(|t| text[t.start..t.end] == *"SELECT"));
        assert!(toks.iter().any(|t| text[t.start..t.end] == *"FROM"));
        assert!(toks.iter().any(|t| text[t.start..t.end] == *"WHERE"));
        assert!(toks.iter().any(|t| text[t.start..t.end] == *"PROGRAM-ID"));
    }

    #[test]
    fn diff_and_latex_special_scanners() {
        let diff = "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n";
        let d = highlight_special("diff", diff).expect("diff");
        assert!(d.iter().any(|t| t.scope == Scope::Preproc));
        assert!(d.iter().any(|t| t.scope == Scope::Number));
        assert!(d.iter().any(|t| t.scope == Scope::Type && diff[t.start..t.end].starts_with('-')));
        assert!(d.iter().any(|t| t.scope == Scope::Keyword && diff[t.start..t.end].starts_with('+')));

        let tex = "% c\n\\begin{document}\nHello \\textbf{x}\n";
        let t = highlight_special("latex", tex).expect("latex");
        assert!(t.iter().any(|t| t.scope == Scope::Comment));
        assert!(t.iter().any(|t| tex[t.start..t.end] == *"\\begin"));
        assert!(t.iter().any(|t| tex[t.start..t.end] == *"\\textbf"));
    }

    #[test]
    fn cobol_fixed_form_star_comment() {
        let mut keywords = BTreeMap::new();
        keywords.insert("instre1".into(), "division identification".into());
        let groups = groups_from_keywords(&keywords);
        let refs: Vec<(Scope, &BTreeSet<String>)> =
            groups.iter().map(|(s, set)| (*s, set)).collect();
        let text = "      * fixed comment\nIDENTIFICATION DIVISION.\n";
        let toks = highlight_keyword_lang(text, "*>", "", "", &refs);
        assert!(toks.iter().any(|t| t.scope == Scope::Comment && text[t.start..t.end].contains("fixed")));
        assert!(toks.iter().any(|t| text[t.start..t.end] == *"IDENTIFICATION"));
    }

    #[test]
    fn xml_cdata_highlights_inner_html() {
        let text = r#"<?xml version="1.0"?>
<item>
  <description><![CDATA[
    <h3>Added</h3>
    <ul><li><strong>x</strong></li></ul>
  ]]></description>
</item>
"#;
        let toks = highlight_tree_sitter("xml", text).expect("xml");
        assert!(
            toks.iter()
                .any(|t| t.scope == Scope::Keyword && text[t.start..t.end] == *"h3"),
            "expected HTML h3 tag inside CDATA: {toks:?}"
        );
        assert!(toks.iter().any(|t| {
            t.scope == Scope::Keyword && text[t.start..t.end] == *"strong"
        }));
        assert!(toks.iter().any(|t| t.scope == Scope::Preproc)); // CDATA delimiters
    }
}

