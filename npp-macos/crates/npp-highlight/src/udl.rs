//! LexUser-equivalent highlighter for Notepad++ User-Defined Languages.
//!
//! Practical port of `lexilla/lexers/LexUser.cxx` + `setUserLexer` packing:
//! comments, delimiters (incl. `((EOL …))`), keywords (prefix/whole), operators,
//! numbers, folders, and delimiter nesting bitmasks.

use npp_config::UdlLang;

/// SCE_USER_STYLE_* ids (SciLexer.h): DEFAULT=0 … DELIMITER8=23.
const SCE_USER_STYLE_DEFAULT: u8 = 0;
const SCE_USER_STYLE_COMMENT: u8 = 1;
const SCE_USER_STYLE_COMMENTLINE: u8 = 2;
const SCE_USER_STYLE_NUMBER: u8 = 3;
const SCE_USER_STYLE_KEYWORD1: u8 = 4;
const SCE_USER_STYLE_OPERATOR: u8 = 12;
const SCE_USER_STYLE_FOLDER_IN_CODE1: u8 = 13;
const SCE_USER_STYLE_FOLDER_IN_CODE2: u8 = 14;
const SCE_USER_STYLE_FOLDER_IN_COMMENT: u8 = 15;
const SCE_USER_STYLE_DELIMITER1: u8 = 16;

/// Nesting bitmasks (SciLexer.h `SCE_USER_MASK_NESTING_*`).
const NEST_DELIMITER1: u32 = 0x1;
const NEST_KEYWORD1: u32 = 0x400;

/// Styled byte range produced by [`highlight_udl`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UdlToken {
    /// Start byte offset (inclusive).
    pub start: usize,
    /// End byte offset (exclusive).
    pub end: usize,
    /// `SCE_USER_STYLE_*` id 0–23.
    pub style_id: u8,
}

#[derive(Clone, Debug)]
struct Variant {
    open: Vec<u8>,
    escape: Vec<u8>,
    closes: Vec<Vec<u8>>,
}

#[derive(Clone, Debug)]
struct DelimSlot {
    variants: Vec<Variant>,
    nesting: u32,
    style: u8,
}

#[derive(Clone, Debug)]
struct Compiled {
    case_ignored: bool,
    force_pure_lc: u8,
    line_comment_opens: Vec<Vec<u8>>,
    line_comment_closes: Vec<Vec<Vec<u8>>>,
    block_comment_opens: Vec<Vec<u8>>,
    block_comment_closes: Vec<Vec<Vec<u8>>>,
    delims: [DelimSlot; 8],
    keywords: [Vec<Vec<u8>>; 8],
    prefix: [bool; 8],
    operators: Vec<Vec<u8>>,
    folder_code1_open: Vec<Vec<u8>>,
    folder_code1_middle: Vec<Vec<u8>>,
    folder_code1_close: Vec<Vec<u8>>,
    folder_code2_open: Vec<Vec<u8>>,
    folder_code2_middle: Vec<Vec<u8>>,
    folder_code2_close: Vec<Vec<u8>>,
    folder_comment_open: Vec<Vec<u8>>,
    folder_comment_middle: Vec<Vec<u8>>,
    folder_comment_close: Vec<Vec<u8>>,
    number_prefixes: Vec<Vec<u8>>,
    number_suffixes: Vec<Vec<u8>>,
}

fn list<'a>(lang: &'a UdlLang, name: &str) -> &'a str {
    lang.keyword_lists
        .get(name)
        .map(String::as_str)
        .unwrap_or("")
}

/// Expand `((EOL …))` / bare tokens the way LexUser `SubGroup` does.
fn expand_group_token(raw: &str) -> Vec<Vec<u8>> {
    let s = raw.trim();
    if s.is_empty() {
        return Vec::new();
    }
    let inner = if s.starts_with("((") && s.ends_with("))") && s.len() >= 4 {
        &s[2..s.len() - 2]
    } else {
        return vec![s.as_bytes().to_vec()];
    };
    let mut out = Vec::new();
    for part in inner.split_whitespace() {
        if part == "EOL" {
            out.push(b"\r\n".to_vec());
            out.push(b"\n".to_vec());
            out.push(b"\r".to_vec());
        } else {
            out.push(part.as_bytes().to_vec());
        }
    }
    out
}

