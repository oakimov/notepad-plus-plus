//! Line-oriented editing commands (Edit menu parity).
//!
//! All functions operate on `\n`-normalized text and preserve a single
//! trailing-newline convention of the input.

/// Duplicate line `line` (0-based). Returns `false` if out of range.
pub fn duplicate_line(text: &mut String, line: usize) -> bool {
    let lines: Vec<&str> = text.split('\n').collect();
    if line >= lines.len() {
        return false;
    }
    let rebuilt = rebuild_insert(&lines, line + 1, lines[line]);
    *text = rebuilt;
    true
}

/// Move line `line` up one. Returns `false` at top/out of range.
pub fn move_line_up(text: &mut String, line: usize) -> bool {
    if line == 0 {
        return false;
    }
    let mut lines: Vec<&str> = text.split('\n').collect();
    if line >= lines.len() {
        return false;
    }
    lines.swap(line - 1, line);
    *text = join_lines(&lines, text.ends_with('\n'));
    true
}

/// Move line `line` down one. Returns `false` at bottom/out of range.
pub fn move_line_down(text: &mut String, line: usize) -> bool {
    let mut lines: Vec<&str> = text.split('\n').collect();
    if line + 1 >= lines.len() {
        return false;
    }
    lines.swap(line, line + 1);
    *text = join_lines(&lines, text.ends_with('\n'));
    true
}

/// Join lines `start..=end` with single spaces.
pub fn join_lines_range(text: &mut String, start: usize, end: usize) -> bool {
    let lines: Vec<&str> = text.split('\n').collect();
    if start >= lines.len() || end >= lines.len() || start > end {
        return false;
    }
    let trailing = text.ends_with('\n');
    let joined = lines[start..=end].join(" ");
    let mut owned: Vec<String> = lines.iter().map(|s| (*s).to_owned()).collect();
    owned.splice(start..=end, [joined]);
    let refs: Vec<&str> = owned.iter().map(String::as_str).collect();
    *text = join_lines(&refs, trailing);
    true
}

/// Sort lines `start..=end` ascending (case-insensitive like NPP default off?
/// NPP sorts case-sensitively; `insensitive` selects the variant).
pub fn sort_lines(text: &mut String, start: usize, end: usize, insensitive: bool) -> bool {
    let mut lines: Vec<String> = text.split('\n').map(|l| l.to_owned()).collect();
    if start >= lines.len() || end >= lines.len() || start > end {
        return false;
    }
    let trailing = text.ends_with('\n');
    if insensitive {
        lines[start..=end].sort_by_key(|s| s.to_lowercase());
    } else {
        lines[start..=end].sort();
    }
    let refs: Vec<&str> = lines.iter().map(String::as_str).collect();
    *text = join_lines(&refs, trailing);
    true
}

/// Trim trailing whitespace on every line.
pub fn trim_trailing(text: &mut String) {
    let trailing = text.ends_with('\n');
    let lines: Vec<&str> = text.split('\n').map(str::trim_end).collect();
    *text = join_lines(&lines, trailing);
}

/// Trim leading and trailing whitespace on every line.
pub fn trim_all(text: &mut String) {
    let trailing = text.ends_with('\n');
    let lines: Vec<&str> = text.split('\n').map(|l| l.trim()).collect();
    *text = join_lines(&lines, trailing);
}

/// Uppercase ASCII + Unicode-aware via `char::to_uppercase`.
pub fn to_upper(text: &mut String) {
    *text = text.to_uppercase();
}

/// Lowercase equivalent.
pub fn to_lower(text: &mut String) {
    *text = text.to_lowercase();
}

/// Toggle line comment on lines `start..=end` using `token` (e.g. `//`).
/// Comments when any target line is uncommented, else uncomments all.
pub fn toggle_line_comment(text: &mut String, start: usize, end: usize, token: &str) -> bool {
    let mut lines: Vec<String> = text.split('\n').map(str::to_owned).collect();
    if start >= lines.len() || end >= lines.len() || start > end {
        return false;
    }
    let trailing = text.ends_with('\n');
    let need_comment = lines[start..=end]
        .iter()
        .any(|l| !l.trim_start().starts_with(token));
    for line in &mut lines[start..=end] {
        if need_comment {
            let indent = line.len() - line.trim_start().len();
            line.insert_str(indent, &(token.to_owned() + " "));
        } else if let Some(pos) = line.find(token) {
            let mut end = pos + token.len();
            if line[end..].starts_with(' ') {
                end += 1;
            }
            line.replace_range(pos..end, "");
        }
    }
    let refs: Vec<&str> = lines.iter().map(String::as_str).collect();
    *text = join_lines(&refs, trailing);
    true
}

