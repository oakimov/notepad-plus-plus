//! Settings persistence parity with `PowerEditor/src/Parameters.h`.
//!
//! Reads the stock `langs.model.xml` / `stylers.model.xml` shipped with the
//! Win32 tree and user `config.xml` / `session.xml` files via `quick-xml`.
//! Native-language string tables (`installer/nativeLang/*.xml`) load as
//! generic key maps so the Swift side can localize menus.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Resolve `~/Library/Application Support/NppMac`, creating it on demand.
#[must_use]
pub fn support_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_owned());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("NppMac")
}

/// Ensure the support dir + `plugins/` exist.
pub fn ensure_dirs() -> std::io::Result<PathBuf> {
    let dir = support_dir();
    std::fs::create_dir_all(dir.join("plugins"))?;
    Ok(dir)
}

/// In-memory recent-files list (persisted to `config.xml`).
#[derive(Debug, Default, Clone)]
pub struct RecentFiles {
    items: Vec<PathBuf>,
    capacity: usize,
}

impl RecentFiles {
    /// Empty list with Notepad++-style default capacity.
    #[must_use]
    pub fn new() -> Self {
        Self {
            items: Vec::new(),
            capacity: 10,
        }
    }

    /// Push a path to the front, de-duplicated and capped.
    pub fn push(&mut self, path: PathBuf) {
        self.items.retain(|p| p != &path);
        self.items.insert(0, path);
        self.items.truncate(self.capacity.max(1));
    }

    /// Current entries, most recent first.
    #[must_use]
    pub fn items(&self) -> &[PathBuf] {
        &self.items
    }
}

/// One language entry from `langs.model.xml`.
#[derive(Debug, Clone, Default)]
pub struct LanguageDef {
    /// `name` attribute (e.g. `cpp`).
    pub name: String,
    /// Space-separated extensions.
    pub ext: String,
    /// Line comment token.
    pub comment_line: String,
    /// Block comment open/close.
    pub comment_start: String,
    /// Block comment close.
    pub comment_end: String,
    /// `Keywords name -> words` map.
    pub keywords: BTreeMap<String, String>,
}

