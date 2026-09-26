//! C ABI bridge for the Swift AppKit GUI.
//!
//! Main-thread only for v1. Opaque [`Engine`] owns document buffers (npp-core),
//! metadata (path/encoding/language), and optional keyword tables (npp-config).
//!
//! Safety contracts for `extern "C"` entry points are documented in
//! `include/npp_ffi.h` (null-checked pointers, caller-frees strings/tokens).

#![allow(clippy::missing_safety_doc)]

use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::ptr;

use npp_core::{Buffer, DocumentManager};
use npp_fs::Encoding;
use npp_highlight::{
    groups_from_keywords, has_grammar, highlight_keywords, highlight_tree_sitter,
    language_for_extension, Scope, Token,
};

/// Per-document UI metadata (path, title, encoding, language).
#[derive(Debug, Clone)]
struct DocMeta {
    title: String,
    path: Option<PathBuf>,
    encoding: Encoding,
    had_bom: bool,
    language: String,
}

/// Engine state behind the opaque C handle.
pub struct Engine {
    docs: DocumentManager,
    meta: Vec<DocMeta>,
    /// lang name → keyword groups for fallback highlighting.
    keywords: BTreeMap<String, Vec<(Scope, std::collections::BTreeSet<String>)>>,
}

impl Engine {
    /// `langs_model`: explicit `langs.model.xml` (app bundle); falls back to the
    /// in-repo copy for dev/test runs.
    fn new(langs_model: Option<&Path>) -> Self {
        let mut eng = Self {
            docs: DocumentManager::new(),
            meta: Vec::new(),
            keywords: BTreeMap::new(),
        };
        eng.load_keywords(langs_model);
        let _ = eng.doc_new();
        eng
    }

    fn load_keywords(&mut self, langs_model: Option<&Path>) {
        let candidates = [
            langs_model.map(Path::to_path_buf),
            Some(
                PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .join("../../..")
                    .join("PowerEditor/src/langs.model.xml"),
            ),
            Some(PathBuf::from("PowerEditor/src/langs.model.xml")),
        ];
        for p in candidates.iter().flatten() {
            if let Ok(langs) = npp_config::parse_langs_model(p) {
                for lang in langs {
                    let groups = groups_from_keywords(&lang.keywords);
                    self.keywords.insert(lang.name, groups);
                }
                break;
            }
        }
    }

    fn doc_new(&mut self) -> i32 {
        let n = self.meta.len() + 1;
        let idx = self.docs.open(Buffer::new()) as i32;
        self.meta.push(DocMeta {
            title: format!("new {n}"),
            path: None,
            encoding: Encoding::Utf8,
            had_bom: false,
            language: "normal".into(),
        });
        idx
    }

    fn ensure_aligned(&self) {
        debug_assert_eq!(self.docs.len(), self.meta.len());
    }
}

fn cstr_to_str(p: *const c_char) -> Option<&'static str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p).to_str().ok() }
}

fn to_cstring(s: &str) -> *mut c_char {
    // C strings cannot contain interior NUL; replace so binary-ish buffers still export.
    let cleaned: std::borrow::Cow<'_, str> = if s.as_bytes().contains(&0) {
        std::borrow::Cow::Owned(s.replace('\0', "\u{FFFD}"))
    } else {
        std::borrow::Cow::Borrowed(s)
    };
    CString::new(cleaned.as_ref())
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

fn encoding_to_c(e: Encoding) -> i32 {
    match e {
        Encoding::Utf8 => 0,
        Encoding::Utf8Bom => 1,
        Encoding::Utf16Le => 2,
        Encoding::Utf16Be => 3,
        Encoding::Ansi => 4,
    }
}

fn encoding_from_c(v: i32) -> Encoding {
    match v {
        1 => Encoding::Utf8Bom,
        2 => Encoding::Utf16Le,
        3 => Encoding::Utf16Be,
        4 => Encoding::Ansi,
        _ => Encoding::Utf8,
    }
}

fn scope_to_c(s: Scope) -> u32 {
    match s {
        Scope::Default => 0,
        Scope::Keyword => 1,
        Scope::Type => 2,
        Scope::Str => 3,
        Scope::Comment => 4,
        Scope::Number => 5,
        Scope::Operator => 6,
        Scope::Function => 7,
        Scope::Preproc => 8,
    }
}

