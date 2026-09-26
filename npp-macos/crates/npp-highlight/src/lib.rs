//! Syntax highlighting: tree-sitter registry with keyword fallback.
//!
//! Cached grammars (offline build) cover rust/python/javascript/typescript/
//! go/java/ruby/html/css/json/toml/xml/yaml. Languages without a grammar
//! tokenize via keyword lists + comment/string scanners from `langs.model.xml`,
//! styled by `stylers.model.xml` colors.

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
    match name {
        "keyword" | "keyword.control" | "keyword.operator" | "include" => Scope::Keyword,
        "type" | "type.builtin" | "constructor" => Scope::Type,
        "string" | "character" => Scope::Str,
        "comment" => Scope::Comment,
        "number" | "boolean" | "constant" => Scope::Number,
        "operator" | "punctuation" => Scope::Operator,
        "function" | "function.call" | "method" => Scope::Function,
        "preproc" | "attribute" | "tag" => Scope::Preproc,
        _ => Scope::Default,
    }
}

/// Per-grammar queries: node names differ across grammars.
fn query_for(lang: &str) -> &'static str {
    match grammar_key(lang) {
        "rust" => r#"(string_literal) @string (line_comment) @comment (block_comment) @comment"#,
        "python" | "javascript" | "json" | "yaml" | "html" | "css" | "xml" => {
            r#"(string) @string (comment) @comment"#
        }
        "typescript" => r#"(string) @string (comment) @comment"#,
        "go" => {
            r#"(interpreted_string_literal) @string (raw_string_literal) @string (comment) @comment"#
        }
        "java" => {
            r#"(string_literal) @string (line_comment) @comment (block_comment) @comment"#
        }
        "ruby" => r#"(string) @string (comment) @comment"#,
        "toml" => r#"(string) @string (comment) @comment"#,
        _ => r#"(string) @string (comment) @comment"#,
    }
}

/// Highlight with tree-sitter when a grammar exists, else `None`.
#[must_use]
pub fn highlight_tree_sitter(lang: &str, text: &str) -> Option<Vec<Token>> {
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
            out.push(Token {
                start: node.start_byte(),
                end: node.end_byte(),
                scope: scope_for_capture(name),
            });
        }
    }
    out.sort_by_key(|t| (t.start, t.end));
    Some(out)
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
/// Matching is ASCII word-boundary; skips ranges covered by `exclude`.
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
        if c.is_ascii_alphanumeric() || c == b'_' {
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            if exclude.iter().any(|&(a, b)| start < b && i > a) {
                continue;
            }
            let word = &text[start..i];
            for (scope, set) in groups {
                if set.contains(word) {
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

/// Full keyword-language highlight: comments/strings + keywords outside them.
#[must_use]
pub fn highlight_keyword_lang(
    text: &str,
    comment_line: &str,
    comment_start: &str,
    comment_end: &str,
    groups: &[(Scope, &BTreeSet<String>)],
) -> Vec<Token> {
    let structural = scan_comments_and_strings(text, comment_line, comment_start, comment_end);
    let exclude: Vec<(usize, usize)> = structural.iter().map(|t| (t.start, t.end)).collect();
    let kws = highlight_keywords(text, groups, &exclude);
    merge_tokens(structural, kws)
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
        set.extend(words.split_whitespace().map(str::to_owned));
    }
    vec![(Scope::Keyword, kw), (Scope::Type, ty)]
}

/// Map a styler `WordsStyle` name to a [`Scope`].
#[must_use]
pub fn scope_from_style_name(name: &str) -> Option<Scope> {
    let u = name.to_ascii_uppercase();
    if u.contains("INSTRUCTION") || u == "KEYWORD" || u.contains("KEYWORD1") {
        Some(Scope::Keyword)
    } else if u.contains("TYPE") {
        Some(Scope::Type)
    } else if u.contains("STRING") || u.contains("CHARACTER") || u.contains("LITERAL") {
        Some(Scope::Str)
    } else if u.contains("COMMENT") {
        Some(Scope::Comment)
    } else if u.contains("NUMBER") {
        Some(Scope::Number)
    } else if u.contains("OPERATOR") {
        Some(Scope::Operator)
    } else if u.contains("FUNCTION") || u.contains("METHOD") {
        Some(Scope::Function)
    } else if u.contains("PREPROCESSOR") || u.contains("PREPROC") || u.contains("DIRECTIVE") {
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
}
