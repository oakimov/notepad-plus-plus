//! File loading/saving: encoding detection, atomic writes, backups.
//!
//! Detection order mirrors Notepad++ behavior (`EncodingMapper.cpp` role):
//! BOM first, then explicit label, then strict-UTF-8 probe, else fallback
//! label (system ANSI ≈ windows-1252 on the Mac port).

use std::io;
use std::path::Path;
use std::time::SystemTime;

/// UTF-8 BOM stripped on load, restored per user setting on save.
pub const UTF8_BOM: [u8; 3] = [0xEF, 0xBB, 0xBF];
/// UTF-16 LE BOM.
pub const UTF16LE_BOM: [u8; 2] = [0xFF, 0xFE];
/// UTF-16 BE BOM.
pub const UTF16BE_BOM: [u8; 2] = [0xFE, 0xFF];

/// Files at or above this size open in large-file mode (head/tail preview).
pub const LARGE_FILE_BYTES: u64 = 200 * 1024 * 1024;

/// Detected or chosen text encoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Encoding {
    /// UTF-8, optionally with BOM.
    #[default]
    Utf8,
    /// UTF-8 with BOM forced on save.
    Utf8Bom,
    /// UTF-16 LE (BOM or explicit).
    Utf16Le,
    /// UTF-16 BE (BOM or explicit).
    Utf16Be,
    /// Single-byte fallback (windows-1252 labels the ANSI slot).
    Ansi,
}

impl Encoding {
    /// `encoding_rs` label for decode/encode.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Utf8 | Self::Utf8Bom => "utf-8",
            Self::Utf16Le => "utf-16le",
            Self::Utf16Be => "utf-16be",
            Self::Ansi => "windows-1252",
        }
    }
}

/// Loaded document: normalized text plus the facts the UI needs.
#[derive(Debug, Clone)]
pub struct Loaded {
    /// Text to hand the buffer (line endings still mixed; core normalizes).
    pub text: String,
    /// Detected encoding.
    pub encoding: Encoding,
    /// File had a BOM.
    pub had_bom: bool,
    /// Last-write time for external-change detection.
    pub mtime: Option<SystemTime>,
}

/// Detect encoding from raw bytes: BOM → strict UTF-8 → ANSI fallback.
/// `hint` forces a label (user-chosen Encoding menu value).
#[must_use]
pub fn detect(bytes: &[u8], hint: Option<Encoding>) -> (Encoding, bool) {
    if let Some(h) = hint {
        return (h, matches!(h, Encoding::Utf8Bom));
    }
    if bytes.starts_with(&UTF8_BOM) {
        return (Encoding::Utf8Bom, true);
    }
    if bytes.starts_with(&UTF16LE_BOM) {
        return (Encoding::Utf16Le, true);
    }
    if bytes.starts_with(&UTF16BE_BOM) {
        return (Encoding::Utf16Be, true);
    }
    if std::str::from_utf8(bytes).is_ok() {
        return (Encoding::Utf8, false);
    }
    (Encoding::Ansi, false)
}

/// Decode raw bytes per `encoding`, stripping the BOM when present.
/// encoding_rs decodes BOMs itself, so pass the full slice through and
/// strip a leading U+FEFF the decoder leaves in BOM-less mode.
#[must_use]
pub fn decode(bytes: &[u8], encoding: Encoding, _had_bom: bool) -> String {
    let enc = match encoding {
        Encoding::Utf16Le => encoding_rs::UTF_16LE,
        Encoding::Utf16Be => encoding_rs::UTF_16BE,
        Encoding::Ansi => encoding_rs::WINDOWS_1252,
        Encoding::Utf8 | Encoding::Utf8Bom => encoding_rs::UTF_8,
    };
    let (s, _, _) = enc.decode(bytes);
    s.strip_prefix('\u{FEFF}').unwrap_or(&s).to_owned()
}

/// Read a file: detect, decode, stat mtime.
pub fn load(path: &Path, hint: Option<Encoding>) -> io::Result<Loaded> {
    let bytes = std::fs::read(path)?;
    let (encoding, had_bom) = detect(&bytes, hint);
    let text = decode(&bytes, encoding, had_bom);
    let mtime = std::fs::metadata(path)?.modified().ok();
    Ok(Loaded {
        text,
        encoding,
        had_bom,
        mtime,
    })
}

/// Back-compat M1 API: `(text, had_bom)` with auto-detect.
pub fn load_text(path: &Path) -> io::Result<(String, bool)> {
    load(path, None).map(|l| (l.text, l.had_bom))
}

