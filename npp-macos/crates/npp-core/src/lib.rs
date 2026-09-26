//! Core editor buffer: UTF-8 text, line endings, undo/redo, document list.
//!
//! Mirrors the behavior split of `PowerEditor/src/ScintillaComponent/Buffer.h`
//! and `DocTabView.cpp` at the model layer (no Win32, no Scintilla).
//!
//! Submodules: [`search`] (find/replace), [`lineops`] (line editing commands).

pub mod lineops;
pub mod search;

/// Line ending style of a document.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LineEnding {
    /// `\r\n` (Windows / Notepad++ default for new files).
    #[default]
    Crlf,
    /// `\n` (Unix).
    Lf,
    /// `\r` (legacy Mac).
    Cr,
}

impl LineEnding {
    /// Raw separator string.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Crlf => "\r\n",
            Self::Lf => "\n",
            Self::Cr => "\r",
        }
    }

    /// Detect from a text sample (first line break wins, CRLF default).
    #[must_use]
    pub fn detect(text: &str) -> Self {
        let bytes = text.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            match bytes[i] {
                b'\r' if i + 1 < bytes.len() && bytes[i + 1] == b'\n' => return Self::Crlf,
                b'\r' => return Self::Cr,
                b'\n' => return Self::Lf,
                _ => {}
            }
            i += 1;
        }
        Self::default()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Op {
    Insert { byte_pos: usize, text: String },
    Delete { byte_pos: usize, text: String },
}

/// Single editable text buffer.
#[derive(Debug, Clone)]
pub struct Buffer {
    text: String,
    ending: LineEnding,
    undo: Vec<Op>,
    redo: Vec<Op>,
    dirty: bool,
    saved: String,
}

impl Buffer {
    /// Empty buffer with CRLF endings.
    #[must_use]
    pub fn new() -> Self {
        Self {
            text: String::new(),
            ending: LineEnding::default(),
            undo: Vec::new(),
            redo: Vec::new(),
            dirty: false,
            saved: String::new(),
        }
    }

    /// Buffer from loaded text; ending is auto-detected, text normalized to `\n`.
    #[must_use]
    pub fn from_loaded(loaded: &str) -> Self {
        let ending = LineEnding::detect(loaded);
        let text = loaded
            .replace("\r\n", "\n")
            .replace('\r', "\n");
        Self {
            saved: text.clone(),
            text,
            ending,
            undo: Vec::new(),
            redo: Vec::new(),
            dirty: false,
        }
    }

    /// Current text with `\n` line separators.
    #[must_use]
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Serialize back using the buffer's line ending.
    #[must_use]
    pub fn to_file_text(&self) -> String {
        self.text.replace('\n', self.ending.as_str())
    }

    /// Current line-ending style (used on save).
    #[must_use]
    pub const fn ending(&self) -> LineEnding {
        self.ending
    }

    /// Change line-ending style for subsequent saves (marks dirty when changed).
    pub fn set_ending(&mut self, ending: LineEnding) {
        if self.ending != ending {
            self.ending = ending;
            self.dirty = true;
        }
    }

    /// Whether the buffer differs from the last [`Self::mark_saved`] point.
    #[must_use]
    pub const fn is_dirty(&self) -> bool {
        self.dirty
    }

    /// Mark the current content as saved on disk.
    pub fn mark_saved(&mut self) {
        self.saved.clone_from(&self.text);
        self.dirty = false;
    }

    /// Insert `s` at byte position `pos` (must be a char boundary).
    pub fn insert(&mut self, pos: usize, s: &str) {
        assert!(self.text.is_char_boundary(pos), "insert pos not a char boundary");
        self.text.insert_str(pos, s);
        self.undo.push(Op::Insert {
            byte_pos: pos,
            text: s.to_owned(),
        });
        self.redo.clear();
        self.dirty = true;
    }

    /// Remove the byte range, returning the removed text.
    pub fn remove(&mut self, start: usize, end: usize) -> String {
        assert!(start <= end && end <= self.text.len(), "remove range out of bounds");
        assert!(
            self.text.is_char_boundary(start) && self.text.is_char_boundary(end),
            "remove range splits a char"
        );
        let removed = self.text[start..end].to_owned();
        self.text.replace_range(start..end, "");
        self.undo.push(Op::Delete {
            byte_pos: start,
            text: removed.clone(),
        });
        self.redo.clear();
        self.dirty = true;
        removed
    }

    /// Undo one edit. Returns `false` when the stack is empty.
    pub fn undo(&mut self) -> bool {
        let Some(op) = self.undo.pop() else {
            return false;
        };
        match &op {
            Op::Insert { byte_pos, text } => {
                self.text.replace_range(*byte_pos..byte_pos + text.len(), "");
            }
            Op::Delete { byte_pos, text } => {
                self.text.insert_str(*byte_pos, text);
            }
        }
        self.redo.push(op);
        self.dirty = self.text != self.saved;
        true
    }

