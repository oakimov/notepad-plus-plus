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

use npp_core::{Buffer, DocumentManager, LineEnding};
use npp_fs::Encoding;
use npp_highlight::{
    bgr_to_rgb, build_extension_map, default_scope_rgb, display_name, grammar_key,
    groups_from_keywords, highlight_keyword_lang, highlight_keywords, highlight_special,
    highlight_tree_sitter, is_menu_language, language_for_extension, language_for_extension_map,
    merge_tokens, scope_from_style_name, Scope, Token,
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

/// Comment delimiters + keyword groups for one language.
struct LangHighlight {
    comment_line: String,
    comment_start: String,
    comment_end: String,
    groups: Vec<(Scope, std::collections::BTreeSet<String>)>,
}

/// Engine state behind the opaque C handle.
pub struct Engine {
    docs: DocumentManager,
    meta: Vec<DocMeta>,
    /// Ordered menu languages (XML `name` keys).
    lang_names: Vec<String>,
    /// lang name → keyword/comment data.
    lang_hl: BTreeMap<String, LangHighlight>,
    /// extension → language name.
    ext_map: BTreeMap<String, String>,
    /// lang → scope → RGB hex (`RRGGBB`).
    style_colors: BTreeMap<String, BTreeMap<Scope, String>>,
    /// Global fallback scope colors from the first styler entries seen.
    global_colors: BTreeMap<Scope, String>,
    /// UDL key → display name.
    udl_display: BTreeMap<String, String>,
    /// Optional editor canvas colors from the active theme (`RRGGBB`).
    editor_fg: Option<String>,
    editor_bg: Option<String>,
}

impl Engine {
    /// `langs_model`: explicit `langs.model.xml` (app bundle); falls back to the
    /// in-repo copy for dev/test runs.
    fn new(langs_model: Option<&Path>) -> Self {
        let mut eng = Self {
            docs: DocumentManager::new(),
            meta: Vec::new(),
            lang_names: Vec::new(),
            lang_hl: BTreeMap::new(),
            ext_map: BTreeMap::new(),
            style_colors: BTreeMap::new(),
            global_colors: BTreeMap::new(),
            udl_display: BTreeMap::new(),
            editor_fg: None,
            editor_bg: None,
        };
        eng.load_langs(langs_model);
        eng.load_stylers(langs_model);
        let _ = eng.doc_new();
        eng
    }

    fn model_candidates(explicit: Option<&Path>, file: &str) -> Vec<PathBuf> {
        let mut out = Vec::new();
        if let Some(p) = explicit {
            out.push(p.to_path_buf());
            if let Some(parent) = p.parent() {
                out.push(parent.join(file));
            }
        }
        out.push(
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../..")
                .join("PowerEditor/src")
                .join(file),
        );
        out.push(PathBuf::from("PowerEditor/src").join(file));
        out
    }

    fn load_langs(&mut self, langs_model: Option<&Path>) {
        for p in Self::model_candidates(langs_model, "langs.model.xml") {
            if let Ok(langs) = npp_config::parse_langs_model(&p) {
                let pairs: Vec<(String, String)> = langs
                    .iter()
                    .map(|l| (l.name.clone(), l.ext.clone()))
                    .collect();
                self.ext_map = build_extension_map(&pairs);
                self.lang_names.clear();
                self.lang_hl.clear();
                for lang in langs {
                    if (is_menu_language(&lang.name) || lang.name == "normal")
                        && !self.lang_names.iter().any(|n| n == &lang.name)
                    {
                        self.lang_names.push(lang.name.clone());
                    }
                    let groups = groups_from_keywords(&lang.keywords);
                    self.lang_hl.insert(
                        lang.name.clone(),
                        LangHighlight {
                            comment_line: lang.comment_line,
                            comment_start: lang.comment_start,
                            comment_end: lang.comment_end,
                            groups,
                        },
                    );
                }
                // Stable A–Z by display name for the menu (keep `normal` first).
                self.lang_names.sort_by(|a, b| {
                    if a == "normal" {
                        return std::cmp::Ordering::Less;
                    }
                    if b == "normal" {
                        return std::cmp::Ordering::Greater;
                    }
                    display_name(a).cmp(display_name(b))
                });
                break;
            }
        }
        if self.lang_names.is_empty() {
            self.lang_names.push("normal".into());
        }
    }

    /// Register UDL keyword languages (load-only). Returns registered keys.
    fn register_udl(&mut self, defs: &[npp_config::UdlDef]) -> Vec<String> {
        let mut keys = Vec::new();
        for u in defs {
            let groups = groups_from_keywords(&u.keywords);
            self.lang_hl.insert(
                u.key.clone(),
                LangHighlight {
                    comment_line: u.comment_line.clone(),
                    comment_start: String::new(),
                    comment_end: String::new(),
                    groups,
                },
            );
            // Extension map entries.
            for ext in u.ext.split_whitespace() {
                let e = ext.trim_start_matches('.').to_ascii_lowercase();
                if !e.is_empty() {
                    self.ext_map.insert(e, u.key.clone());
                }
            }
            if !self.lang_names.iter().any(|n| n == &u.key) {
                self.lang_names.push(u.key.clone());
            }
            self.udl_display.insert(u.key.clone(), u.name.clone());
            keys.push(u.key.clone());
        }
        self.lang_names.sort_by(|a, b| {
            if a == "normal" {
                return std::cmp::Ordering::Less;
            }
            if b == "normal" {
                return std::cmp::Ordering::Greater;
            }
            // Compare via static display / slug; udl_display already filled for new keys.
            let da = if a.starts_with("udl_") {
                a.trim_start_matches("udl_").replace('_', " ")
            } else {
                display_name(a).to_string()
            };
            let db = if b.starts_with("udl_") {
                b.trim_start_matches("udl_").replace('_', " ")
            } else {
                display_name(b).to_string()
            };
            da.cmp(&db)
        });
        keys
    }

    fn display_for(&self, key: &str) -> String {
        if let Some(d) = self.udl_display.get(key) {
            return d.clone();
        }
        if key.starts_with("udl_") {
            return key.trim_start_matches("udl_").replace('_', " ");
        }
        display_name(key).to_string()
    }

    fn load_stylers(&mut self, langs_model: Option<&Path>) {
        for p in Self::model_candidates(langs_model, "stylers.model.xml") {
            if self.apply_stylers_file(&p) {
                break;
            }
        }
    }

    /// Replace styler colors from a theme / `stylers.model.xml` path.
    fn apply_stylers_file(&mut self, path: &Path) -> bool {
        let Ok(styles) = npp_config::parse_stylers_model(path) else {
            return false;
        };
        self.style_colors.clear();
        self.global_colors.clear();
        self.editor_fg = None;
        self.editor_bg = None;
        for (lexer, rows) in styles {
            let mut map = BTreeMap::new();
            for row in rows {
                if row.name.eq_ignore_ascii_case("DEFAULT") {
                    if self.editor_fg.is_none() && !row.fg.is_empty() {
                        self.editor_fg = Some(bgr_to_rgb(&row.fg));
                    }
                    if self.editor_bg.is_none() && !row.bg.is_empty() {
                        self.editor_bg = Some(bgr_to_rgb(&row.bg));
                    }
                }
                if let Some(scope) = scope_from_style_name(&row.name) {
                    let rgb = bgr_to_rgb(&row.fg);
                    map.entry(scope).or_insert(rgb.clone());
                    self.global_colors.entry(scope).or_insert(rgb);
                }
            }
            self.style_colors.insert(lexer, map);
        }
        true
    }

    fn resolve_lang(&self, lang: &str) -> String {
        if self.lang_hl.contains_key(lang) {
            return lang.to_owned();
        }
        let gk = grammar_key(lang);
        if self.lang_hl.contains_key(gk) {
            return gk.to_owned();
        }
        // javascript.js ↔ javascript keyword tables
        if lang == "javascript" && self.lang_hl.contains_key("javascript.js") {
            return "javascript.js".into();
        }
        lang.to_owned()
    }

    fn guess_language(&self, path: &Path) -> String {
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");
        if self.ext_map.is_empty() {
            language_for_extension(ext).to_owned()
        } else {
            language_for_extension_map(ext, &self.ext_map)
        }
    }

    fn color_for(&self, lang: &str, scope: Scope) -> String {
        let key = self.resolve_lang(lang);
        if let Some(m) = self.style_colors.get(&key) {
            if let Some(c) = m.get(&scope) {
                return c.clone();
            }
        }
        // Some lexers share stylers (c→cpp, markup→html/xml, …).
        for alias in ["cpp", "python", "javascript", "rust", "html", "xml", "css"] {
            if let Some(m) = self.style_colors.get(alias) {
                if let Some(c) = m.get(&scope) {
                    return c.clone();
                }
            }
        }
        if let Some(c) = self.global_colors.get(&scope) {
            return c.clone();
        }
        default_scope_rgb(scope).to_owned()
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
    let resolved = engine.resolve_lang(lang);
    // Diff / TeX need dedicated scanners (empty or comment-only keyword tables).
    if let Some(special) = highlight_special(&resolved, text) {
        return special;
    }
    let hl = engine.lang_hl.get(&resolved);
    let kw_toks = hl.map(|h| {
        let refs: Vec<(Scope, &std::collections::BTreeSet<String>)> =
            h.groups.iter().map(|(s, set)| (*s, set)).collect();
        highlight_keyword_lang(
            text,
            &h.comment_line,
            &h.comment_start,
            &h.comment_end,
            &refs,
        )
    });

    if let Some(ts) = highlight_tree_sitter(lang, text) {
        // Tree-sitter owns its ranges (strings/comments/keywords/…); XML keywords fill gaps.
        let overlay = hl
            .map(|h| {
                let refs: Vec<(Scope, &std::collections::BTreeSet<String>)> =
                    h.groups.iter().map(|(s, set)| (*s, set)).collect();
                let exclude: Vec<(usize, usize)> = ts.iter().map(|t| (t.start, t.end)).collect();
                highlight_keywords(text, &refs, &exclude)
            })
            .unwrap_or_default();
        return merge_tokens(ts, overlay);
    }
    kw_toks.unwrap_or_default()
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
    let language = eng.guess_language(path);
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
pub unsafe extern "C" fn npp_doc_eol(engine: *const Engine, index: i32) -> i32 {
    let Some(eng) = eng_ref(engine) else {
        return 0;
    };
    if index < 0 {
        return 0;
    }
    match eng.docs.get(index as usize).map(Buffer::ending) {
        Some(LineEnding::Lf) => 1,
        Some(LineEnding::Cr) => 2,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_doc_set_eol(engine: *mut Engine, index: i32, eol: i32) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    let ending = match eol {
        1 => LineEnding::Lf,
        2 => LineEnding::Cr,
        _ => LineEnding::Crlf,
    };
    let Some(buf) = eng.docs.get_mut(index as usize) else {
        return false;
    };
    buf.set_ending(ending);
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
pub unsafe extern "C" fn npp_doc_set_language(
    engine: *mut Engine,
    index: i32,
    lang: *const c_char,
) -> bool {
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    if index < 0 {
        return false;
    }
    let Some(lang) = cstr_to_str(lang) else {
        return false;
    };
    let Some(m) = eng.meta.get_mut(index as usize) else {
        return false;
    };
    m.language = lang.to_owned();
    true
}

/// Number of languages available for the Language menu.
#[no_mangle]
pub unsafe extern "C" fn npp_lang_count(engine: *const Engine) -> i32 {
    eng_ref(engine)
        .map(|e| e.lang_names.len() as i32)
        .unwrap_or(0)
}

/// Language key at menu index (caller frees).
#[no_mangle]
pub unsafe extern "C" fn npp_lang_name(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    eng.lang_names
        .get(index as usize)
        .map(|s| to_cstring(s))
        .unwrap_or(ptr::null_mut())
}

/// Display label for menu index (caller frees).
#[no_mangle]
pub unsafe extern "C" fn npp_lang_display_name(engine: *const Engine, index: i32) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return ptr::null_mut();
    };
    if index < 0 {
        return ptr::null_mut();
    }
    eng.lang_names
        .get(index as usize)
        .map(|s| to_cstring(&eng.display_for(s)))
        .unwrap_or(ptr::null_mut())
}

/// Display label for a language key (caller frees). No engine needed.
#[no_mangle]
pub unsafe extern "C" fn npp_lang_display_name_for(lang: *const c_char) -> *mut c_char {
    let Some(lang) = cstr_to_str(lang) else {
        return to_cstring("Normal text");
    };
    if lang.starts_with("udl_") {
        return to_cstring(&lang.trim_start_matches("udl_").replace('_', " "));
    }
    to_cstring(display_name(lang))
}

/// Load a `.udl.xml` file into the engine (keyword highlighting only).
/// Returns number of UserLang entries registered, or -1 on error (optional err_out).
#[no_mangle]
pub unsafe extern "C" fn npp_udl_load(
    engine: *mut Engine,
    path: *const c_char,
    err_out: *mut *mut c_char,
) -> i32 {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    let Some(eng) = eng_mut(engine) else {
        return -1;
    };
    let Some(path) = cstr_to_str(path) else {
        return -1;
    };
    match npp_config::parse_udl(Path::new(path)) {
        Ok(defs) => {
            let n = defs.len() as i32;
            eng.register_udl(&defs);
            n
        }
        Err(e) => {
            if !err_out.is_null() {
                *err_out = to_cstring(&e);
            }
            -1
        }
    }
}

/// RGB hex (`RRGGBB`) foreground for `scope` under `lang` (caller frees).
#[no_mangle]
pub unsafe extern "C" fn npp_scope_fg(
    engine: *const Engine,
    lang: *const c_char,
    scope: u32,
) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return to_cstring(default_scope_rgb(Scope::Default));
    };
    let lang = cstr_to_str(lang).unwrap_or("normal");
    let sc = match scope {
        1 => Scope::Keyword,
        2 => Scope::Type,
        3 => Scope::Str,
        4 => Scope::Comment,
        5 => Scope::Number,
        6 => Scope::Operator,
        7 => Scope::Function,
        8 => Scope::Preproc,
        _ => Scope::Default,
    };
    to_cstring(&eng.color_for(lang, sc))
}

/// Load a theme / stylers XML, replacing current colors. Returns false on error.
#[no_mangle]
pub unsafe extern "C" fn npp_stylers_load(
    engine: *mut Engine,
    path: *const c_char,
    err_out: *mut *mut c_char,
) -> bool {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    let Some(eng) = eng_mut(engine) else {
        return false;
    };
    let Some(path) = cstr_to_str(path) else {
        return false;
    };
    if eng.apply_stylers_file(Path::new(path)) {
        true
    } else {
        if !err_out.is_null() {
            *err_out = to_cstring("failed to parse stylers/theme XML");
        }
        false
    }
}

/// Theme editor foreground (`RRGGBB`) or empty.
#[no_mangle]
pub unsafe extern "C" fn npp_editor_fg(engine: *const Engine) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return to_cstring("");
    };
    to_cstring(eng.editor_fg.as_deref().unwrap_or(""))
}

