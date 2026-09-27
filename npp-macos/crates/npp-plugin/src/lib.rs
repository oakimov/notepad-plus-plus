//! Plugin host: `.dylib` loader, `FuncItem` registry, `NPPM_*` dispatch.
//!
//! Mirrors `PowerEditor/src/MISC/PluginsManager/PluginInterface.h` semantics
//! with opaque `u64` handles instead of Win32 `HWND`.
//! See `include/NppPluginInterface.h` and `docs/plugin-porting.md`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Opaque handle token replacing `HWND` in `NppData`.
pub type NppHandle = u64;

/// Host-side identifiers passed to `setInfo`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NppData {
    /// Main window token.
    pub npp: NppHandle,
    /// Primary editor token.
    pub editor_main: NppHandle,
    /// Secondary (split-view) editor token.
    pub editor_second: NppHandle,
}

/// Plugin menu entry, mirroring `FuncItem` (name ≤ 63 chars + NUL).
#[derive(Debug, Clone)]
pub struct FuncItem {
    /// Menu label.
    pub name: String,
    /// Command id assigned by the host.
    pub cmd_id: u32,
    /// Checked on first show.
    pub init_checked: bool,
}

/// `NPPM_*` message numbers — match `Notepad_plus_msgs.h` (`NPPMSG = 2024`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u32)]
pub enum Nppm {
    /// Active editor token (NppMac) / view index write (Win32 compat via lParam).
    GetCurrentScintilla = 2028,
    /// Active document index.
    GetCurrentDocIndex = 2047,
    /// Execute a menu command by `IDM_*` id.
    MenuCommand = 2072,
    /// Active buffer id (= doc index on NppMac).
    GetCurrentBufferId = 2084,
}

impl Nppm {
    /// Parse a raw message number into the M4 subset.
    #[must_use]
    pub fn from_raw(msg: u32) -> Option<Self> {
        match msg {
            2028 => Some(Self::GetCurrentScintilla),
            2047 => Some(Self::GetCurrentDocIndex),
            2072 => Some(Self::MenuCommand),
            2084 => Some(Self::GetCurrentBufferId),
            _ => None,
        }
    }
}

/// Scintilla-notification shim: Rust edit event translated for `beNotified`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EditNotification {
    /// Buffer id.
    pub buffer_id: u64,
    /// Start byte of the change.
    pub start: usize,
    /// Changed length in bytes.
    pub length: usize,
    /// Lines added (>0) or removed (<0).
    pub lines_added: i32,
}

/// Notification codes forwarded to `beNotified` (`NPPN_*` / `SCN_*`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u32)]
pub enum NotifyCode {
    /// Host finished startup.
    Ready = 1001,
    /// File about to close.
    FileBeforeClose = 1003,
    /// File just opened.
    FileOpened = 1004,
    /// File just closed.
    FileClosed = 1005,
    /// File about to save.
    FileBeforeSave = 1007,
    /// File just saved.
    FileSaved = 1008,
    /// Host shutting down.
    Shutdown = 1009,
    /// Buffer brought to foreground.
    BufferActivated = 1010,
    /// Text modified (`SCN_MODIFIED`).
    ScnModified = 2008,
}

/// Loaded plugin record.
#[derive(Debug)]
pub struct Plugin {
    /// Plugin display name (`getName`).
    pub name: String,
    /// Registered menu entries.
    pub funcs: Vec<FuncItem>,
    next_cmd: u32,
}

impl Plugin {
    /// Register menu entries, assigning command ids from `base`.
    #[must_use]
    pub fn new(name: String, funcs: Vec<FuncItem>, base: u32) -> Self {
        let mut p = Self {
            name,
            funcs: Vec::new(),
            next_cmd: base,
        };
        for mut f in funcs {
            f.name.truncate(63);
            f.cmd_id = p.next_cmd;
            p.next_cmd += 1;
            p.funcs.push(f);
        }
        p
    }
}

/// Plugin host: scan dir, `dlopen` entries, dispatch `NPPM_*`.
#[derive(Debug, Default)]
pub struct PluginHost {
    plugins: Vec<Plugin>,
    current_buffer: u64,
    current_editor: NppHandle,
    current_doc: u32,
}

