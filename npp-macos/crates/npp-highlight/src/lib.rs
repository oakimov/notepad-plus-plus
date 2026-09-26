//! Syntax highlighting: tree-sitter registry with keyword fallback.
//!
//! Cached grammars (offline build) cover rust/python/javascript/typescript/
//! go/java/ruby/html/css/json/toml/xml/yaml. Languages without a grammar
//! (`cpp`, `swift`, …) tokenize via keyword lists imported from the stock
//! `langs.model.xml` (`npp-config`), styled by `stylers.model.xml` colors.

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

/// Language key guessed from a file extension (superset of the M1 stub).
#[must_use]
pub fn language_for_extension(ext: &str) -> &'static str {
    match ext.to_ascii_lowercase().as_str() {
        "rs" => "rust",
        "py" | "pyw" => "python",
        "js" | "mjs" | "cjs" => "javascript",
        "ts" => "typescript",
        "tsx" | "jsx" => "typescript",
        "go" => "go",
        "java" => "java",
        "rb" => "ruby",
        "html" | "htm" => "html",
        "css" => "css",
        "json" => "json",
        "toml" => "toml",
        "xml" | "plist" | "xib" | "storyboard" | "xsd" | "xsl" => "xml",
        "yaml" | "yml" => "yaml",
        "cpp" | "cxx" | "cc" | "c" | "h" | "hpp" | "cs" => "cpp",
        "swift" => "swift",
        "md" | "markdown" => "markdown",
        _ => "normal",
    }
}

/// Whether a tree-sitter grammar is linked for `lang`.
#[must_use]
pub fn has_grammar(lang: &str) -> bool {
    matches!(
        lang,
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
    match lang {
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

/// Per-grammar queries: node names differ (`string` vs `string_literal`
/// vs `interpreted_string_literal`, …), so each language gets its own
/// query string. Unknown predicates compile-fail per grammar, hence the
/// split (surveyed from the vendored `node-types.json` files).
fn query_for(lang: &str) -> &'static str {
    match lang {
        "rust" => r#"(string_literal) @string (line_comment) @comment (block_comment) @comment"#,
        "python" | "javascript" | "json" | "yaml" | "html" | "css" | "xml" => {
            r#"(string) @string (comment) @comment"#
        }
        "typescript" => r#"(string) @string (comment) @comment"#,
        "go" => r#"(interpreted_string_literal) @string (raw_string_literal) @string (comment) @comment"#,
        "java" => r#"(string_literal) @string (line_comment) @comment (block_comment) @comment"#,
        "ruby" => r#"(string) @string (comment) @comment"#,
        "toml" => r#"(string) @string (comment) @comment"#,
        _ => r#"(string) @string (comment) @comment"#,
    }
}

/// Highlight with tree-sitter when a grammar exists, else `None`
/// (caller falls back to [`highlight_keywords`]).
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

/// Keyword tokenizer from `langs.model.xml` word lists.
/// `groups`: list of (scope, words) pairs; matching is ASCII word-boundary.
#[must_use]
pub fn highlight_keywords(text: &str, groups: &[(Scope, &BTreeSet<String>)]) -> Vec<Token> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if c.is_ascii_alphanumeric() || c == b'_' {
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
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

/// Convert NPP BGR hex (`stylers.model.xml` `fgColor`) to RGB hex.
#[must_use]
pub fn bgr_to_rgb(hex: &str) -> String {
    if hex.len() == 6 {
        format!("{}{}{}", &hex[4..6], &hex[2..4], &hex[0..2])
    } else {
        hex.to_owned()
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
    fn keyword_fallback_cpp() {
        assert!(!has_grammar("cpp"));
        let mut keywords = BTreeMap::new();
        keywords.insert("instre1".into(), "int return if".into());
        keywords.insert("type1".into(), "size_t".into());
        let groups = groups_from_keywords(&keywords);
        let toks = highlight_keywords("int main() { return size_t; }", &as_refs(&groups));
        assert!(toks.iter().any(|t| t.scope == Scope::Keyword));
        assert!(toks.iter().any(|t| t.scope == Scope::Type));
    }

    #[test]
    fn bgr_swaps() {
        assert_eq!(bgr_to_rgb("0000FF"), "FF0000");
    }

    fn as_refs(groups: &[(Scope, BTreeSet<String>)]) -> Vec<(Scope, &BTreeSet<String>)> {
        groups.iter().map(|(s, set)| (*s, set)).collect()
    }
}