/// Encode text for saving. UTF-16 always carries its BOM (like NPP);
/// UTF-8 carries it only when `with_bom`.
#[must_use]
pub fn encode(text: &str, encoding: Encoding, with_bom: bool) -> Vec<u8> {
    let need_bom = with_bom || matches!(encoding, Encoding::Utf16Le | Encoding::Utf16Be);
    let enc = match encoding {
        Encoding::Utf16Le => encoding_rs::UTF_16LE,
        Encoding::Utf16Be => encoding_rs::UTF_16BE,
        Encoding::Ansi => encoding_rs::WINDOWS_1252,
        Encoding::Utf8 | Encoding::Utf8Bom => encoding_rs::UTF_8,
    };
    let text: &str = if need_bom {
        // encoding_rs emits the BOM when the input starts with U+FEFF.
        &format!("\u{FEFF}{text}")
    } else {
        text
    };
    let (bytes, _, _) = enc.encode(text);
    bytes.into_owned()
}

/// Atomic save: write temp file in the same directory, then rename.
pub fn save(path: &Path, text: &str, encoding: Encoding, with_bom: bool) -> io::Result<()> {
    let tmp = path.with_extension("nppmac-tmp");
    std::fs::write(&tmp, encode(text, encoding, with_bom))?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Back-compat M1 UTF-8 atomic save.
pub fn save_text_atomic(path: &Path, text: &str, with_bom: bool) -> io::Result<()> {
    save(
        path,
        text,
        if with_bom { Encoding::Utf8Bom } else { Encoding::Utf8 },
        with_bom,
    )
}

/// Copy `path` to `path.bak` (simple session backup).
pub fn backup(path: &Path) -> io::Result<std::path::PathBuf> {
    let bak = path.with_extension("bak");
    std::fs::copy(path, &bak)?;
    Ok(bak)
}

/// Whether the file on disk changed since `mtime` (external modification).
pub fn changed_on_disk(path: &Path, mtime: Option<SystemTime>) -> bool {
    match (std::fs::metadata(path).and_then(|m| m.modified()), mtime) {
        (Ok(now), Some(prev)) => now > prev,
        _ => false,
    }
}

/// Head/tail preview for large files without loading all bytes.
pub fn preview(path: &Path, head: usize, tail: usize) -> io::Result<(Vec<u8>, Vec<u8>, u64)> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(path)?;
    let len = f.metadata()?.len();
    let mut h = vec![0u8; head.min(len as usize)];
    f.read_exact(&mut h)?;
    let mut t = vec![0u8; tail.min(len as usize)];
    if (t.len() as u64) < len {
        f.seek(SeekFrom::Start(len - t.len() as u64))?;
        f.read_exact(&mut t)?;
    } else {
        t = h.clone();
    }
    Ok((h, t, len))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bom_and_utf16_detect() {
        let (e, b) = detect(b"\xEF\xBB\xBFhi", None);
        assert_eq!((e, b), (Encoding::Utf8Bom, true));
        let (e, _) = detect(b"\xFF\xFEh\x00", None);
        assert_eq!(e, Encoding::Utf16Le);
        let (e, _) = detect(b"\xFE\xFF\x00h", None);
        assert_eq!(e, Encoding::Utf16Be);
    }

    #[test]
    fn utf8_vs_ansi_probe() {
        assert_eq!(detect("héllo 世界".as_bytes(), None).0, Encoding::Utf8);
        assert_eq!(detect(b"\xff\xfe\x00bad", None).0, Encoding::Utf16Le);
        assert_eq!(detect(b"\xe9\x28invalid", None).0, Encoding::Ansi);
    }

    #[test]
    fn round_trip_encodings() {
        let dir = std::env::temp_dir().join("nppmac-fs-test");
        let _ = std::fs::create_dir_all(&dir);
        for (enc, bom) in [
            (Encoding::Utf8, false),
            (Encoding::Utf8Bom, true),
            (Encoding::Ansi, false),
        ] {
            let path = dir.join(format!("t-{}-{}.txt", enc.label(), bom));
            save(&path, "héllo\n", enc, bom).unwrap();
            let l = load(&path, None).unwrap();
            assert_eq!(l.text, "héllo\n");
            let _ = std::fs::remove_file(&path);
        }
        let p16 = dir.join("t16.txt");
        save(&p16, "hi ✓\n", Encoding::Utf16Le, true).unwrap();
        let l = load(&p16, None).unwrap();
        assert_eq!(l.text, "hi ✓\n");
        assert!(!changed_on_disk(&p16, l.mtime));
        let _ = std::fs::remove_file(&p16);
    }
}