/// LexUser `GenerateVector`: collect tokens with a two-digit prefix into index-aligned slots.
fn generate_vector(src: &str, prefix: &str) -> Vec<Vec<Vec<u8>>> {
    let mut slots: Vec<Vec<Vec<u8>>> = Vec::new();
    let bytes = src.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        while i < bytes.len() && bytes[i] == b' ' {
            i += 1;
        }
        if i >= bytes.len() {
            break;
        }
        let is_pref = i + 2 <= bytes.len()
            && bytes[i] == prefix.as_bytes()[0]
            && bytes[i + 1] == prefix.as_bytes()[1]
            && (i + 2 >= bytes.len() || bytes[i + 2] != b' ');
        // Prefixes are always two ASCII digits; also accept at start or after space.
        let at_boundary = i == 0 || bytes[i - 1] == b' ';
        if !(is_pref && at_boundary && prefix.len() == 2) {
            // Skip unknown token.
            while i < bytes.len() && bytes[i] != b' ' {
                i += 1;
            }
            continue;
        }
        i += 2;
        if i < bytes.len() && bytes[i] == b' ' {
            slots.push(Vec::new());
            continue;
        }
        let start = i;
        if i + 1 < bytes.len() && bytes[i] == b'(' && bytes[i + 1] == b'(' {
            // Consume through matching `))` (no nesting of groups in UDL packing).
            i += 2;
            while i + 1 < bytes.len() && !(bytes[i] == b')' && bytes[i + 1] == b')') {
                i += 1;
            }
            if i + 1 < bytes.len() {
                i += 2;
            }
        } else {
            while i < bytes.len() && bytes[i] != b' ' {
                i += 1;
            }
        }
        let token = std::str::from_utf8(&bytes[start..i]).unwrap_or("");
        slots.push(expand_group_token(token));
    }
    slots
}

fn pad_slots(slots: &mut Vec<Vec<Vec<u8>>>, min_len: usize) {
    while slots.len() < min_len {
        slots.push(Vec::new());
    }
}

fn split_words(src: &str) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    for w in src.split_whitespace() {
        if !w.is_empty() {
            out.push(w.as_bytes().to_vec());
        }
    }
    // Longest first for match preference.
    out.sort_by(|a, b| b.len().cmp(&a.len()));
    out
}

/// Operators1 uses SubGroup(group=true): space-separated alternatives in one slot.
fn split_operators(src: &str) -> Vec<Vec<u8>> {
    split_words(src)
}

fn nesting_for_style(lang: &UdlLang, style_id: u8) -> u32 {
    lang.styles
        .iter()
        .find(|s| s.style_id == style_id)
        .map(|s| s.nesting)
        .unwrap_or(0)
}

