//! Find/replace engine: literal + regex search over buffer text.
//!
//! Regex uses `fancy-regex` (PCRE-ish: look-around, backrefs), matching the
//! Boost.Regex PCRE role in the original (`BUILD.md:15`). Literal search uses
//! `memchr` fast paths. All byte offsets assume `\n`-normalized text and must
//! be char boundaries at match edges produced here.

use fancy_regex::Regex as FancyRegex;
use memchr::{memchr_iter, memmem};

/// A single match: byte range into the buffer text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Match {
    /// Start byte offset (char boundary).
    pub start: usize,
    /// End byte offset (char boundary).
    pub end: usize,
}

/// Search direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Direction {
    /// Toward end of buffer.
    #[default]
    Forward,
    /// Toward start of buffer.
    Backward,
}

/// Options mirroring the Notepad++ Find dialog flags.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SearchOptions {
    /// Case-sensitive comparison.
    pub match_case: bool,
    /// Match whole words only.
    pub whole_word: bool,
    /// Treat pattern as regex (fancy-regex syntax).
    pub regex: bool,
    /// Search direction.
    pub dir: Direction,
    /// Wrap around buffer ends.
    pub wrap: bool,
}

impl SearchOptions {
    /// Default Find-dialog settings: forward, wrap, case-insensitive literal.
    #[must_use]
    pub const fn find_defaults() -> Self {
        Self {
            match_case: false,
            whole_word: false,
            regex: false,
            dir: Direction::Forward,
            wrap: true,
        }
    }
}

/// Error from an invalid regex pattern.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegexError(pub String);

impl std::fmt::Display for RegexError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "invalid regex: {}", self.0)
    }
}

/// Find all non-overlapping matches of `pattern` in `text`.
pub fn find_all(
    text: &str,
    pattern: &str,
    opts: SearchOptions,
) -> Result<Vec<Match>, RegexError> {
    if pattern.is_empty() {
        return Ok(Vec::new());
    }
    if opts.regex {
        find_all_regex(text, pattern, opts)
    } else {
        Ok(find_all_literal(text, pattern, opts))
    }
}

/// Find the next match after (`Forward`) or before (`Backward`) `pos`.
pub fn find_next(
    text: &str,
    pattern: &str,
    pos: usize,
    opts: SearchOptions,
) -> Result<Option<Match>, RegexError> {
    let pos = pos.min(text.len());
    if opts.regex {
        find_next_regex(text, pattern, pos, opts)
    } else {
        Ok(find_next_literal(text, pattern, pos, opts))
    }
}

/// Count matches (Find dialog "Count").
pub fn count(text: &str, pattern: &str, opts: SearchOptions) -> Result<usize, RegexError> {
    Ok(find_all(text, pattern, opts)?.len())
}

/// Replace all matches; returns `(new_text, replacement_count)`.
/// `$`-captures in `replacement` expand for regex mode (fancy-regex
/// `expand`); literal mode substitutes verbatim.
pub fn replace_all(
    text: &str,
    pattern: &str,
    replacement: &str,
    opts: SearchOptions,
) -> Result<(String, usize), RegexError> {
    if pattern.is_empty() {
        return Ok((text.to_owned(), 0));
    }
    if opts.regex {
        let re = compile(pattern, opts)?;
        let mut out = String::with_capacity(text.len());
        let mut last = 0usize;
        let mut n = 0usize;
        for caps in re.captures_iter(text).filter_map(Result::ok) {
            let m = caps.get(0).expect("capture group 0 always matches");
            if m.start() == m.end() {
                continue; // skip zero-width to avoid stall loops
            }
            out.push_str(&text[last..m.start()]);
            let mut dst = String::new();
            caps.expand(replacement, &mut dst);
            out.push_str(&dst);
            last = m.end();
            n += 1;
        }
        out.push_str(&text[last..]);
        Ok((out, n))
    } else {
        let matches = find_all_literal(text, pattern, opts);
        if matches.is_empty() {
            return Ok((text.to_owned(), 0));
        }
        let mut out = String::with_capacity(text.len());
        let mut last = 0usize;
        for m in &matches {
            out.push_str(&text[last..m.start]);
            out.push_str(replacement);
            last = m.end;
        }
        out.push_str(&text[last..]);
        Ok((out, matches.len()))
    }
}

