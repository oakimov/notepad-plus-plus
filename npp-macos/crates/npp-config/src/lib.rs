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

/// `COLORSTYLE_ALL` from `NppConstants.h` — omit `colorStyle` attr when equal.
const UDL_COLORSTYLE_ALL: u8 = 0x01 | 0x02;

/// Exactly 28 keyword-list names, SciLexer.h `SCE_USER_KWLIST_*` / GlobalMappers order.
pub const UDL_KEYWORD_LIST_NAMES: [&str; 28] = [
    "Comments",
    "Numbers, prefix1",
    "Numbers, prefix2",
    "Numbers, extras1",
    "Numbers, extras2",
    "Numbers, suffix1",
    "Numbers, suffix2",
    "Numbers, range",
    "Operators1",
    "Operators2",
    "Folders in code1, open",
    "Folders in code1, middle",
    "Folders in code1, close",
    "Folders in code2, open",
    "Folders in code2, middle",
    "Folders in code2, close",
    "Folders in comment, open",
    "Folders in comment, middle",
    "Folders in comment, close",
    "Keywords1",
    "Keywords2",
    "Keywords3",
    "Keywords4",
    "Keywords5",
    "Keywords6",
    "Keywords7",
    "Keywords8",
    "Delimiters",
];

/// One UDL `WordsStyle` row (`SCE_USER_STYLE_*` 0..23).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UdlStyle {
    /// Style display name (`DEFAULT`, `COMMENTS`, `KEYWORDS1`, …).
    pub name: String,
    /// `SCE_USER_STYLE_*` id 0..23.
    pub style_id: u8,
    /// 6-digit hex RGB as in XML (e.g. `"333333"`).
    pub fg_color: String,
    /// Background hex RGB.
    pub bg_color: String,
    /// Color apply mask; `3` (`COLORSTYLE_ALL`) is omitted on write.
    pub color_style: u8,
    /// Font face; empty means omit on write.
    pub font_name: String,
    /// Bit flags: bold / italic / underline.
    pub font_style: u8,
    /// Font size string; empty means omit on write (`STYLE_NOT_USED`).
    pub font_size: String,
    /// Nesting bitmask.
    pub nesting: u32,
}

/// UDL `<Settings>` block.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UdlSettings {
    /// `Global/@caseIgnored`.
    pub case_ignored: bool,
    /// `Global/@allowFoldOfComments`.
    pub allow_fold_of_comments: bool,
    /// `Global/@foldCompact`.
    pub fold_compact: bool,
    /// `Global/@forcePureLC`.
    pub force_pure_lc: u8,
    /// `Global/@decimalSeparator`.
    pub decimal_separator: u8,
    /// `Prefix/@Keywords1..Keywords8`.
    pub prefix: [bool; 8],
}

/// Full User-Defined Language model (UDL v2.1).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UdlLang {
    /// Display name from `UserLang/@name`.
    pub name: String,
    /// Stable engine key (`udl_<slug>`).
    pub key: String,
    /// Space-separated extensions.
    pub ext: String,
    /// `UserLang/@udlVersion` (typically `"2.1"`).
    pub udl_version: String,
    /// `UserLang/@darkModeTheme == "yes"`.
    pub dark_mode_theme: bool,
    /// `<Settings>` values.
    pub settings: UdlSettings,
    /// Exactly 28 lists keyed by [`UDL_KEYWORD_LIST_NAMES`].
    pub keyword_lists: BTreeMap<String, String>,
    /// `<Styles>/<WordsStyle>` rows.
    pub styles: Vec<UdlStyle>,
}

/// Temporary alias while call sites migrate off the load-only subset name.
pub type UdlDef = UdlLang;