fn compile(lang: &UdlLang) -> Compiled {
    let comments = list(lang, "Comments");
    // Pair open/close slots by index (LexUser GenerateVector), dropping empty opens.
    let line_comment_opens_raw: Vec<Vec<u8>> = generate_vector(comments, "00")
        .into_iter()
        .map(|alts| alts.first().cloned().unwrap_or_default())
        .collect();
    let line_closes_raw = {
        let mut c = generate_vector(comments, "02");
        pad_slots(&mut c, line_comment_opens_raw.len());
        c
    };
    let mut line_comment_opens = Vec::new();
    let mut line_comment_closes = Vec::new();
    for (i, open) in line_comment_opens_raw.into_iter().enumerate() {
        if open.is_empty() {
            continue;
        }
        line_comment_opens.push(open);
        line_comment_closes.push(line_closes_raw.get(i).cloned().unwrap_or_default());
    }

    let block_opens_raw: Vec<Vec<u8>> = generate_vector(comments, "03")
        .into_iter()
        .map(|a| a.first().cloned().unwrap_or_default())
        .collect();
    let mut block_closes_raw = generate_vector(comments, "04");
    pad_slots(&mut block_closes_raw, block_opens_raw.len());
    let mut block_comment_opens = Vec::new();
    let mut block_comment_closes = Vec::new();
    for (i, open) in block_opens_raw.into_iter().enumerate() {
        if open.is_empty() {
            continue;
        }
        block_comment_opens.push(open);
        block_comment_closes.push(block_closes_raw.get(i).cloned().unwrap_or_default());
    }

    let delims_src = list(lang, "Delimiters");
    let prefixes = ["00", "03", "06", "09", "12", "15", "18", "21"];
    let esc_prefs = ["01", "04", "07", "10", "13", "16", "19", "22"];
    let close_prefs = ["02", "05", "08", "11", "14", "17", "20", "23"];
    let mut delims: [DelimSlot; 8] = std::array::from_fn(|i| DelimSlot {
        variants: Vec::new(),
        nesting: nesting_for_style(lang, SCE_USER_STYLE_DELIMITER1 + i as u8),
        style: SCE_USER_STYLE_DELIMITER1 + i as u8,
    });
    for d in 0..8 {
        let opens = generate_vector(delims_src, prefixes[d]);
        let mut escapes = generate_vector(delims_src, esc_prefs[d]);
        let mut closes = generate_vector(delims_src, close_prefs[d]);
        pad_slots(&mut escapes, opens.len());
        pad_slots(&mut closes, opens.len());
        for (i, open_alts) in opens.into_iter().enumerate() {
            let open = open_alts.first().cloned().unwrap_or_default();
            if open.is_empty() {
                continue;
            }
            let escape = escapes
                .get(i)
                .and_then(|a| a.first().cloned())
                .unwrap_or_default();
            let close_alts = closes.get(i).cloned().unwrap_or_default();
            delims[d].variants.push(Variant {
                open,
                escape,
                closes: close_alts,
            });
        }
    }

    let mut keywords: [Vec<Vec<u8>>; 8] = std::array::from_fn(|_| Vec::new());
    for i in 0..8 {
        let name = format!("Keywords{}", i + 1);
        keywords[i] = split_words(list(lang, &name));
        if lang.settings.case_ignored {
            for w in &mut keywords[i] {
                for b in w.iter_mut() {
                    *b = b.to_ascii_lowercase();
                }
            }
        }
    }

    let mut operators = split_operators(list(lang, "Operators1"));
    operators.extend(split_operators(list(lang, "Operators2")));
    operators.sort_by(|a, b| b.len().cmp(&a.len()));
    operators.dedup();

    let number_prefixes = {
        let mut v = split_words(list(lang, "Numbers, prefix1"));
        v.extend(split_words(list(lang, "Numbers, prefix2")));
        v.sort_by(|a, b| b.len().cmp(&a.len()));
        v
    };
    let number_suffixes = {
        let mut v = split_words(list(lang, "Numbers, suffix1"));
        v.extend(split_words(list(lang, "Numbers, suffix2")));
        v.sort_by(|a, b| b.len().cmp(&a.len()));
        v
    };

    Compiled {
        case_ignored: lang.settings.case_ignored,
        force_pure_lc: lang.settings.force_pure_lc,
        line_comment_opens,
        line_comment_closes,
        block_comment_opens,
        block_comment_closes,
        delims,
        keywords,
        prefix: lang.settings.prefix,
        operators,
        folder_code1_open: split_words(list(lang, "Folders in code1, open")),
        folder_code1_middle: split_words(list(lang, "Folders in code1, middle")),
        folder_code1_close: split_words(list(lang, "Folders in code1, close")),
        folder_code2_open: split_words(list(lang, "Folders in code2, open")),
        folder_code2_middle: split_words(list(lang, "Folders in code2, middle")),
        folder_code2_close: split_words(list(lang, "Folders in code2, close")),
        folder_comment_open: split_words(list(lang, "Folders in comment, open")),
        folder_comment_middle: split_words(list(lang, "Folders in comment, middle")),
        folder_comment_close: split_words(list(lang, "Folders in comment, close")),
        number_prefixes,
        number_suffixes,
    }
}