// --- literal ---

fn fold_eq(a: u8, b: u8, match_case: bool) -> bool {
    if match_case {
        a == b
    } else {
        a.eq_ignore_ascii_case(&b)
    }
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn whole_word_ok(text: &[u8], start: usize, end: usize) -> bool {
    let left = start == 0 || !is_word_byte(text[start - 1]);
    let right = end >= text.len() || !is_word_byte(text[end]);
    left && right
}

fn find_all_literal(text: &str, pattern: &str, opts: SearchOptions) -> Vec<Match> {
    let hay = text.as_bytes();
    let ndl = pattern.as_bytes();
    let mut out = Vec::new();
    if ndl.is_empty() || ndl.len() > hay.len() {
        return out;
    }
    if !opts.match_case && pattern.is_ascii() {
        let lower_hay: Vec<u8> = hay.iter().map(|b| b.to_ascii_lowercase()).collect();
        let lower_ndl: Vec<u8> = ndl.iter().map(|b| b.to_ascii_lowercase()).collect();
        for start in memmem::find_iter(&lower_hay, &lower_ndl) {
            let end = start + ndl.len();
            if opts.whole_word && !whole_word_ok(hay, start, end) {
                continue;
            }
            out.push(Match { start, end });
        }
        return out;
    }
    // General path (case-sensitive or non-ASCII, case-folded per byte).
    let first = ndl[0];
    for start in memchr_iter(first, hay) {
        if start + ndl.len() > hay.len() {
            break;
        }
        let mut ok = true;
        for (i, &b) in ndl.iter().enumerate() {
            if !fold_eq(hay[start + i], b, opts.match_case) {
                ok = false;
                break;
            }
        }
        if !ok {
            continue;
        }
        let end = start + ndl.len();
        if opts.whole_word && !whole_word_ok(hay, start, end) {
            continue;
        }
        out.push(Match { start, end });
    }
    out
}

fn find_next_literal(
    text: &str,
    pattern: &str,
    pos: usize,
    opts: SearchOptions,
) -> Option<Match> {
    if pattern.is_empty() {
        return None;
    }
    let all = find_all_literal(text, pattern, opts);
    match opts.dir {
        Direction::Forward => {
            if let Some(m) = all.iter().find(|m| m.start >= pos).copied() {
                return Some(m);
            }
            if opts.wrap {
                all.into_iter().next()
            } else {
                None
            }
        }
        Direction::Backward => {
            if let Some(m) = all.iter().rev().find(|m| m.start < pos).copied() {
                return Some(m);
            }
            if opts.wrap {
                all.into_iter().last()
            } else {
                None
            }
        }
    }
}

// --- regex ---

fn regex_prefix(pattern: &str, opts: SearchOptions) -> String {
    let mut p = String::new();
    if !opts.match_case {
        p.push_str("(?i)");
    }
    if opts.whole_word {
        p.push_str(r"\b(?:");
        p.push_str(pattern);
        p.push(')');
        p.push_str(r"\b");
    } else {
        p.push_str(pattern);
    }
    p
}

fn compile(pattern: &str, opts: SearchOptions) -> Result<FancyRegex, RegexError> {
    FancyRegex::new(&regex_prefix(pattern, opts))
        .map_err(|e| RegexError(e.to_string()))
}

fn to_match(m: fancy_regex::Match<'_>) -> Match {
    Match {
        start: m.start(),
        end: m.end(),
    }
}

fn find_all_regex(
    text: &str,
    pattern: &str,
    opts: SearchOptions,
) -> Result<Vec<Match>, RegexError> {
    let re = compile(pattern, opts)?;
    let mut out = Vec::new();
    for m in re.find_iter(text) {
        let m = m.map_err(|e| RegexError(e.to_string()))?;
        if m.start() == m.end() {
            continue; // skip zero-width to avoid stall loops
        }
        out.push(to_match(m));
    }
    Ok(out)
}

fn find_next_regex(
    text: &str,
    pattern: &str,
    pos: usize,
    opts: SearchOptions,
) -> Result<Option<Match>, RegexError> {
    let all = find_all_regex(text, pattern, opts)?;
    Ok(match opts.dir {
        Direction::Forward => {
            if let Some(m) = all.iter().find(|m| m.start >= pos).copied() {
                Some(m)
            } else if opts.wrap {
                all.into_iter().next()
            } else {
                None
            }
        }
        Direction::Backward => {
            if let Some(m) = all.iter().rev().find(|m| m.start < pos).copied() {
                Some(m)
            } else if opts.wrap {
                all.into_iter().last()
            } else {
                None
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn literal_case_insensitive_cjk_safe() {
        let text = "Hello 世界 hello héllo";
        let m = find_all(text, "hello", SearchOptions::find_defaults()).unwrap();
        // "Hello" + "hello" match; "héllo" (é = e-acute) correctly does not.
        assert_eq!(m.len(), 2);
        for x in &m {
            assert!(text.is_char_boundary(x.start) && text.is_char_boundary(x.end));
        }
    }

    #[test]
    fn whole_word_filters() {
        let opts = SearchOptions {
            whole_word: true,
            ..SearchOptions::find_defaults()
        };
        let m = find_all("he hell hello", "hell", opts).unwrap();
        assert_eq!(m.len(), 1);
        assert_eq!(m[0], Match { start: 3, end: 7 });
    }

    #[test]
    fn regex_dot_and_class() {
        let opts = SearchOptions {
            regex: true,
            ..SearchOptions::find_defaults()
        };
        let m = find_all("a1 b22 c333", r"[a-z]\d+", opts).unwrap();
        assert_eq!(m.len(), 3);
    }

    #[test]
    fn regex_lookahead_parity() {
        // Boost PCRE feature used by NPP regex users: look-ahead.
        let opts = SearchOptions {
            regex: true,
            ..SearchOptions::find_defaults()
        };
        let m = find_all("foobar foo", r"foo(?=bar)", opts).unwrap();
        assert_eq!(m.len(), 1);
        assert_eq!(m[0], Match { start: 0, end: 3 });
    }

    #[test]
    fn invalid_regex_errors() {
        let opts = SearchOptions {
            regex: true,
            ..SearchOptions::find_defaults()
        };
        assert!(find_all("x", "([", opts).is_err());
    }

    #[test]
    fn next_wraps_and_backward() {
        let text = "aa bb aa";
        let fwd = SearchOptions::find_defaults();
        assert_eq!(
            find_next(text, "aa", 1, fwd).unwrap(),
            Some(Match { start: 6, end: 8 })
        );
        assert_eq!(
            find_next(text, "aa", 8, fwd).unwrap(),
            Some(Match { start: 0, end: 2 })
        );
        let back = SearchOptions {
            dir: Direction::Backward,
            ..SearchOptions::find_defaults()
        };
        assert_eq!(
            find_next(text, "aa", 8, back).unwrap(),
            Some(Match { start: 6, end: 8 })
        );
    }

    #[test]
    fn replace_all_literal_and_regex_group() {
        let lit = SearchOptions::find_defaults();
        let (s, n) = replace_all("aa bb aa", "aa", "zz", lit).unwrap();
        assert_eq!((s.as_str(), n), ("zz bb zz", 2));
        let re = SearchOptions {
            regex: true,
            ..SearchOptions::find_defaults()
        };
        let (s, n) = replace_all("a1 b2", r"([a-z])(\d)", "$2$1", re).unwrap();
        assert_eq!((s.as_str(), n), ("1a 2b", 2));
    }

    #[test]
    fn count_matches() {
        let n = count("aa bb aa", "aa", SearchOptions::find_defaults()).unwrap();
        assert_eq!(n, 2);
    }
}