/// Parse `<Language>` entries from a `langs.model.xml` file.
pub fn parse_langs_model(path: &Path) -> Result<Vec<LanguageDef>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut langs = Vec::new();
    let mut cur: Option<LanguageDef> = None;
    let mut kw_name = String::new();
    let mut buf = Vec::new();
    // Helper: build a LanguageDef from a tag's attributes.
    let read_lang = |e: &quick_xml::events::BytesStart<'_>| {
        let mut l = LanguageDef::default();
        for a in e.attributes().flatten() {
            match a.key.as_ref() {
                b"name" => l.name = attr(&a),
                b"ext" => l.ext = attr(&a),
                b"commentLine" => l.comment_line = attr(&a),
                b"commentStart" => l.comment_start = attr(&a),
                b"commentEnd" => l.comment_end = attr(&a),
                _ => {}
            }
        }
        l
    };
    loop {
        match r.read_event_into(&mut buf) {
            // Self-closing `<Language ... />` (e.g. `normal`) has no End event.
            Ok(Event::Empty(e)) => match e.name().as_ref() {
                b"Language" => langs.push(read_lang(&e)),
                b"Keywords" => {
                    kw_name.clear();
                    for a in e.attributes().flatten() {
                        if a.key.as_ref() == b"name" {
                            kw_name = attr(&a);
                        }
                    }
                    if let Some(l) = cur.as_mut() {
                        l.keywords.insert(kw_name.clone(), String::new());
                    }
                }
                _ => {}
            },
            Ok(Event::Start(e)) => match e.name().as_ref() {
                b"Language" => cur = Some(read_lang(&e)),
                b"Keywords" => {
                    kw_name.clear();
                    for a in e.attributes().flatten() {
                        if a.key.as_ref() == b"name" {
                            kw_name = attr(&a);
                        }
                    }
                    // Accumulate Text until the matching End; empty
                    // `<Keywords></Keywords>` yields End immediately.
                    let mut text = String::new();
                    loop {
                        match r.read_event_into(&mut buf) {
                            Ok(Event::Text(t)) => {
                                text.push_str(&t.xml10_content().unwrap_or_default());
                            }
                            Ok(Event::End(_)) | Ok(Event::Eof) => break,
                            Err(e) => return Err(e.to_string()),
                            _ => {}
                        }
                        buf.clear();
                    }
                    if let Some(l) = cur.as_mut() {
                        l.keywords.insert(kw_name.clone(), text);
                    }
                }
                _ => {}
            },
            Ok(Event::End(e)) if e.name().as_ref() == b"Language" => {
                if let Some(l) = cur.take() {
                    langs.push(l);
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(langs)
}

/// One User-Defined Language from a `.udl.xml` file (load-only subset).
#[derive(Debug, Clone, Default)]
pub struct UdlDef {
    /// Display name from `UserLang/@name`.
    pub name: String,
    /// Stable engine key (`udl_<slug>`).
    pub key: String,
    /// Space-separated extensions.
    pub ext: String,
    /// Keyword class → words (mapped to stock `instreN`/`typeN` names).
    pub keywords: BTreeMap<String, String>,
    /// Line comment token if parsed from Comments list (best-effort).
    pub comment_line: String,
}

fn udl_slug(name: &str) -> String {
    let mut s = String::from("udl_");
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            s.push(c.to_ascii_lowercase());
        } else if c == ' ' || c == '-' || c == '_' {
            if !s.ends_with('_') {
                s.push('_');
            }
        }
    }
    while s.ends_with('_') {
        s.pop();
    }
    if s == "udl" {
        s.push_str("_lang");
    }
    s
}

/// Map UDL KeywordLists names onto stock keyword class keys used by highlighting.
fn map_udl_keyword_class(name: &str) -> Option<&'static str> {
    match name {
        "Keywords1" => Some("instre1"),
        "Keywords2" => Some("type1"),
        "Keywords3" => Some("instre2"),
        "Keywords4" => Some("type2"),
        "Keywords5" => Some("instre3"),
        "Keywords6" => Some("type3"),
        "Keywords7" => Some("instre4"),
        "Keywords8" => Some("type4"),
        _ => None,
    }
}