/// Build a stable `udl_<slug>` key from a UDL display name.
#[must_use]
pub fn udl_slug(name: &str) -> String {
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

fn empty_keyword_lists() -> BTreeMap<String, String> {
    UDL_KEYWORD_LIST_NAMES
        .iter()
        .map(|&n| (n.to_string(), String::new()))
        .collect()
}

/// Map style display name → `SCE_USER_STYLE_*` id.
fn udl_style_id(name: &str) -> Option<u8> {
    Some(match name {
        "DEFAULT" => 0,
        "COMMENTS" => 1,
        "LINE COMMENTS" => 2,
        "NUMBERS" => 3,
        "KEYWORDS1" => 4,
        "KEYWORDS2" => 5,
        "KEYWORDS3" => 6,
        "KEYWORDS4" => 7,
        "KEYWORDS5" => 8,
        "KEYWORDS6" => 9,
        "KEYWORDS7" => 10,
        "KEYWORDS8" => 11,
        "OPERATORS" => 12,
        "FOLDER IN CODE1" => 13,
        "FOLDER IN CODE2" => 14,
        "FOLDER IN COMMENT" => 15,
        "DELIMITERS1" => 16,
        "DELIMITERS2" => 17,
        "DELIMITERS3" => 18,
        "DELIMITERS4" => 19,
        "DELIMITERS5" => 20,
        "DELIMITERS6" => 21,
        "DELIMITERS7" => 22,
        "DELIMITERS8" => 23,
        _ => return None,
    })
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

fn parse_yes_no(s: &str) -> bool {
    s.eq_ignore_ascii_case("yes")
}

fn yes_no(b: bool) -> &'static str {
    if b {
        "yes"
    } else {
        "no"
    }
}

fn parse_u8_attr(s: &str, default: u8) -> u8 {
    s.parse().unwrap_or(default)
}

/// Line-comment token from Comments list (`00# …` → `"#"`), for legacy highlight.
impl UdlLang {
    /// Best-effort line comment from the Comments keyword list (`00` token).
    #[must_use]
    pub fn comment_line(&self) -> String {
        let Some(text) = self.keyword_lists.get("Comments") else {
            return String::new();
        };
        text.split_whitespace()
            .find_map(|t| t.strip_prefix("00").filter(|s| !s.is_empty()))
            .unwrap_or("")
            .to_string()
    }

    /// Keywords1..8 mapped to stock `instreN`/`typeN` keys (non-empty only).
    #[must_use]
    pub fn highlight_keywords(&self) -> BTreeMap<String, String> {
        let mut out = BTreeMap::new();
        for (name, text) in &self.keyword_lists {
            if let Some(mapped) = map_udl_keyword_class(name) {
                if !text.trim().is_empty() {
                    out.insert(mapped.to_string(), text.clone());
                }
            }
        }
        out
    }
}

fn read_words_style(e: &quick_xml::events::BytesStart<'_>) -> Option<UdlStyle> {
    let mut s = UdlStyle {
        color_style: UDL_COLORSTYLE_ALL,
        ..UdlStyle::default()
    };
    for a in e.attributes().flatten() {
        let v = attr(&a);
        match a.key.as_ref() {
            b"name" => s.name = v,
            b"fgColor" => s.fg_color = v,
            b"bgColor" => s.bg_color = v,
            b"colorStyle" => s.color_style = parse_u8_attr(&v, UDL_COLORSTYLE_ALL),
            b"fontName" => s.font_name = v,
            b"fontStyle" => s.font_style = parse_u8_attr(&v, 0),
            b"fontSize" => s.font_size = v,
            b"nesting" => s.nesting = v.parse().unwrap_or(0),
            _ => {}
        }
    }
    if s.name.is_empty() {
        return None;
    }
    s.style_id = udl_style_id(&s.name)?;
    Some(s)
}

fn read_keyword_text(
    r: &mut quick_xml::reader::Reader<&[u8]>,
    buf: &mut Vec<u8>,
) -> Result<String, String> {
    use quick_xml::events::Event;
    let mut text = String::new();
    loop {
        match r.read_event_into(buf) {
            Ok(Event::Text(t)) => {
                text.push_str(&t.xml10_content().unwrap_or_default());
            }
            Ok(Event::CData(t)) => {
                text.push_str(&String::from_utf8_lossy(t.as_ref()));
            }
            Ok(Event::End(_)) | Ok(Event::Eof) => break,
            Err(e) => return Err(e.to_string()),
            _ => {}
        }
        buf.clear();
    }
    Ok(text)
}

fn kw_name_from(e: &quick_xml::events::BytesStart<'_>) -> String {
    let mut kw_name = String::new();
    for a in e.attributes().flatten() {
        if a.key.as_ref() == b"name" {
            kw_name = attr(&a);
        }
    }
    kw_name
}

fn parse_user_lang_attrs(e: &quick_xml::events::BytesStart<'_>) -> Option<UdlLang> {
    let mut name = String::new();
    let mut ext = String::new();
    let mut udl_version = String::from("2.1");
    let mut dark_mode_theme = false;
    for a in e.attributes().flatten() {
        match a.key.as_ref() {
            b"name" => name = attr(&a),
            b"ext" => ext = attr(&a),
            b"udlVersion" => udl_version = attr(&a),
            b"darkModeTheme" => dark_mode_theme = parse_yes_no(&attr(&a)),
            _ => {}
        }
    }
    if name.is_empty() {
        return None;
    }
    Some(UdlLang {
        key: udl_slug(&name),
        name,
        ext,
        udl_version,
        dark_mode_theme,
        settings: UdlSettings::default(),
        keyword_lists: empty_keyword_lists(),
        styles: Vec::new(),
    })
}

fn apply_global(u: &mut UdlLang, e: &quick_xml::events::BytesStart<'_>) {
    for a in e.attributes().flatten() {
        let v = attr(&a);
        match a.key.as_ref() {
            b"caseIgnored" => u.settings.case_ignored = parse_yes_no(&v),
            b"allowFoldOfComments" => u.settings.allow_fold_of_comments = parse_yes_no(&v),
            b"foldCompact" => u.settings.fold_compact = parse_yes_no(&v),
            b"forcePureLC" => u.settings.force_pure_lc = parse_u8_attr(&v, 0),
            b"decimalSeparator" => u.settings.decimal_separator = parse_u8_attr(&v, 0),
            _ => {}
        }
    }
}

fn apply_prefix(u: &mut UdlLang, e: &quick_xml::events::BytesStart<'_>) {
    for a in e.attributes().flatten() {
        let key = a.key.as_ref();
        if let Some(rest) = key.strip_prefix(b"Keywords") {
            if let Ok(idx_s) = std::str::from_utf8(rest) {
                if let Ok(n) = idx_s.parse::<usize>() {
                    if (1..=8).contains(&n) {
                        u.settings.prefix[n - 1] = parse_yes_no(&attr(&a));
                    }
                }
            }
        }
    }
}

/// Parse a Notepad++ `.udl.xml` / `userDefineLang.xml` into full UDL v2.1 models.
pub fn parse_udl(path: &Path) -> Result<Vec<UdlLang>, String> {
    use quick_xml::events::Event;
    use quick_xml::reader::Reader;

    let xml = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut r = Reader::from_str(&xml);
    r.config_mut().trim_text(true);
    let mut out = Vec::new();
    let mut cur: Option<UdlLang> = None;
    let mut buf = Vec::new();
    loop {
        match r.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => match e.name().as_ref() {
                b"UserLang" => {
                    if let Some(u) = parse_user_lang_attrs(&e) {
                        cur = Some(u);
                    }
                }
                b"Global" => {
                    if let Some(u) = cur.as_mut() {
                        apply_global(u, &e);
                    }
                }
                b"Prefix" => {
                    if let Some(u) = cur.as_mut() {
                        apply_prefix(u, &e);
                    }
                }
                b"Keywords" => {
                    let kw_name = kw_name_from(&e);
                    let text = read_keyword_text(&mut r, &mut buf)?;
                    if let Some(u) = cur.as_mut() {
                        if !kw_name.is_empty() {
                            u.keyword_lists.insert(kw_name, text);
                        }
                    }
                }
                b"WordsStyle" => {
                    if let Some(style) = read_words_style(&e) {
                        if let Some(u) = cur.as_mut() {
                            u.styles.push(style);
                        }
                    }
                }
                _ => {}
            },
            Ok(Event::Empty(e)) => match e.name().as_ref() {
                b"UserLang" => {
                    if let Some(u) = parse_user_lang_attrs(&e) {
                        out.push(u);
                    }
                }
                b"Global" => {
                    if let Some(u) = cur.as_mut() {
                        apply_global(u, &e);
                    }
                }
                b"Prefix" => {
                    if let Some(u) = cur.as_mut() {
                        apply_prefix(u, &e);
                    }
                }
                b"Keywords" => {
                    let kw_name = kw_name_from(&e);
                    if let Some(u) = cur.as_mut() {
                        if !kw_name.is_empty() {
                            u.keyword_lists.entry(kw_name).or_default();
                        }
                    }
                }
                b"WordsStyle" => {
                    if let Some(style) = read_words_style(&e) {
                        if let Some(u) = cur.as_mut() {
                            u.styles.push(style);
                        }
                    }
                }
                _ => {}
            },
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

/// Write UDL languages matching `insertUserLang2Tree` shape in Parameters.cpp.
pub fn write_udl(path: &Path, langs: &[UdlLang]) -> Result<(), String> {
    let mut s = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n");
    for lang in langs {
        s.push_str("<UserLang name=\"");
        s.push_str(&xml_escape(&lang.name));
        s.push_str("\" ext=\"");
        s.push_str(&xml_escape(&lang.ext));
        s.push('"');
        if lang.dark_mode_theme {
            s.push_str(" darkModeTheme=\"yes\"");
        }
        let ver = if lang.udl_version.is_empty() {
            "2.1"
        } else {
            &lang.udl_version
        };
        s.push_str(" udlVersion=\"");
        s.push_str(&xml_escape(ver));
        s.push_str("\">\n");

        s.push_str("<Settings>\n<Global caseIgnored=\"");
        s.push_str(yes_no(lang.settings.case_ignored));
        s.push_str("\" allowFoldOfComments=\"");
        s.push_str(yes_no(lang.settings.allow_fold_of_comments));
        s.push_str("\" foldCompact=\"");
        s.push_str(yes_no(lang.settings.fold_compact));
        s.push_str("\" forcePureLC=\"");
        s.push_str(&lang.settings.force_pure_lc.to_string());
        s.push_str("\" decimalSeparator=\"");
        s.push_str(&lang.settings.decimal_separator.to_string());
        s.push_str("\" />\n<Prefix");
        for i in 0..8 {
            s.push_str(&format!(
                " Keywords{}=\"{}\"",
                i + 1,
                yes_no(lang.settings.prefix[i])
            ));
        }
        s.push_str(" />\n</Settings>\n<KeywordLists>\n");

        for &name in &UDL_KEYWORD_LIST_NAMES {
            let text = lang
                .keyword_lists
                .get(name)
                .map(String::as_str)
                .unwrap_or("");
            s.push_str("<Keywords name=\"");
            s.push_str(&xml_escape(name));
            s.push_str("\">");
            s.push_str(&xml_escape(text));
            s.push_str("</Keywords>\n");
        }

        s.push_str("</KeywordLists>\n<Styles>\n");
        for style in &lang.styles {
            if style.name.is_empty() {
                continue;
            }
            s.push_str("<WordsStyle name=\"");
            s.push_str(&xml_escape(&style.name));
            s.push_str("\" fgColor=\"");
            s.push_str(&xml_escape(&style.fg_color));
            s.push_str("\" bgColor=\"");
            s.push_str(&xml_escape(&style.bg_color));
            s.push('"');
            if style.color_style != UDL_COLORSTYLE_ALL {
                s.push_str(" colorStyle=\"");
                s.push_str(&style.color_style.to_string());
                s.push('"');
            }
            if !style.font_name.is_empty() {
                s.push_str(" fontName=\"");
                s.push_str(&xml_escape(&style.font_name));
                s.push('"');
            }
            s.push_str(" fontStyle=\"");
            s.push_str(&style.font_style.to_string());
            s.push('"');
            if !style.font_size.is_empty() {
                s.push_str(" fontSize=\"");
                s.push_str(&xml_escape(&style.font_size));
                s.push('"');
            }
            s.push_str(" nesting=\"");
            s.push_str(&style.nesting.to_string());
            s.push_str("\" />\n");
        }
        s.push_str("</Styles>\n</UserLang>\n");
    }
    s.push_str("</NotepadPlus>\n");
    std::fs::write(path, s).map_err(|e| e.to_string())
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
        let p = if p.exists() {
            p
        } else {
            PathBuf::from(
                "/Users/mitra/Projects/notepad-plus-plus/PowerEditor/bin/userDefineLangs/markdown._preinstalled.udl.xml",
            )
        };
        if !p.exists() {
            return;
        }
        let langs = parse_udl(&p).unwrap();
        assert!(!langs.is_empty());
        let md = &langs[0];
        assert!(md.name.contains("Markdown"));
        assert!(md.settings.case_ignored);
        assert!(md.settings.prefix[0]);
        assert!(md.keyword_lists.contains_key("Comments"));
        assert!(md.keyword_lists.contains_key("Delimiters"));
        assert!(md.keyword_lists.contains_key("Keywords1"));
        let delim4 = md
            .styles
            .iter()
            .find(|s| s.name == "DELIMITERS4")
            .expect("DELIMITERS4");
        assert_eq!(delim4.nesting, 65600);

        let dir = std::env::temp_dir().join("nppmac-udl-roundtrip");
        let _ = std::fs::create_dir_all(&dir);
        let out = dir.join("markdown.roundtrip.udl.xml");
        write_udl(&out, &langs).unwrap();
        let again = parse_udl(&out).unwrap();
        assert_eq!(again.len(), langs.len());
        assert_eq!(again[0].name, md.name);
        assert_eq!(again[0].key, md.key);
        assert_eq!(again[0].ext, md.ext);
        assert_eq!(again[0].udl_version, md.udl_version);
        assert_eq!(again[0].settings, md.settings);
        assert_eq!(again[0].keyword_lists, md.keyword_lists);
        assert_eq!(again[0].styles, md.styles);
        let _ = std::fs::remove_file(&out);
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
