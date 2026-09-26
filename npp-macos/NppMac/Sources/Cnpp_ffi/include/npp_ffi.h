#ifndef NPP_FFI_H
#define NPP_FFI_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque engine handle (main-thread only).
typedef struct NppEngine NppEngine;

/// Highlight token scope (mirrors npp_highlight::Scope).
typedef enum NppScope {
    NPP_SCOPE_DEFAULT = 0,
    NPP_SCOPE_KEYWORD = 1,
    NPP_SCOPE_TYPE = 2,
    NPP_SCOPE_STRING = 3,
    NPP_SCOPE_COMMENT = 4,
    NPP_SCOPE_NUMBER = 5,
    NPP_SCOPE_OPERATOR = 6,
    NPP_SCOPE_FUNCTION = 7,
    NPP_SCOPE_PREPROC = 8,
} NppScope;

typedef struct NppToken {
    uint32_t start;
    uint32_t end;
    NppScope scope;
} NppToken;

/// Encoding label for UI / save (mirrors npp_fs::Encoding).
typedef enum NppEncoding {
    NPP_ENC_UTF8 = 0,
    NPP_ENC_UTF8_BOM = 1,
    NPP_ENC_UTF16LE = 2,
    NPP_ENC_UTF16BE = 3,
    NPP_ENC_ANSI = 4,
} NppEncoding;

NppEngine *npp_engine_create(void);
/// Like npp_engine_create; loads keywords from `langs_model` (NULL ⇒ in-repo fallback).
NppEngine *npp_engine_create_with_langs(const char *langs_model);
void npp_engine_destroy(NppEngine *engine);

/// Free a string returned by this API.
void npp_string_free(char *s);

int32_t npp_doc_count(const NppEngine *engine);
int32_t npp_doc_selected(const NppEngine *engine);

/// Create a new empty document; returns index or -1.
int32_t npp_doc_new(NppEngine *engine);

/// Open path (UTF-8). Returns index or -1 on failure.
int32_t npp_doc_open(NppEngine *engine, const char *path);

/// Close document at index. Returns false if index invalid.
bool npp_doc_close(NppEngine *engine, int32_t index);

bool npp_doc_select(NppEngine *engine, int32_t index);

/// Reorder tabs: move from -> to.
bool npp_doc_move(NppEngine *engine, int32_t from, int32_t to);

/// Heap UTF-8 string; caller frees with npp_string_free. NULL on bad index.
char *npp_doc_title(const NppEngine *engine, int32_t index);
char *npp_doc_path(const NppEngine *engine, int32_t index);
char *npp_doc_text(const NppEngine *engine, int32_t index);
char *npp_doc_language(const NppEngine *engine, int32_t index);
bool npp_doc_set_language(NppEngine *engine, int32_t index, const char *lang);

bool npp_doc_is_dirty(const NppEngine *engine, int32_t index);
NppEncoding npp_doc_encoding(const NppEngine *engine, int32_t index);
bool npp_doc_set_encoding(NppEngine *engine, int32_t index, NppEncoding enc);

/// Line ending for UI / save (0=CRLF, 1=LF, 2=CR).
typedef enum NppEol {
    NPP_EOL_CRLF = 0,
    NPP_EOL_LF = 1,
    NPP_EOL_CR = 2,
} NppEol;

NppEol npp_doc_eol(const NppEngine *engine, int32_t index);
bool npp_doc_set_eol(NppEngine *engine, int32_t index, NppEol eol);

/// Replace full document text (marks dirty when changed).
bool npp_doc_set_text(NppEngine *engine, int32_t index, const char *text);

/// Save to existing path or `path` if provided. path may be NULL to use stored path.
/// Returns false on error; optional err_out receives malloc'd message.
bool npp_doc_save(NppEngine *engine, int32_t index, const char *path, char **err_out);

void npp_doc_mark_saved(NppEngine *engine, int32_t index, const char *title, const char *path);

/// Language menu catalog (from langs.model.xml).
int32_t npp_lang_count(const NppEngine *engine);
char *npp_lang_name(const NppEngine *engine, int32_t index);
char *npp_lang_display_name(const NppEngine *engine, int32_t index);
char *npp_lang_display_name_for(const char *lang);

/// Load a User-Defined Language `.udl.xml` (keyword highlight only).
/// Returns count of languages registered, or -1 on error.
int32_t npp_udl_load(NppEngine *engine, const char *path, char **err_out);

/// Guess language from path extension (static fallback map).
char *npp_language_for_path(const char *path);
/// Guess language using the engine's XML-backed extension map.
char *npp_language_for_path_ex(const NppEngine *engine, const char *path);

/// RGB hex (`RRGGBB`) foreground for scope under lang (from stylers.model.xml).
char *npp_scope_fg(const NppEngine *engine, const char *lang, uint32_t scope);

/// Load theme / stylers XML (replaces colors). Optional err_out.
bool npp_stylers_load(NppEngine *engine, const char *path, char **err_out);
/// Theme DEFAULT fg/bg (`RRGGBB`); empty string if unset.
char *npp_editor_fg(const NppEngine *engine);
char *npp_editor_bg(const NppEngine *engine);

/// Highlight `text` for `lang`. Allocates *out_tokens; free with npp_tokens_free.
/// Returns token count (0 on empty / failure).
int32_t npp_highlight(NppEngine *engine, const char *lang, const char *text,
                      NppToken **out_tokens);
void npp_tokens_free(NppToken *tokens, int32_t count);

/// Byte-offset match range (UTF-8).
typedef struct NppMatch {
    uint32_t start;
    uint32_t end;
} NppMatch;

/// Find all matches. Allocates *out_matches; free with npp_matches_free.
/// Returns count, or -1 on invalid regex (optional err_out).
int32_t npp_find_all(const char *text, const char *pattern,
                     bool match_case, bool whole_word, bool regex,
                     NppMatch **out_matches, char **err_out);
void npp_matches_free(NppMatch *matches, int32_t count);

/// Count matches (−1 on regex error).
int32_t npp_find_count(const char *text, const char *pattern,
                       bool match_case, bool whole_word, bool regex, char **err_out);

/// Replace all; writes new UTF-8 text to *out_text (caller frees). Returns replacement count (−1 on error).
int32_t npp_replace_all(const char *text, const char *pattern, const char *replacement,
                        bool match_case, bool whole_word, bool regex,
                        char **out_text, char **err_out);

#ifdef __cplusplus
}
#endif

#endif /* NPP_FFI_H */