fn eq_at(text: &[u8], i: usize, pat: &[u8], case_ignored: bool) -> bool {
    if pat.is_empty() || i + pat.len() > text.len() {
        return false;
    }
    if case_ignored {
        text[i..i + pat.len()]
            .iter()
            .zip(pat.iter())
            .all(|(a, b)| a.to_ascii_lowercase() == b.to_ascii_lowercase())
    } else {
        &text[i..i + pat.len()] == pat
    }
}

fn longest_match<'a>(text: &[u8], i: usize, pats: &'a [Vec<u8>], case_ignored: bool) -> Option<&'a [u8]> {
    let mut best: Option<&[u8]> = None;
    for p in pats {
        if eq_at(text, i, p, case_ignored) && best.map(|b| p.len() > b.len()).unwrap_or(true) {
            best = Some(p.as_slice());
        }
    }
    best
}

fn at_line_start(text: &[u8], i: usize) -> bool {
    i == 0 || text[i - 1] == b'\n' || text[i - 1] == b'\r'
}

fn only_ws_before_on_line(text: &[u8], i: usize) -> bool {
    let mut j = i;
    while j > 0 {
        let c = text[j - 1];
        if c == b'\n' || c == b'\r' {
            return true;
        }
        if c != b' ' && c != b'\t' {
            return false;
        }
        j -= 1;
    }
    true
}

fn line_comment_allowed(force_pure_lc: u8, text: &[u8], i: usize) -> bool {
    match force_pure_lc {
        0 => true, // PURE_LC_NONE
        1 => at_line_start(text, i), // PURE_LC_BOL
        2 => only_ws_before_on_line(text, i), // PURE_LC_WSP
        _ => true,
    }
}

fn paint(styles: &mut [u8], start: usize, end: usize, style: u8) {
    let end = end.min(styles.len());
    let start = start.min(end);
    for s in &mut styles[start..end] {
        *s = style;
    }
}

fn is_ws(b: u8) -> bool {
    b == b' ' || b == b'\t' || b == b'\n' || b == b'\r'
}

fn word_end(text: &[u8], mut i: usize) -> usize {
    while i < text.len() && !is_ws(text[i]) {
        i += 1;
    }
    i
}

/// Try keyword lists; returns (end, style) if matched at `i`.
fn match_keyword(c: &Compiled, text: &[u8], i: usize, nest_mask: u32) -> Option<(usize, u8)> {
    let mut best: Option<(usize, u8)> = None;
    for ki in 0..8 {
        let bit = NEST_KEYWORD1 << ki;
        if nest_mask != u32::MAX && nest_mask & bit == 0 {
            continue;
        }
        for kw in &c.keywords[ki] {
            if kw.is_empty() {
                continue;
            }
            // Stored lowercased when case_ignored.
            let ok = if c.case_ignored {
                eq_at(text, i, kw, true)
            } else {
                eq_at(text, i, kw, false)
            };
            if !ok {
                continue;
            }
            let end = if c.prefix[ki] {
                word_end(text, i + kw.len())
            } else {
                let e = i + kw.len();
                // Whole-token: must not continue as non-ws (already exact length of kw).
                // Require boundaries: start at ws/BOL and end at ws/EOF or we matched full word.
                let start_ok = i == 0 || is_ws(text[i - 1]);
                let end_ok = e >= text.len() || is_ws(text[e]);
                if !(start_ok && end_ok) {
                    // Also allow if the keyword itself is symbolic (non-alnum), common in markdown UDL.
                    let symbolic = !kw[0].is_ascii_alphanumeric();
                    if !(symbolic && e <= text.len()) {
                        continue;
                    }
                    if !symbolic && !(start_ok && end_ok) {
                        continue;
                    }
                }
                e
            };
            let style = SCE_USER_STYLE_KEYWORD1 + ki as u8;
            if best.map(|(be, _)| end > be).unwrap_or(true) {
                best = Some((end, style));
            }
        }
    }
    best
}