fn highlight_all(engine: &Engine, lang: &str, text: &str) -> Vec<Token> {
    if let Some(toks) = highlight_tree_sitter(lang, text) {
        return toks;
    }
    if let Some(groups) = engine.keywords.get(lang) {
        let refs: Vec<(Scope, &std::collections::BTreeSet<String>)> =
            groups.iter().map(|(s, set)| (*s, set)).collect();
        return highlight_keywords(text, &refs);
    }
    Vec::new()
}

/// Create a new engine with one empty document.
#[no_mangle]
pub extern "C" fn npp_engine_create() -> *mut Engine {
    Box::into_raw(Box::new(Engine::new(None)))
}

/// Like [`npp_engine_create`], loading keyword tables from `langs_model`
/// (NULL or unreadable ⇒ in-repo fallback).
#[no_mangle]
pub unsafe extern "C" fn npp_engine_create_with_langs(langs_model: *const c_char) -> *mut Engine {
    let path = cstr_to_str(langs_model).map(Path::new);
    Box::into_raw(Box::new(Engine::new(path)))
}

/// Destroy an engine created by [`npp_engine_create`].
#[no_mangle]
pub unsafe extern "C" fn npp_engine_destroy(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// Free a string allocated by this crate.
#[no_mangle]
pub unsafe extern "C" fn npp_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_count(engine: *const Engine) -> i32 {
    eng_ref(engine).map(|e| e.docs.len() as i32).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_selected(engine: *const Engine) -> i32 {
    eng_ref(engine)
        .and_then(|e| e.docs.current())
        .map(|i| i as i32)
        .unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_new(engine: *mut Engine) -> i32 {
    eng_mut(engine).map(|e| e.doc_new()).unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_open(engine: *mut Engine, path: *const c_char) -> i32 {
    let Some(eng) = eng_mut(engine) else {
        return -1;
    };
    let Some(path_str) = cstr_to_str(path) else {
        return -1;
    };
    let path = Path::new(path_str);
    // Refuse pathological opens that would OOM the process (looks like a crash).
    const MAX_OPEN_BYTES: u64 = 32 * 1024 * 1024;
    if let Ok(meta) = std::fs::metadata(path) {
        if meta.len() > MAX_OPEN_BYTES {
            return -1;
        }
    }
    let Ok(loaded) = npp_fs::load(path, None) else {
        return -1;
    };
    let buf = Buffer::from_loaded(&loaded.text);
    let idx = eng.docs.open(buf) as i32;
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    let language = language_for_extension(ext).to_owned();
    let title = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(path_str)
        .to_owned();
    eng.meta.push(DocMeta {
        title,
        path: Some(path.to_path_buf()),
        encoding: loaded.encoding,
        had_bom: loaded.had_bom,
        language,
    });
    eng.ensure_aligned();
    idx
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_close(engine: *mut Engine, index: i32) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    let i = index as usize;
    if !eng.docs.close(i) {
        return false;
    }
    if i < eng.meta.len() {
        eng.meta.remove(i);
    }
    if eng.docs.is_empty() {
        let _ = eng.doc_new();
    }
    eng.ensure_aligned();
    true
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_select(engine: *mut Engine, index: i32) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    eng.docs.select(index as usize)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_move(engine: *mut Engine, from: i32, to: i32) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if from < 0 || to < 0 {
        return false;
    }
    let from = from as usize;
    let to = to as usize;
    if from >= eng.meta.len() || to >= eng.meta.len() || from == to {
        return false;
    }
    let mut bufs: Vec<Buffer> = (0..eng.docs.len())
        .map(|i| eng.docs.get(i).cloned().unwrap_or_default())
        .collect();
    let buf = bufs.remove(from);
    bufs.insert(to, buf);
    let meta = eng.meta.remove(from);
    eng.meta.insert(to, meta);

    let selected = eng.docs.current().unwrap_or(0);
    let new_sel = if selected == from {
        to
    } else if from < selected && to >= selected {
        selected - 1
    } else if from > selected && to <= selected {
        selected + 1
    } else {
        selected
    };

    eng.docs = DocumentManager::new();
    for b in bufs {
        eng.docs.open(b);
    }
    eng.docs.select(new_sel);
    true
}

unsafe fn eng_ref<'a>(engine: *const Engine) -> Option<&'a Engine> {
    if engine.is_null() {
        None
    } else {
        Some(&*engine)
    }
}

unsafe fn eng_mut<'a>(engine: *mut Engine) -> Option<&'a mut Engine> {
    if engine.is_null() {
        None
    } else {
        Some(&mut *engine)
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_title(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    eng.meta
        .get(index as usize)
        .map(|m| to_cstring(&m.title))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_path(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    match eng.meta.get(index as usize).and_then(|m| m.path.as_ref()) {
        Some(p) => to_cstring(&p.to_string_lossy()),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_text(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    match eng.docs.get(index as usize) {
        Some(b) => to_cstring(b.text()),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_language(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    eng.meta
        .get(index as usize)
        .map(|m| to_cstring(&m.language))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_is_dirty(engine: *const Engine, index: i32) -> bool {
    let Some(eng) = eng_ref(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    eng.docs
        .get(index as usize)
        .map(Buffer::is_dirty)
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_encoding(engine: *const Engine, index: i32) -> i32 {
    let Some(eng) = eng_ref(engine) else {
        return 0;
    };
    if index < 0 {
        return 0;
    }
    eng.meta
        .get(index as usize)
        .map(|m| encoding_to_c(m.encoding))
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_set_encoding(engine: *mut Engine, index: i32, enc: i32) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    let Some(m) = eng.meta.get_mut(index as usize) else {
        return false;
    };
    m.encoding = encoding_from_c(enc);
    m.had_bom = matches!(m.encoding, Encoding::Utf8Bom);
    true
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_set_text(
    engine: *mut Engine,
    index: i32,
    text: *const c_char,
) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    let Some(text) = cstr_to_str(text) else {
        return false;
    };
    let Some(buf) = eng.docs.get_mut(index as usize) else {
        return false;
    };
    if buf.text() == text {
        return true;
    }
    // Replace only the changed middle so each sync records a small undo op
    // instead of two full-buffer copies.
    let (start, old_end, new_end) = changed_span(buf.text(), text);
    if old_end > start {
        let _ = buf.remove(start, old_end);
    }
    if new_end > start {
        buf.insert(start, &text[start..new_end]);
    }
    true
}

/// Byte span `(start, old_end, new_end)` where `old` and `new` differ,
/// trimmed of their common prefix/suffix and aligned to char boundaries.
fn changed_span(old: &str, new: &str) -> (usize, usize, usize) {
    let (a, b) = (old.as_bytes(), new.as_bytes());
    let mut start = a.iter().zip(b).take_while(|(x, y)| x == y).count();
    while !old.is_char_boundary(start) {
        start -= 1;
    }
    let max_suffix = (a.len() - start).min(b.len() - start);
    let mut suffix = a
        .iter()
        .rev()
        .zip(b.iter().rev())
        .take(max_suffix)
        .take_while(|(x, y)| x == y)
        .count();
    while !old.is_char_boundary(a.len() - suffix) || !new.is_char_boundary(b.len() - suffix) {
        suffix -= 1;
    }
    (start, a.len() - suffix, b.len() - suffix)
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_save(
    engine: *mut Engine,
    index: i32,
    path: *const c_char,
    err_out: *mut *mut c_char,
) -> bool {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    if engine.is_null() || index < 0 {
        return false;
    }
    let eng = &mut *engine;
    let i = index as usize;
    let Some(buf) = eng.docs.get(i) else {
        return false;
    };
    let Some(meta) = eng.meta.get(i) else {
        return false;
    };
    let path_buf: PathBuf = if let Some(p) = cstr_to_str(path) {
        PathBuf::from(p)
    } else if let Some(p) = &meta.path {
        p.clone()
    } else {
        if !err_out.is_null() {
            *err_out = to_cstring("No path for save");
        }
        return false;
    };
    let file_text = buf.to_file_text();
    let with_bom = matches!(meta.encoding, Encoding::Utf8Bom) || meta.had_bom;
    match npp_fs::save(&path_buf, &file_text, meta.encoding, with_bom) {
        Ok(()) => {
            if let Some(b) = eng.docs.get_mut(i) {
                b.mark_saved();
            }
            if let Some(m) = eng.meta.get_mut(i) {
                m.path = Some(path_buf.clone());
                if let Some(name) = path_buf.file_name().and_then(|n| n.to_str()) {
                    m.title = name.to_owned();
                }
            }
            true
        }
        Err(e) => {
            if !err_out.is_null() {
                *err_out = to_cstring(&e.to_string());
            }
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_mark_saved(
    engine: *mut Engine,
    index: i32,
    title: *const c_char,
    path: *const c_char,
) {
    if engine.is_null() || index < 0 {
        return;
    }
    let eng = &mut *engine;
    let i = index as usize;
    if let Some(b) = eng.docs.get_mut(i) {
        b.mark_saved();
    }
    if let Some(m) = eng.meta.get_mut(i) {
        if let Some(t) = cstr_to_str(title) {
            m.title = t.to_owned();
        }
        if let Some(p) = cstr_to_str(path) {
            m.path = Some(PathBuf::from(p));
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_language_for_path(path: *const c_char) -> *mut c_char {
    let Some(path) = cstr_to_str(path) else {
        return to_cstring("normal");
    };
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    to_cstring(language_for_extension(ext))
}

#[repr(C)]
pub struct NppTokenC {
    pub start: u32,
    pub end: u32,
    pub scope: u32,
}

#[no_mangle]
pub unsafe extern "C" fn npp_highlight(
    engine: *mut Engine,
    lang: *const c_char,
    text: *const c_char,
    out_tokens: *mut *mut NppTokenC,
) -> i32 {
    if out_tokens.is_null() {
        return 0;
    }
    *out_tokens = ptr::null_mut();
    if engine.is_null() {
        return 0;
    }
    let Some(lang) = cstr_to_str(lang) else {
        return 0;
    };
    let Some(text) = cstr_to_str(text) else {
        return 0;
    };
    if text.len() > 2 * 1024 * 1024 {
        return 0;
    }
    let _ = has_grammar(lang);
    let toks = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        highlight_all(&*engine, lang, text)
    })) {
        Ok(t) => t,
        Err(_) => return 0,
    };
    if toks.is_empty() {
        return 0;
    }
    // Use a boxed slice so length == allocation size for a safe free.
    let boxed: Box<[NppTokenC]> = toks
        .into_iter()
        .map(|t| NppTokenC {
            start: t.start as u32,
            end: t.end as u32,
            scope: scope_to_c(t.scope),
        })
        .collect::<Vec<_>>()
        .into_boxed_slice();
    let len = boxed.len() as i32;
    let ptr = Box::into_raw(boxed) as *mut NppTokenC;
    *out_tokens = ptr;
    len
}

/// Free token array of known length (from [`npp_highlight`]).
#[no_mangle]
pub unsafe extern "C" fn npp_tokens_free(tokens: *mut NppTokenC, count: i32) {
    if tokens.is_null() || count <= 0 {
        return;
    }
    let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(tokens, count as usize));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn engine_new_open_save_roundtrip() {
        let eng = npp_engine_create();
        assert!(!eng.is_null());
        unsafe {
            assert_eq!(npp_doc_count(eng), 1);
            let dir = std::env::temp_dir().join("npp-ffi-test");
            let _ = std::fs::create_dir_all(&dir);
            let path = dir.join("sample.rs");
            std::fs::write(&path, "fn main() {}\n").unwrap();
            let cpath = CString::new(path.to_str().unwrap()).unwrap();
            let idx = npp_doc_open(eng, cpath.as_ptr());
            assert!(idx >= 0);
            let text = npp_doc_text(eng, idx);
            assert!(!text.is_null());
            let s = CStr::from_ptr(text).to_string_lossy().into_owned();
            npp_string_free(text);
            assert!(s.contains("fn main"));
            assert!(!npp_doc_is_dirty(eng, idx));
            let set = CString::new("fn main() { /* edited */ }\n").unwrap();
            assert!(npp_doc_set_text(eng, idx, set.as_ptr()));
            assert!(npp_doc_is_dirty(eng, idx));
            let mut err: *mut c_char = ptr::null_mut();
            assert!(npp_doc_save(eng, idx, cpath.as_ptr(), &mut err));
            assert!(!npp_doc_is_dirty(eng, idx));
            npp_engine_destroy(eng);
            let _ = std::fs::remove_file(&path);
        }
    }

    #[test]
    fn open_highlight_free_many_files_no_crash() {
        let eng = npp_engine_create();
        unsafe {
            let dir = std::env::temp_dir().join("npp-ffi-qa");
            let _ = std::fs::create_dir_all(&dir);
            let files: &[(&str, &str)] = &[
                ("a.rs", "fn main() {\n  let s = \"x\";\n  // c\n}\n"),
                ("b.py", "def main():\n    print('hi')\n"),
                ("c.js", "function f() { return \"x\"; }\n"),
                ("d.txt", "plain\n"),
            ];
            for (name, body) in files {
                let path = dir.join(name);
                std::fs::write(&path, body).unwrap();
                let cpath = CString::new(path.to_str().unwrap()).unwrap();
                let idx = npp_doc_open(eng, cpath.as_ptr());
                assert!(idx >= 0, "open {name}");
                let text = npp_doc_text(eng, idx);
                let lang = npp_doc_language(eng, idx);
                assert!(!text.is_null() && !lang.is_null());
                // Hammer highlight/free — previously corrupted the heap when Vec capacity > len.
                for _ in 0..50 {
                    let mut toks: *mut NppTokenC = ptr::null_mut();
                    let n = npp_highlight(eng, lang, text, &mut toks);
                    if n > 0 {
                        assert!(!toks.is_null());
                        npp_tokens_free(toks, n);
                    }
                }
                npp_string_free(text);
                npp_string_free(lang);
            }
            // File with interior NUL must still export text (replacement chars).
            let nul_path = dir.join("nul.bin");
            std::fs::write(&nul_path, b"ab\0cd\n").unwrap();
            let cpath = CString::new(nul_path.to_str().unwrap()).unwrap();
            let idx = npp_doc_open(eng, cpath.as_ptr());
            assert!(idx >= 0);
            let text = npp_doc_text(eng, idx);
            let s = CStr::from_ptr(text).to_string_lossy();
            assert!(s.contains('a') && s.contains('d'), "got {s:?}");
            npp_string_free(text);
            npp_engine_destroy(eng);
        }
    }

    #[test]
    fn changed_span_minimal_and_char_aligned() {
        assert_eq!(changed_span("abc", "abc"), (3, 3, 3));
        assert_eq!(changed_span("abc", "abxc"), (2, 2, 3));
        assert_eq!(changed_span("abxc", "abc"), (2, 3, 2));
        assert_eq!(changed_span("aaa", "aaaa"), (3, 3, 4));
        assert_eq!(changed_span("", "x"), (0, 0, 1));
        // "é" (C3 A9) → "è" (C3 A8): shared lead byte must not split the char.
        assert_eq!(changed_span("xéy", "xèy"), (1, 3, 3));
        // Shared trailing continuation byte: "é" (C3 A9) → "©" (C2 A9).
        assert_eq!(changed_span("é", "©"), (0, 2, 2));
    }

    #[test]
    fn set_text_edits_round_trip() {
        let eng = npp_engine_create();
        unsafe {
            for s in ["hello", "héllo wörld", "hé", "", "日本語", "日本人語", "x"] {
                let c = CString::new(s).unwrap();
                assert!(npp_doc_set_text(eng, 0, c.as_ptr()));
                let out = npp_doc_text(eng, 0);
                assert_eq!(CStr::from_ptr(out).to_str().unwrap(), s);
                npp_string_free(out);
            }
            npp_engine_destroy(eng);
        }
    }

    #[test]
    fn highlight_rust_returns_tokens() {
        let eng = npp_engine_create();
        unsafe {
            let lang = CString::new("rust").unwrap();
            let text = CString::new("fn main() {\n// c\nlet s = \"x\";\n}\n").unwrap();
            let mut toks: *mut NppTokenC = ptr::null_mut();
            let n = npp_highlight(eng, lang.as_ptr(), text.as_ptr(), &mut toks);
            assert!(n > 0);
            npp_tokens_free(toks, n);
            npp_engine_destroy(eng);
        }
    }
}