/// Convert leading tabs to `width` spaces (per line) or back.
pub fn tabs_to_spaces(text: &mut String, width: usize) {
    let trailing = text.ends_with('\n');
    let out: Vec<String> = text
        .split('\n')
        .map(|l| {
            let n = l.chars().take_while(|&c| c == '\t').count();
            " ".repeat(n * width.max(1)) + &l[n..]
        })
        .collect();
    let refs: Vec<&str> = out.iter().map(String::as_str).collect();
    *text = join_lines(&refs, trailing);
}

/// Indent lines `start..=end` by one tab (or `use_spaces`).
pub fn indent(text: &mut String, start: usize, end: usize, use_spaces: bool, width: usize) -> bool {
    shift(text, start, end, true, use_spaces, width)
}

/// Dedent lines `start..=end` by one level.
pub fn dedent(text: &mut String, start: usize, end: usize, use_spaces: bool, width: usize) -> bool {
    shift(text, start, end, false, use_spaces, width)
}

fn shift(
    text: &mut String,
    start: usize,
    end: usize,
    right: bool,
    use_spaces: bool,
    width: usize,
) -> bool {
    let mut lines: Vec<String> = text.split('\n').map(str::to_owned).collect();
    if start >= lines.len() || end >= lines.len() || start > end {
        return false;
    }
    let trailing = text.ends_with('\n');
    let pad = if use_spaces {
        " ".repeat(width.max(1))
    } else {
        "\t".to_owned()
    };
    for line in &mut lines[start..=end] {
        if right {
            line.insert_str(0, &pad);
        } else if let Some(rest) = line.strip_prefix(&pad) {
            *line = rest.to_owned();
        } else if !use_spaces && line.starts_with(' ') {
            line.remove(0);
        }
    }
    let refs: Vec<&str> = lines.iter().map(String::as_str).collect();
    *text = join_lines(&refs, trailing);
    true
}

fn join_lines(lines: &[&str], trailing_newline: bool) -> String {
    let mut s = lines.join("\n");
    if trailing_newline && !s.ends_with('\n') {
        s.push('\n');
    }
    s
}

fn rebuild_insert(lines: &[&str], at: usize, content: &str) -> String {
    let mut v: Vec<String> = lines.iter().map(|s| (*s).to_owned()).collect();
    v.insert(at.min(v.len()), content.to_owned());
    v.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dup_move_join() {
        let mut s = "a\nb\nc".to_owned();
        assert!(duplicate_line(&mut s, 1));
        assert_eq!(s, "a\nb\nb\nc");
        assert!(move_line_up(&mut s, 2));
        assert_eq!(s, "a\nb\nb\nc"); // swapped identical lines
        let mut j = "a\nb\nc".to_owned();
        assert!(join_lines_range(&mut j, 0, 1));
        assert_eq!(j, "a b\nc");
    }

    #[test]
    fn sort_and_trim() {
        let mut s = "b\na\nc  \n".to_owned();
        assert!(sort_lines(&mut s, 0, 2, false));
        assert_eq!(s, "a\nb\nc  \n");
        trim_trailing(&mut s);
        assert_eq!(s, "a\nb\nc\n");
    }

    #[test]
    fn comment_toggle_round_trip() {
        let mut s = "fn x() {\npass\n}".to_owned();
        assert!(toggle_line_comment(&mut s, 1, 1, "//"));
        assert_eq!(s, "fn x() {\n// pass\n}");
        assert!(toggle_line_comment(&mut s, 1, 1, "//"));
        assert_eq!(s, "fn x() {\npass\n}");
    }

    #[test]
    fn case_indent_tabs() {
        let mut s = "aBc".to_owned();
        to_upper(&mut s);
        assert_eq!(s, "ABC");
        to_lower(&mut s);
        assert_eq!(s, "abc");
        let mut t = "\tx".to_owned();
        tabs_to_spaces(&mut t, 4);
        assert_eq!(t, "    x");
        let mut u = "x\ny".to_owned();
        assert!(indent(&mut u, 0, 1, false, 4));
        assert_eq!(u, "\tx\n\ty");
        assert!(dedent(&mut u, 0, 1, false, 4));
        assert_eq!(u, "x\ny");
    }
}