fn match_number(c: &Compiled, text: &[u8], i: usize) -> Option<usize> {
    let mut pos = i;
    // optional prefix
    if let Some(p) = longest_match(text, pos, &c.number_prefixes, c.case_ignored) {
        pos += p.len();
    }
    if pos >= text.len() || !text[pos].is_ascii_digit() {
        // bare digit run without prefix
        if i < text.len() && text[i].is_ascii_digit() {
            // don't take mid-identifier digits
            if i > 0 && (text[i - 1].is_ascii_alphabetic() || text[i - 1] == b'_') {
                return None;
            }
            pos = i;
        } else {
            return None;
        }
    } else if pos == i {
        // no prefix path already handled
    }
    if pos >= text.len() || !text[pos].is_ascii_digit() {
        return None;
    }
    while pos < text.len() && (text[pos].is_ascii_digit() || text[pos] == b'_') {
        pos += 1;
    }
    if let Some(s) = longest_match(text, pos, &c.number_suffixes, c.case_ignored) {
        pos += s.len();
    }
    if pos > i {
        Some(pos)
    } else {
        None
    }
}

fn match_folder(c: &Compiled, text: &[u8], i: usize) -> Option<(usize, u8)> {
    let groups: &[(&Vec<Vec<u8>>, u8)] = &[
        (&c.folder_code1_open, SCE_USER_STYLE_FOLDER_IN_CODE1),
        (&c.folder_code1_middle, SCE_USER_STYLE_FOLDER_IN_CODE1),
        (&c.folder_code1_close, SCE_USER_STYLE_FOLDER_IN_CODE1),
        (&c.folder_code2_open, SCE_USER_STYLE_FOLDER_IN_CODE2),
        (&c.folder_code2_middle, SCE_USER_STYLE_FOLDER_IN_CODE2),
        (&c.folder_code2_close, SCE_USER_STYLE_FOLDER_IN_CODE2),
        (&c.folder_comment_open, SCE_USER_STYLE_FOLDER_IN_COMMENT),
        (&c.folder_comment_middle, SCE_USER_STYLE_FOLDER_IN_COMMENT),
        (&c.folder_comment_close, SCE_USER_STYLE_FOLDER_IN_COMMENT),
    ];
    let mut best: Option<(usize, u8)> = None;
    for (pats, style) in groups {
        if let Some(p) = longest_match(text, i, pats, c.case_ignored) {
            let end = i + p.len();
            if best.map(|(be, _)| end > be).unwrap_or(true) {
                best = Some((end, *style));
            }
        }
    }
    best
}

#[derive(Clone)]
struct Frame {
    style: u8,
    nesting: u32,
    escape: Vec<u8>,
    closes: Vec<Vec<u8>>,
}

fn try_open_delim(c: &Compiled, text: &[u8], i: usize, allowed_mask: u32) -> Option<(usize, Frame)> {
    let mut best: Option<(usize, Frame)> = None;
    for (di, slot) in c.delims.iter().enumerate() {
        let bit = NEST_DELIMITER1 << di;
        if allowed_mask != u32::MAX && allowed_mask & bit == 0 {
            continue;
        }
        for v in &slot.variants {
            if eq_at(text, i, &v.open, c.case_ignored) {
                let end = i + v.open.len();
                if best.as_ref().map(|(be, _)| end > *be).unwrap_or(true) {
                    best = Some((
                        end,
                        Frame {
                            style: slot.style,
                            nesting: slot.nesting,
                            escape: v.escape.clone(),
                            closes: v.closes.clone(),
                        },
                    ));
                }
            }
        }
    }
    best
}