/// Theme editor background (`RRGGBB`) or empty.
#[no_mangle]
pub unsafe extern "C" fn npp_editor_bg(engine: *const Engine) -> *mut c_char {
    let Some(eng) = eng_ref(engine) else {
        return to_cstring("");
    };
    to_cstring(eng.editor_bg.as_deref().unwrap_or(""))
}

/// Guess language from path; uses engine extension map when `engine` is non-null.
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

/// Like [`npp_language_for_path`] but uses the engine's XML-backed extension map.
#[no_mangle]
pub unsafe extern "C" fn npp_language_for_path_ex(
    engine: *const Engine,
    path: *const c_char,
) -> *mut c_char {
    let Some(path) = cstr_to_str(path) else {
        return to_cstring("normal");
    };
    if let Some(eng) = eng_ref(engine) {
        return to_cstring(&eng.guess_language(Path::new(path)));
    }
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

#[repr(C)]
pub struct NppMatchC {
    pub start: u32,
    pub end: u32,
}

fn search_opts(match_case: bool, whole_word: bool, regex: bool) -> npp_core::search::SearchOptions {
    npp_core::search::SearchOptions {
        match_case,
        whole_word,
        regex,
        dir: npp_core::search::Direction::Forward,
        wrap: true,
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_find_all(
    text: *const c_char,
    pattern: *const c_char,
    match_case: bool,
    whole_word: bool,
    regex: bool,
    out_matches: *mut *mut NppMatchC,
    err_out: *mut *mut c_char,
) -> i32 {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    if out_matches.is_null() {
        return 0;
    }
    *out_matches = ptr::null_mut();
    let Some(text) = cstr_to_str(text) else {
        return 0;
    };
    let Some(pattern) = cstr_to_str(pattern) else {
        return 0;
    };
    let opts = search_opts(match_case, whole_word, regex);
    match npp_core::search::find_all(text, pattern, opts) {
        Ok(matches) => {
            if matches.is_empty() {
                return 0;
            }
            let boxed: Box<[NppMatchC]> = matches
                .into_iter()
                .map(|m| NppMatchC {
                    start: m.start as u32,
                    end: m.end as u32,
                })
                .collect::<Vec<_>>()
                .into_boxed_slice();
            let len = boxed.len() as i32;
            *out_matches = Box::into_raw(boxed) as *mut NppMatchC;
            len
        }
        Err(e) => {
            if !err_out.is_null() {
                *err_out = to_cstring(&e.to_string());
            }
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_matches_free(matches: *mut NppMatchC, count: i32) {
    if matches.is_null() || count <= 0 {
        return;
    }
    let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(matches, count as usize));
}

#[no_mangle]
pub unsafe extern "C" fn npp_find_count(
    text: *const c_char,
    pattern: *const c_char,
    match_case: bool,
    whole_word: bool,
    regex: bool,
    err_out: *mut *mut c_char,
) -> i32 {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    let Some(text) = cstr_to_str(text) else {
        return 0;
    };
    let Some(pattern) = cstr_to_str(pattern) else {
        return 0;
    };
    match npp_core::search::count(text, pattern, search_opts(match_case, whole_word, regex)) {
        Ok(n) => n as i32,
        Err(e) => {
            if !err_out.is_null() {
                *err_out = to_cstring(&e.to_string());
            }
            -1
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn npp_replace_all(
    text: *const c_char,
    pattern: *const c_char,
    replacement: *const c_char,
    match_case: bool,
    whole_word: bool,
    regex: bool,
    out_text: *mut *mut c_char,
    err_out: *mut *mut c_char,
) -> i32 {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
    if !out_text.is_null() {
        *out_text = ptr::null_mut();
    }
    let Some(text) = cstr_to_str(text) else {
        return -1;
    };
    let Some(pattern) = cstr_to_str(pattern) else {
        return -1;
    };
    let replacement = cstr_to_str(replacement).unwrap_or("");
    match npp_core::search::replace_all(
        text,
        pattern,
        replacement,
        search_opts(match_case, whole_word, regex),
    ) {
        Ok((new_text, n)) => {
            if !out_text.is_null() {
                *out_text = to_cstring(&new_text);
            }
            n as i32
        }
        Err(e) => {
            if !err_out.is_null() {
                *err_out = to_cstring(&e.to_string());
            }
            -1
        }
    }
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

    #[test]
    fn language_catalog_and_set() {
        let eng = npp_engine_create();
        unsafe {
            let n = npp_lang_count(eng);
            assert!(n > 50, "expected stock langs, got {n}");
            let name0 = npp_lang_name(eng, 0);
            assert!(!name0.is_null());
            let s = CStr::from_ptr(name0).to_string_lossy().into_owned();
            npp_string_free(name0);
            assert_eq!(s, "normal");
            let cpp = CString::new("cpp").unwrap();
            assert!(npp_doc_set_language(eng, 0, cpp.as_ptr()));
            let got = npp_doc_language(eng, 0);
            assert_eq!(CStr::from_ptr(got).to_str().unwrap(), "cpp");
            npp_string_free(got);
            let disp = npp_lang_display_name_for(cpp.as_ptr());
            assert_eq!(CStr::from_ptr(disp).to_str().unwrap(), "C++");
            npp_string_free(disp);
            let fg = npp_scope_fg(eng, cpp.as_ptr(), 1);
            let fg_s = CStr::from_ptr(fg).to_string_lossy().into_owned();
            npp_string_free(fg);
            assert_eq!(fg_s.len(), 6);
            npp_engine_destroy(eng);
        }
    }

    #[test]
    fn highlight_cpp_keywords_and_comments() {
        let eng = npp_engine_create();
        unsafe {
            let lang = CString::new("cpp").unwrap();
            let text = CString::new("// hi\nint main() { return 0; }\n").unwrap();
            let mut toks: *mut NppTokenC = ptr::null_mut();
            let n = npp_highlight(eng, lang.as_ptr(), text.as_ptr(), &mut toks);
            assert!(n > 0, "cpp should produce tokens from langs.model.xml");
            let mut saw_comment = false;
            let mut saw_kw = false;
            for i in 0..n as usize {
                let t = &*toks.add(i);
                if t.scope == 4 {
                    saw_comment = true;
                }
                if t.scope == 1 {
                    saw_kw = true;
                }
            }
            npp_tokens_free(toks, n);
            assert!(saw_comment && saw_kw);
            npp_engine_destroy(eng);
        }
    }

    #[test]
    fn xml_tag_color_from_stylers() {
        let langs = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../PowerEditor/src/langs.model.xml"
        );
        let stylers = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../PowerEditor/src/stylers.model.xml"
        );
        unsafe {
            let eng = npp_engine_create_with_langs(CString::new(langs).unwrap().as_ptr());
            assert!(!eng.is_null());
            let stylers = CString::new(stylers).unwrap();
            assert!(npp_stylers_load(eng, stylers.as_ptr(), ptr::null_mut()));
            let lang = CString::new("xml").unwrap();
            let fg = npp_scope_fg(eng, lang.as_ptr(), 1); // Keyword ← TAG
            let s = CStr::from_ptr(fg).to_string_lossy().into_owned();
            npp_string_free(fg);
            // TAG fgColor BGR 0000FF → RGB FF0000
            assert_eq!(s, "FF0000", "xml Keyword should come from TAG, got {s}");
            npp_engine_destroy(eng);
        }
    }

    #[test]
    fn audit_all_stock_languages_highlight() {
        use npp_config::parse_langs_model;
        use npp_highlight::{has_grammar, highlight_tree_sitter, Scope};

        let langs_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../PowerEditor/src/langs.model.xml"
        );
        let stylers_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../PowerEditor/src/stylers.model.xml"
        );
        let defs = parse_langs_model(Path::new(langs_path)).expect("langs.model.xml");
        let mut failures: Vec<String> = Vec::new();

        // Tree-sitter languages: require rich scopes on idiomatic samples.
        let ts_samples: &[(&str, &str, &[Scope])] = &[
            (
                "rust",
                "fn main() {\n  let x = 42; // c\n  foo(\"s\");\n}\n",
                &[Scope::Keyword, Scope::Number, Scope::Comment, Scope::Str, Scope::Function],
            ),
            (
                "python",
                "def foo(x):\n  # c\n  return 1\n",
                &[Scope::Keyword, Scope::Comment, Scope::Number, Scope::Function],
            ),
            (
                "javascript",
                "function foo(x) {\n  // c\n  return \"s\";\n}\n",
                &[Scope::Keyword, Scope::Comment, Scope::Str, Scope::Function],
            ),
            (
                "typescript",
                "function foo(x: number): string {\n  return \"s\";\n}\n",
                &[Scope::Keyword, Scope::Str, Scope::Function],
            ),
            (
                "go",
                "package main\nfunc main() {\n  x := 1 // c\n}\n",
                &[Scope::Keyword, Scope::Comment, Scope::Number, Scope::Function],
            ),
            (
                "java",
                "class A {\n  int foo() { return 1; /* c */ }\n}\n",
                &[Scope::Keyword, Scope::Comment, Scope::Number, Scope::Function],
            ),
            (
                "ruby",
                "def foo(x)\n  # c\n  x + 1\nend\n",
                &[Scope::Keyword, Scope::Comment, Scope::Number, Scope::Function],
            ),
            (
                "html",
                "<div class=\"a\"><!-- c -->x</div>\n",
                &[Scope::Keyword, Scope::Type, Scope::Str, Scope::Comment],
            ),
            (
                "css",
                "body { color: #fff; /* c */ }\n",
                &[Scope::Keyword, Scope::Comment],
            ),
            (
                "json",
                "{\"a\": 1, \"b\": true}\n",
                &[Scope::Str, Scope::Number],
            ),
            (
                "toml",
                "a = 1\n# c\n",
                &[Scope::Number, Scope::Comment],
            ),
            (
                "xml",
                "<?xml version=\"1.0\"?><!-- c --><root a=\"v\">t</root>\n",
                &[Scope::Keyword, Scope::Type, Scope::Str, Scope::Comment],
            ),
            (
                "yaml",
                "a: 1\nb: \"s\"\n# c\n",
                &[Scope::Number, Scope::Str, Scope::Comment],
            ),
        ];
        for (lang, sample, need) in ts_samples {
            assert!(has_grammar(lang), "{lang} should have grammar");
            let Some(toks) = highlight_tree_sitter(lang, sample) else {
                failures.push(format!("{lang}: tree-sitter returned None"));
                continue;
            };
            if toks.is_empty() {
                failures.push(format!("{lang}: 0 tokens"));
                continue;
            }
            for scope in *need {
                if !toks.iter().any(|t| t.scope == *scope) {
                    failures.push(format!(
                        "{lang}: missing {scope:?} in {} tokens",
                        toks.len()
                    ));
                }
            }
        }

        unsafe {
            let eng = npp_engine_create_with_langs(CString::new(langs_path).unwrap().as_ptr());
            assert!(!eng.is_null());
            let _ = npp_stylers_load(
                eng,
                CString::new(stylers_path).unwrap().as_ptr(),
                ptr::null_mut(),
            );

            for def in &defs {
                let name = def.name.as_str();
                if matches!(name, "normal" | "searchResult" | "udf" | "ext") {
                    continue;
                }
                // Prefer curated TS sample when present.
                let sample = ts_samples
                    .iter()
                    .find(|(k, _, _)| {
                        name == *k
                            || (*k == "javascript" && name.contains("javascript"))
                            || name.starts_with(&format!("{k}."))
                    })
                    .map(|(_, s, _)| (*s).to_owned())
                    .unwrap_or_else(|| {
                        if name == "diff" {
                            return "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n".into();
                        }
                        if name == "latex" || name == "tex" {
                            return "% c\n\\begin{document}\nHello\n\\end{document}\n".into();
                        }
                        let mut s = String::new();
                        if !def.comment_line.is_empty() {
                            s.push_str(&def.comment_line);
                            s.push_str(" comment\n");
                        } else if !def.comment_start.is_empty() && !def.comment_end.is_empty() {
                            s.push_str(&def.comment_start);
                            s.push('c');
                            s.push_str(&def.comment_end);
                            s.push('\n');
                        }
                        if let Some(words) = def.keywords.values().next() {
                            if let Some(w) = words.split_whitespace().next() {
                                // Prefer uppercase form so case-insensitive matching is exercised.
                                s.push_str(&w.to_ascii_uppercase());
                                s.push(' ');
                            }
                        }
                        s.push_str("ident 42 \"str\"\n");
                        s
                    });

                let lang = CString::new(name).unwrap();
                let text = CString::new(sample.as_str()).unwrap();
                let mut toks: *mut NppTokenC = ptr::null_mut();
                let count = npp_highlight(eng, lang.as_ptr(), text.as_ptr(), &mut toks);
                if count <= 0 {
                    failures.push(format!(
                        "{name}: 0 tokens (comment_line={:?})",
                        def.comment_line
                    ));
                    continue;
                }
                let mut saw_structure = false;
                for i in 0..count as usize {
                    let t = &*toks.add(i);
                    // Comment(4) Keyword(1) Type(2) Str(3) Number(5) Operator(6) Function(7) Preproc(8)
                    if matches!(t.scope, 1 | 2 | 3 | 4 | 5 | 7 | 8) {
                        saw_structure = true;
                        break;
                    }
                }
                npp_tokens_free(toks, count);
                if !saw_structure {
                    failures.push(format!(
                        "{name}: only operators/default — weak highlight for sample"
                    ));
                }
            }
            npp_engine_destroy(eng);
        }

        if !failures.is_empty() {
            panic!(
                "highlight audit failures ({}):\n{}",
                failures.len(),
                failures.join("\n")
            );
        }
    }

}