    /// Redo one undone edit. Returns `false` when the stack is empty.
    pub fn redo(&mut self) -> bool {
        let Some(op) = self.redo.pop() else {
            return false;
        };
        match &op {
            Op::Insert { byte_pos, text } => {
                self.text.insert_str(*byte_pos, text);
            }
            Op::Delete { byte_pos, text } => {
                self.text.replace_range(*byte_pos..byte_pos + text.len(), "");
            }
        }
        self.undo.push(op);
        self.dirty = true;
        true
    }

    /// Number of lines (empty buffer counts as 1, Notepad++ status-bar parity).
    #[must_use]
    pub fn line_count(&self) -> usize {
        if self.text.is_empty() {
            1
        } else {
            self.text.bytes().filter(|&b| b == b'\n').count() + 1
        }
    }

    /// Line `index` (0-based) without the terminator.
    #[must_use]
    pub fn line(&self, index: usize) -> Option<&str> {
        self.text.split('\n').nth(index)
    }
}

impl Default for Buffer {
    fn default() -> Self {
        Self::new()
    }
}

/// Open-document list backing the internal tab bar (`DocTabView.cpp` parity).
#[derive(Debug, Default)]
pub struct DocumentManager {
    docs: Vec<Buffer>,
    current: Option<usize>,
}

impl DocumentManager {
    /// Empty manager with no documents.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Open a new document, select it, return its index.
    pub fn open(&mut self, buf: Buffer) -> usize {
        self.docs.push(buf);
        let idx = self.docs.len() - 1;
        self.current = Some(idx);
        idx
    }

    /// Close the document at `index`; fixes up the selection.
    pub fn close(&mut self, index: usize) -> bool {
        if index >= self.docs.len() {
            return false;
        }
        self.docs.remove(index);
        self.current = match self.current {
            _ if self.docs.is_empty() => None,
            Some(cur) if cur == index => Some(index.min(self.docs.len() - 1)),
            Some(cur) if cur > index => Some(cur - 1),
            Some(cur) => Some(cur),
            None => None,
        };
        true
    }

    /// Currently selected document index.
    #[must_use]
    pub const fn current(&self) -> Option<usize> {
        self.current
    }

    /// Select a document.
    pub fn select(&mut self, index: usize) -> bool {
        if index < self.docs.len() {
            self.current = Some(index);
            true
        } else {
            false
        }
    }

    /// Borrow a document.
    #[must_use]
    pub fn get(&self, index: usize) -> Option<&Buffer> {
        self.docs.get(index)
    }

    /// Mutably borrow a document.
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Buffer> {
        self.docs.get_mut(index)
    }

    /// Number of open documents.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.docs.len()
    }

    /// Whether no documents are open.
    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.docs.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ending_detect_and_round_trip() {
        let b = Buffer::from_loaded("a\r\nb\r\n");
        assert_eq!(b.ending, LineEnding::Crlf);
        assert_eq!(b.to_file_text(), "a\r\nb\r\n");
        let u = Buffer::from_loaded("a\nb\n");
        assert_eq!(u.ending, LineEnding::Lf);
        assert_eq!(u.to_file_text(), "a\nb\n");
    }

    #[test]
    fn insert_undo_redo_cjk() {
        let mut b = Buffer::from_loaded("héllo 世界");
        b.insert(0, ">>");
        assert!(b.is_dirty());
        assert!(b.text().starts_with(">>"));
        assert!(b.undo());
        assert_eq!(b.text(), "héllo 世界");
        assert!(b.redo());
        assert_eq!(b.text(), ">>héllo 世界");
    }

    #[test]
    fn remove_undo_restores() {
        let mut b = Buffer::from_loaded("abcdef");
        let cut = b.remove(1, 4);
        assert_eq!(cut, "bcd");
        assert_eq!(b.text(), "aef");
        assert!(b.undo());
        assert_eq!(b.text(), "abcdef");
    }

    #[test]
    fn lines_and_manager() {
        let b = Buffer::from_loaded("one\ntwo\nthree");
        assert_eq!(b.line_count(), 3);
        assert_eq!(b.line(1), Some("two"));
        let mut m = DocumentManager::new();
        let i0 = m.open(Buffer::new());
        let i1 = m.open(b);
        assert_eq!(m.current(), Some(i1));
        assert!(m.select(i0));
        assert!(m.close(i0));
        assert_eq!(m.len(), 1);
    }

    #[test]
    fn save_clears_dirty() {
        let mut b = Buffer::from_loaded("x");
        b.insert(1, "y");
        assert!(b.is_dirty());
        b.mark_saved();
        assert!(!b.is_dirty());
    }
}