fn try_line_comment(c: &Compiled, text: &[u8], i: usize) -> Option<(usize, usize, Vec<Vec<u8>>)> {
    if !line_comment_allowed(c.force_pure_lc, text, i) {
        return None;
    }
    let mut best: Option<(usize, usize, Vec<Vec<u8>>)> = None;
    for (idx, open) in c.line_comment_opens.iter().enumerate() {
        if eq_at(text, i, open, c.case_ignored) {
            let end = i + open.len();
            if best.as_ref().map(|(be, _, _)| end > *be).unwrap_or(true) {
                let closes = c.line_comment_closes.get(idx).cloned().unwrap_or_default();
                best = Some((end, idx, closes));
            }
        }
    }
    best.map(|(end, _, closes)| (end, end, closes))
}

fn try_block_comment(c: &Compiled, text: &[u8], i: usize) -> Option<(usize, Vec<Vec<u8>>)> {
    let mut best: Option<(usize, Vec<Vec<u8>>)> = None;
    for (idx, open) in c.block_comment_opens.iter().enumerate() {
        if eq_at(text, i, open, c.case_ignored) {
            let end = i + open.len();
            if best.as_ref().map(|(be, _)| end > *be).unwrap_or(true) {
                let closes = c.block_comment_closes.get(idx).cloned().unwrap_or_default();
                best = Some((end, closes));
            }
        }
    }
    best
}

fn find_close(text: &[u8], i: usize, closes: &[Vec<u8>], case_ignored: bool) -> Option<(usize, usize)> {
    // returns (close_start, close_end)
    let mut best: Option<(usize, usize)> = None;
    for c in closes {
        if c.is_empty() {
            continue;
        }
        if eq_at(text, i, c, case_ignored) {
            let end = i + c.len();
            if best.map(|(_, be)| end > be).unwrap_or(true) {
                best = Some((i, end));
            }
        }
    }
    best
}

/// Overlay nested keyword/delimiter recognition inside an already-painted delimiter span.
fn scan_nested_interior(
    c: &Compiled,
    text: &[u8],
    styles: &mut [u8],
    start: usize,
    end: usize,
    _base: u8,
    nesting: u32,
) {
    let mut i = start;
    while i < end {
        if let Some((open_end, frame)) = try_open_delim(c, text, i, nesting) {
            if open_end > end {
                i += 1;
                continue;
            }
            paint(styles, i, open_end, frame.style);
            let mut j = open_end;
            let mut closed = false;
            while j < end {
                if !frame.escape.is_empty() && eq_at(text, j, &frame.escape, c.case_ignored) {
                    let esc_end = (j + frame.escape.len() + 1).min(end);
                    paint(styles, j, esc_end, frame.style);
                    j = esc_end;
                    continue;
                }
                if let Some((cs, ce)) = find_close(text, j, &frame.closes, c.case_ignored) {
                    if ce > end {
                        break;
                    }
                    paint(styles, j, cs, frame.style);
                    if frame.nesting != 0 && cs > open_end {
                        scan_nested_interior(c, text, styles, open_end, cs, frame.style, frame.nesting);
                    }
                    paint(styles, cs, ce, frame.style);
                    i = ce;
                    closed = true;
                    break;
                }
                j += 1;
            }
            if !closed {
                paint(styles, open_end, end, frame.style);
                if frame.nesting != 0 {
                    scan_nested_interior(c, text, styles, open_end, end, frame.style, frame.nesting);
                }
                return;
            }
            continue;
        }

        if let Some((kend, style)) = match_keyword(c, text, i, nesting) {
            if kend <= end {
                paint(styles, i, kend, style);
                i = kend;
                continue;
            }
        }
        i += 1;
    }
}