/// Parse a Notepad++ `.udl.xml` / `userDefineLang.xml` for keyword highlighting.
pub fn parse_udl(path: &Path) -> Result<Vec<UdlDef>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut out = Vec::new();
    let mut cur: Option<UdlDef> = None;
    let mut buf = Vec::new();
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) if e.name().as_ref() == b"UserLang" => {
                let mut name = String::new();
                let mut ext = String::new();
                for a in e.attributes().flatten() {
                    match a.key.as_ref() {
                        b"name" => name = attr(&a),
                        b"ext" => ext = attr(&a),
                        _ => {}
                    }
                }
                if !name.is_empty() {
                    cur = Some(UdlDef {
                        key: udl_slug(&name),
                        name,
                        ext,
                        keywords: BTreeMap::new(),
                        comment_line: String::new(),
                    });
                }
            }
            Ok(Event::Start(e)) if e.name().as_ref() == b"Keywords" => {
                let mut kw_name = String::new();
                for a in e.attributes().flatten() {
                    if a.key.as_ref() == b"name" {
                        kw_name = attr(&a);
                    }
                }
                let mut text = String::new();
                loop {
                    match r.read_event_into(&mut buf) {
                        Ok(Event::Text(t)) => {
                            text.push_str(&t.xml10_content().unwrap_or_default());
                        }
                        Ok(Event::End(_)) | Ok(Event::Eof) => break,
                        Err(e) => return Err(e.to_string()),
                        _ => {}
                    }
                    buf.clear();
                }
                if let Some(u) = cur.as_mut() {
                    if kw_name == "Comments" {
                        // UDL Comments: `00# 01… 02((EOL)) …` — first token after 00 is line comment.
                        if let Some(tok) = text.split_whitespace().find_map(|t| {
                            t.strip_prefix("00").filter(|s| !s.is_empty())
                        }) {
                            u.comment_line = tok.to_string();
                        }
                    } else if let Some(mapped) = map_udl_keyword_class(&kw_name) {
                        if !text.trim().is_empty() {
                            u.keywords.insert(mapped.to_string(), text);
                        }
                    }
                }
            }
            Ok(Event::End(e)) if e.name().as_ref() == b"UserLang" => {
                if let Some(u) = cur.take() {
                    out.push(u);
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

fn attr(a: &quick_xml::events::attributes::Attribute) -> String {
    let raw = String::from_utf8_lossy(a.value.as_ref()).into_owned();
    quick_xml::escape::unescape(&raw)
        .map(|s| s.into_owned())
        .unwrap_or(raw)
}

/// One `WordsStyle` row from `stylers.model.xml`.
#[derive(Debug, Clone, Default)]
pub struct StyleDef {
    /// Style display name (`INSTRUCTION WORD`, …).
    pub name: String,
    /// `fgColor` hex (BGR in NPP files — preserved verbatim, converted later).
    pub fg: String,
    /// `bgColor` hex.
    pub bg: String,
    /// `fontStyle` bitmask.
    pub font_style: String,
    /// `keywordClass` link into `langs.model.xml`.
    pub keyword_class: String,
}

/// `LexerType name -> styles` from `stylers.model.xml`.
pub fn parse_stylers_model(path: &Path) -> Result<BTreeMap<String, Vec<StyleDef>>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut out: BTreeMap<String, Vec<StyleDef>> = BTreeMap::new();
    let mut cur: Option<String> = None;
    let mut buf = Vec::new();
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Empty(e)) | Ok(Event::Start(e)) => {
                match e.name().as_ref() {
                    b"LexerType" => {
                        let mut name = String::new();
                        for a in e.attributes().flatten() {
                            if a.key.as_ref() == b"name" {
                                name = attr(&a);
                            }
                        }
                        out.entry(name.clone()).or_default();
                        cur = Some(name);
                    }
                    b"WordsStyle" => {
                        let mut s = StyleDef::default();
                        for a in e.attributes().flatten() {
                            let v = attr(&a);
                            match a.key.as_ref() {
                                b"name" => s.name = v,
                                b"fgColor" => s.fg = v,
                                b"bgColor" => s.bg = v,
                                b"fontStyle" => s.font_style = v,
                                b"keywordClass" => s.keyword_class = v,
                                _ => {}
                            }
                        }
                        if let Some(k) = cur.as_ref() {
                            out.entry(k.clone()).or_default().push(s);
                        }
                    }
                    _ => {}
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

/// Flat `menuId -> name` string table from a `nativeLang/*.xml` file.
pub fn parse_native_lang(path: &Path) -> Result<BTreeMap<String, String>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut out = BTreeMap::new();
    let mut buf = Vec::new();
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Empty(e)) if e.name().as_ref() == b"Item" => {
                let (mut id, mut name) = (String::new(), String::new());
                for a in e.attributes().flatten() {
                    match a.key.as_ref() {
                        b"menuId" | b"id" | b"nameId" => id = attr(&a),
                        b"name" => name = attr(&a),
                        _ => {}
                    }
                }
                if !id.is_empty() {
                    out.insert(id, name);
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

/// Session file entry (open file + cursor).
#[derive(Debug, Clone, Default)]
pub struct SessionFile {
    /// File path.
    pub filename: String,
    /// Active view index.
    pub view: usize,
}

/// Minimal `session.xml` writer/reader (M2 scope: file list only).
pub fn write_session(path: &Path, files: &[SessionFile]) -> Result<(), String> {
    let mut s = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n<Session>\n");
    for f in files {
        s.push_str(&format!(
            "<File filename=\"{}\" view=\"{}\" />\n",
            xml_escape(&f.filename),
            f.view
        ));
    }
    s.push_str("</Session>\n</NotepadPlus>\n");
    std::fs::write(path, s).map_err(|e| e.to_string())
}

/// Read a minimal `session.xml` produced by [`write_session`].
pub fn read_session(path: &Path) -> Result<Vec<SessionFile>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut out = Vec::new();
    let mut buf = Vec::new();
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Empty(e)) | Ok(Event::Start(e)) if e.name().as_ref() == b"File" => {
                let mut filename = String::new();
                let mut view = 0usize;
                for a in e.attributes().flatten() {
                    match a.key.as_ref() {
                        b"filename" => filename = attr(&a),
                        b"view" => view = attr(&a).parse().unwrap_or(0),
                        _ => {}
                    }
                }
                if !filename.is_empty() {
                    out.push(SessionFile { filename, view });
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(out)
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Persist recent files as a simple newline-separated path list.
pub fn write_recent(path: &Path, recent: &RecentFiles) -> Result<(), String> {
    let body = recent
        .items()
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("\n");
    std::fs::write(path, body + "\n").map_err(|e| e.to_string())
}

/// Load recent files list from disk.
pub fn read_recent(path: &Path) -> Result<RecentFiles, String> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut recent = RecentFiles::new();
    // Push in reverse so the first line ends up most-recent.
    let lines: Vec<_> = text.lines().filter(|l| !l.is_empty()).collect();
    for line in lines.into_iter().rev() {
        recent.push(PathBuf::from(line));
    }
    Ok(recent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recent_files_dedupes_and_caps() {
        let mut r = RecentFiles::new();
        r.push(PathBuf::from("/a"));
        r.push(PathBuf::from("/b"));
        r.push(PathBuf::from("/a"));
        assert_eq!(r.items(), &[PathBuf::from("/a"), PathBuf::from("/b")]);
    }

    #[test]
    fn parses_stock_langs_model() {
        let p = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..")
            .join("PowerEditor")
            .join("src")
            .join("langs.model.xml");
        if !p.exists() {
            return; // repo layout differs; skip
        }
        let langs = parse_langs_model(&p).unwrap();
        // 95 <Language> opens per model file (16 self-closed, no </Language>).
        assert_eq!(langs.len(), 95, "got {} languages", langs.len());
        let cpp = langs.iter().find(|l| l.name == "cpp").expect("cpp entry");
        assert!(cpp.ext.contains("cpp"));
        assert!(!cpp.keywords.is_empty());
    }

    #[test]
    fn parses_stock_stylers_model() {
        let p = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..")
            .join("PowerEditor")
            .join("src")
            .join("stylers.model.xml");
        if !p.exists() {
            return;
        }
        let styles = parse_stylers_model(&p).unwrap();
        assert_eq!(styles.len(), 92, "got {} lexers", styles.len());
        let cpp = styles.get("cpp").expect("cpp lexer");
        assert!(cpp.iter().any(|s| s.name == "INSTRUCTION WORD"));
    }

    #[test]
    fn session_round_trip() {
        let dir = std::env::temp_dir().join("nppmac-config-test");
        let _ = std::fs::create_dir_all(&dir);
        let p = dir.join("session.xml");
        write_session(
            &p,
            &[SessionFile {
                filename: "/a.txt".into(),
                view: 0,
            }],
        )
        .unwrap();
        let text = std::fs::read_to_string(&p).unwrap();
        assert!(text.contains("/a.txt"));
        let loaded = read_session(&p).unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].filename, "/a.txt");
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn parses_markdown_udl() {
        let p = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..")
            .join("PowerEditor")
            .join("bin")
            .join("userDefineLangs")
            .join("markdown._preinstalled.udl.xml");
        if !p.exists() {
            return;
        }
        let langs = parse_udl(&p).unwrap();
        assert!(!langs.is_empty());
        assert!(langs[0].name.contains("Markdown"));
        assert!(langs[0].key.starts_with("udl_"));
        assert!(!langs[0].keywords.is_empty());
    }

    #[test]
    fn recent_round_trip() {
        let dir = std::env::temp_dir().join("nppmac-config-test");
        let _ = std::fs::create_dir_all(&dir);
        let p = dir.join("recent.txt");
        let mut r = RecentFiles::new();
        r.push(PathBuf::from("/z"));
        r.push(PathBuf::from("/a"));
        write_recent(&p, &r).unwrap();
        let loaded = read_recent(&p).unwrap();
        assert_eq!(loaded.items()[0], PathBuf::from("/a"));
        assert_eq!(loaded.items()[1], PathBuf::from("/z"));
        let _ = std::fs::remove_file(&p);
    }
}