impl PluginHost {
    /// Empty host.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Candidate `.dylib` paths under `<dir>/<Name>/<Name>.dylib`.
    #[must_use]
    pub fn scan(dir: &Path) -> Vec<PathBuf> {
        let mut out = Vec::new();
        let Ok(rd) = std::fs::read_dir(dir) else {
            return out;
        };
        for entry in rd.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy().into_owned();
            let lib = entry.path().join(format!("{name}.dylib"));
            if lib.is_file() {
                out.push(lib);
            }
        }
        out.sort();
        out
    }

    /// Probe-load a `.dylib` (checks the file exists and opens it).
    /// Full symbol binding (`setInfo`/`getName`/`getFuncsArray`) happens
    /// once a plugin links the companion header.
    pub fn probe(path: &Path) -> Result<(), String> {
        if !path.is_file() {
            return Err(format!("not found: {}", path.display()));
        }
        // SAFETY: opening a library has no Rust-level invariants; symbols
        // are only read, never executed, by probe.
        unsafe {
            libloading::Library::new(path).map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Register a plugin's menu entries (used after symbol binding).
    pub fn register(&mut self, name: String, funcs: Vec<FuncItem>) -> u32 {
        let base = 50000 + self.plugins.len() as u32 * 100;
        self.plugins.push(Plugin::new(name, funcs, base));
        base
    }

    /// Dispatch the implemented `NPPM_*` subset.
    ///
    /// `MenuCommand` returns 0 here — the Swift host executes `IDM_*` actions.
    #[must_use]
    pub fn dispatch(&self, msg: Nppm, _wparam: usize, _lparam: isize) -> isize {
        match msg {
            Nppm::GetCurrentBufferId => self.current_buffer as isize,
            Nppm::GetCurrentScintilla => self.current_editor as isize,
            Nppm::MenuCommand => 0,
            Nppm::GetCurrentDocIndex => self.current_doc as isize,
        }
    }

    /// Dispatch from a raw message number (unknown → 0).
    #[must_use]
    pub fn dispatch_raw(&self, msg: u32, wparam: usize, lparam: isize) -> isize {
        Nppm::from_raw(msg).map_or(0, |m| self.dispatch(m, wparam, lparam))
    }

    /// Update host state (called on tab switch / edit).
    pub fn set_current(&mut self, buffer: u64, editor: NppHandle, doc: u32) {
        self.current_buffer = buffer;
        self.current_editor = editor;
        self.current_doc = doc;
    }

    /// Registered plugins.
    #[must_use]
    pub fn plugins(&self) -> &[Plugin] {
        &self.plugins
    }

    /// Flattened `cmd_id -> (plugin, label)` menu map.
    #[must_use]
    pub fn menu_map(&self) -> BTreeMap<u32, (String, String)> {
        let mut m = BTreeMap::new();
        for p in &self.plugins {
            for f in &p.funcs {
                m.insert(f.cmd_id, (p.name.clone(), f.name.clone()));
            }
        }
        m
    }
}

/// Directory scanned for `<Name>/<Name>.dylib` plugins.
#[must_use]
pub fn plugins_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_owned());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("NppMac")
        .join("plugins")
}

/// First `NPPM_*` subset implemented (buffer/tab/editor/menucommand).
pub const M4_NPPM_SUBSET: &[&str] = &[
    "NPPM_GETCURRENTBUFFERID",
    "NPPM_GETCURRENTSCINTILLA",
    "NPPM_MENUCOMMAND",
    "NPPM_GETCURRENTDOCINDEX",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_assigns_ids_and_truncates() {
        let mut h = PluginHost::new();
        h.set_current(7, 1, 2);
        let base = h.register(
            "Demo".into(),
            vec![FuncItem {
                name: "x".repeat(100),
                cmd_id: 0,
                init_checked: false,
            }],
        );
        assert_eq!(h.dispatch(Nppm::GetCurrentBufferId, 0, 0), 7);
        assert_eq!(h.dispatch(Nppm::GetCurrentDocIndex, 0, 0), 2);
        assert_eq!(h.dispatch(Nppm::GetCurrentScintilla, 0, 0), 1);
        assert_eq!(h.dispatch_raw(2084, 0, 0), 7);
        assert_eq!(h.dispatch_raw(2028, 0, 0), 1);
        let m = h.menu_map();
        assert_eq!(m.len(), 1);
        assert_eq!(m[&base].0, "Demo");
        assert!(m[&base].1.len() <= 63);
    }

    #[test]
    fn nppm_numbers_match_upstream() {
        assert_eq!(Nppm::GetCurrentScintilla as u32, 2028);
        assert_eq!(Nppm::GetCurrentDocIndex as u32, 2047);
        assert_eq!(Nppm::MenuCommand as u32, 2072);
        assert_eq!(Nppm::GetCurrentBufferId as u32, 2084);
    }

    #[test]
    fn scan_finds_nested_dylib_layout() {
        let dir = std::env::temp_dir().join("nppmac-plugin-test");
        let nested = dir.join("Demo");
        let _ = std::fs::create_dir_all(&nested);
        let lib = nested.join("Demo.dylib");
        std::fs::write(&lib, b"stub").unwrap();
        let found = PluginHost::scan(&dir);
        assert_eq!(found, vec![lib]);
        // probe fails on the stub (not a real dylib) but reports cleanly
        assert!(PluginHost::probe(&found[0]).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn subset_nonempty() {
        assert!(!M4_NPPM_SUBSET.is_empty());
    }
}