fn coalesce(styles: &[u8]) -> Vec<UdlToken> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < styles.len() {
        let style = styles[i];
        let start = i;
        i += 1;
        while i < styles.len() && styles[i] == style {
            i += 1;
        }
        if style != SCE_USER_STYLE_DEFAULT {
            out.push(UdlToken {
                start,
                end: i,
                style_id: style,
            });
        }
    }
    out
}

/// Tokenize `text` with a full UDL language definition into SCE_USER_STYLE_* ranges.
#[must_use]
pub fn highlight_udl(lang: &UdlLang, text: &str) -> Vec<UdlToken> {
    let c = compile(lang);
    let bytes = text.as_bytes();
    if bytes.is_empty() {
        return Vec::new();
    }
    let mut styles = vec![SCE_USER_STYLE_DEFAULT; bytes.len()];
    let mut i = 0;
    while i < bytes.len() {
        // Block comment
        if let Some((open_end, closes)) = try_block_comment(&c, bytes, i) {
            paint(&mut styles, i, open_end, SCE_USER_STYLE_COMMENT);
            let mut j = open_end;
            let mut closed = false;
            while j < bytes.len() {
                if let Some((_cs, ce)) = find_close(bytes, j, &closes, c.case_ignored) {
                    paint(&mut styles, open_end, ce, SCE_USER_STYLE_COMMENT);
                    i = ce;
                    closed = true;
                    break;
                }
                j += 1;
            }
            if !closed {
                paint(&mut styles, open_end, bytes.len(), SCE_USER_STYLE_COMMENT);
                break;
            }
            continue;
        }

        // Line comment
        if let Some((open_end, _, closes)) = try_line_comment(&c, bytes, i) {
            paint(&mut styles, i, open_end, SCE_USER_STYLE_COMMENTLINE);
            let mut j = open_end;
            let mut closed = false;
            while j < bytes.len() {
                if let Some((_cs, ce)) = find_close(bytes, j, &closes, c.case_ignored) {
                    paint(&mut styles, open_end, ce, SCE_USER_STYLE_COMMENTLINE);
                    i = ce;
                    closed = true;
                    break;
                }
                // Default EOL close if no explicit close patterns
                if closes.is_empty() && (bytes[j] == b'\n' || bytes[j] == b'\r') {
                    paint(&mut styles, open_end, j, SCE_USER_STYLE_COMMENTLINE);
                    i = j;
                    closed = true;
                    break;
                }
                j += 1;
            }
            if !closed {
                paint(&mut styles, open_end, bytes.len(), SCE_USER_STYLE_COMMENTLINE);
                break;
            }
            continue;
        }

        // Delimiters
        if let Some((open_end, frame)) = try_open_delim(&c, bytes, i, u32::MAX) {
            paint(&mut styles, i, open_end, frame.style);
            let mut j = open_end;
            let mut closed = false;
            while j < bytes.len() {
                if !frame.escape.is_empty() && eq_at(bytes, j, &frame.escape, c.case_ignored) {
                    let esc_end = (j + frame.escape.len() + 1).min(bytes.len());
                    paint(&mut styles, j, esc_end, frame.style);
                    j = esc_end;
                    continue;
                }
                if let Some((cs, ce)) = find_close(bytes, j, &frame.closes, c.case_ignored) {
                    paint(&mut styles, open_end, cs, frame.style);
                    if frame.nesting != 0 {
                        scan_nested_interior(&c, bytes, &mut styles, open_end, cs, frame.style, frame.nesting);
                    }
                    paint(&mut styles, cs, ce, frame.style);
                    i = ce;
                    closed = true;
                    break;
                }
                j += 1;
            }
            if !closed {
                paint(&mut styles, open_end, bytes.len(), frame.style);
                if frame.nesting != 0 {
                    scan_nested_interior(
                        &c,
                        bytes,
                        &mut styles,
                        open_end,
                        bytes.len(),
                        frame.style,
                        frame.nesting,
                    );
                }
                break;
            }
            continue;
        }

        // Operators
        if let Some(op) = longest_match(bytes, i, &c.operators, c.case_ignored) {
            paint(&mut styles, i, i + op.len(), SCE_USER_STYLE_OPERATOR);
            i += op.len();
            continue;
        }

        // Folders
        if let Some((end, style)) = match_folder(&c, bytes, i) {
            paint(&mut styles, i, end, style);
            i = end;
            continue;
        }

        // Numbers
        if let Some(nend) = match_number(&c, bytes, i) {
            paint(&mut styles, i, nend, SCE_USER_STYLE_NUMBER);
            i = nend;
            continue;
        }

        // Keywords (prefix / whole-token)
        if let Some((kend, style)) = match_keyword(&c, bytes, i, u32::MAX) {
            paint(&mut styles, i, kend, style);
            i = kend;
            continue;
        }

        i += 1;
    }

    coalesce(&styles)
}

/// Folder open..close byte ranges for folding UI. Stub: empty until fold scanner lands.
#[must_use]
pub fn udl_fold_ranges(_lang: &UdlLang, _text: &str) -> Vec<(usize, usize)> {
    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn markdown_lang() -> UdlLang {
        let p = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..")
            .join("PowerEditor")
            .join("bin")
            .join("userDefineLangs")
            .join("markdown._preinstalled.udl.xml");
        npp_config::parse_udl(&p)
            .expect("parse markdown UDL")
            .into_iter()
            .next()
            .expect("one lang")
    }

    fn covers(toks: &[UdlToken], style: u8) -> bool {
        toks.iter().any(|t| t.style_id == style)
    }

    #[test]
    fn markdown_heading_is_commentline() {
        let lang = markdown_lang();
        let text = "# title\n";
        let toks = highlight_udl(&lang, text);
        assert!(
            covers(&toks, SCE_USER_STYLE_COMMENTLINE),
            "expected COMMENTLINE on {toks:?}"
        );
        // `# title` should be covered
        let hit = toks.iter().any(|t| {
            t.style_id == SCE_USER_STYLE_COMMENTLINE && text[t.start..t.end].contains("title")
        });
        assert!(hit, "COMMENTLINE should cover heading text: {toks:?}");
    }

    #[test]
    fn markdown_backtick_is_delimiter() {
        let lang = markdown_lang();
        let text = "a `code` b\n";
        let toks = highlight_udl(&lang, text);
        assert!(
            toks.iter().any(|t| (16..=23).contains(&t.style_id)),
            "expected delimiter style 16–23: {toks:?}"
        );
        assert!(
            toks.iter().any(|t| {
                (16..=23).contains(&t.style_id) && text[t.start..t.end].contains("code")
            }),
            "delimiter should wrap code: {toks:?}"
        );
    }

    #[test]
    fn markdown_bold_not_all_default() {
        let lang = markdown_lang();
        let text = "**bold**\n";
        let toks = highlight_udl(&lang, text);
        assert!(
            toks.iter().any(|t| t.style_id != SCE_USER_STYLE_DEFAULT),
            "expected non-default styles for bold: {toks:?}"
        );
        assert!(
            toks.iter().any(|t| {
                (SCE_USER_STYLE_KEYWORD1..=11).contains(&t.style_id)
                    || (SCE_USER_STYLE_DELIMITER1..=23).contains(&t.style_id)
            }),
            "expected delimiter or keyword styles: {toks:?}"
        );
    }

    #[test]
    fn markdown_http_prefix_keyword1() {
        let lang = markdown_lang();
        let text = "see http://x now\n";
        let toks = highlight_udl(&lang, text);
        assert!(
            toks.iter().any(|t| {
                t.style_id == SCE_USER_STYLE_KEYWORD1 && text[t.start..t.end].contains("http://")
            }),
            "expected KEYWORDS1 on http://x: {toks:?}"
        );
    }

    #[test]
    fn fold_ranges_stub_empty() {
        let lang = markdown_lang();
        assert!(udl_fold_ranges(&lang, "# hi\n").is_empty());
    }
}
