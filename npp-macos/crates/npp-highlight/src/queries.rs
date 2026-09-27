//! Per-grammar tree-sitter highlight queries (predicate-free for QueryCursor).
//! Capture names are mapped by [`crate::scope_for_capture`].

/// Query source for a grammar key (`rust`, `python`, …).
#[must_use]
pub fn query_source(lang: &str) -> &'static str {
    match lang {
        "rust" => RUST,
        "python" => PYTHON,
        "javascript" => JAVASCRIPT,
        "typescript" => TYPESCRIPT,
        "go" => GO,
        "java" => JAVA,
        "ruby" => RUBY,
        "html" => HTML,
        "css" => CSS,
        "json" => JSON,
        "toml" => TOML,
        "xml" => XML,
        "yaml" => YAML,
        _ => FALLBACK,
    }
}

const FALLBACK: &str = r#"
(string) @string
(comment) @comment
"#;

const RUST: &str = r#"
(type_identifier) @type
(primitive_type) @type
(line_comment) @comment
(block_comment) @comment
(char_literal) @string
(string_literal) @string
(raw_string_literal) @string
(boolean_literal) @constant
(integer_literal) @number
(float_literal) @number
(attribute_item) @attribute
(inner_attribute_item) @attribute
(function_item name: (identifier) @function)
(function_signature_item name: (identifier) @function)
(call_expression function: (identifier) @function)
(call_expression function: (field_expression field: (field_identifier) @function))
(call_expression function: (scoped_identifier name: (identifier) @function))
(macro_invocation macro: (identifier) @function)
(crate) @keyword
(super) @keyword
(self) @keyword
(mutable_specifier) @keyword
[
  "as" "async" "await" "break" "const" "continue" "dyn" "else" "enum" "extern"
  "fn" "for" "if" "impl" "in" "let" "loop" "match" "mod" "move" "pub" "ref"
  "return" "static" "struct" "trait" "type" "union" "unsafe" "use" "where"
  "while" "yield"
] @keyword
[
  "*" "&" "+" "-" "/" "%" "=" "==" "!=" "<" ">" "<=" ">=" "&&" "||"
  "|" "^" "<<" ">>" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "->" "=>" "::"
] @operator
"#;

const PYTHON: &str = r#"
(comment) @comment
(string) @string
(integer) @number
(float) @number
(true) @constant
(false) @constant
(none) @constant
(function_definition name: (identifier) @function)
(call function: (identifier) @function)
(call function: (attribute attribute: (identifier) @function))
(type (identifier) @type)
(decorator (identifier) @function)
[
  "as" "assert" "async" "await" "break" "class" "continue" "def" "del" "elif"
  "else" "except" "finally" "for" "from" "global" "if" "import" "lambda"
  "nonlocal" "pass" "raise" "return" "try" "while" "with" "yield" "match" "case"
] @keyword
[
  "-" "+" "*" "**" "/" "//" "%" "@" "|" "&" "^" "~" "<<" ">>"
  "<" "<=" "==" "!=" ">=" ">" "<>" "=" "+=" "-=" "*=" "/=" "%="
  "and" "or" "not" "in" "is"
] @operator
"#;

const JAVASCRIPT: &str = r#"
(comment) @comment
(string) @string
(template_string) @string
(regex) @string
(number) @number
(true) @constant
(false) @constant
(null) @constant
(undefined) @constant
(function_declaration name: (identifier) @function)
(function_expression name: (identifier) @function)
(method_definition name: (property_identifier) @function)
(call_expression function: (identifier) @function)
(call_expression function: (member_expression property: (property_identifier) @function))
[
  "as" "async" "await" "break" "case" "catch" "class" "const" "continue"
  "debugger" "default" "delete" "do" "else" "export" "extends" "finally"
  "for" "from" "function" "get" "if" "import" "in" "instanceof" "let" "new"
  "of" "return" "set" "static" "switch" "throw" "try" "typeof" "var" "void"
  "while" "with" "yield"
] @keyword
[
  "+" "-" "*" "/" "%" "**" "++" "--" "<<" ">>" ">>>" "&" "|" "^" "~"
  "&&" "||" "??" "=" "+=" "-=" "*=" "/=" "%=" "**=" "<<=" ">>=" ">>>="
  "&=" "|=" "^=" "&&=" "||=" "??=" "==" "===" "!=" "!==" "<" ">" "<=" ">="
  "=>" "..."
] @operator
"#;

const TYPESCRIPT: &str = r#"
(comment) @comment
(string) @string
(template_string) @string
(number) @number
(true) @constant
(false) @constant
(null) @constant
(undefined) @constant
(type_identifier) @type
(predefined_type) @type
(function_declaration name: (identifier) @function)
(method_definition name: (property_identifier) @function)
(call_expression function: (identifier) @function)
[
  "as" "async" "await" "break" "case" "catch" "class" "const" "continue"
  "debugger" "default" "delete" "do" "else" "enum" "export" "extends"
  "finally" "for" "from" "function" "get" "if" "implements" "import" "in"
  "instanceof" "interface" "let" "new" "of" "private" "protected" "public"
  "readonly" "return" "set" "static" "switch" "throw" "try" "type" "typeof"
  "var" "void" "while" "with" "yield" "namespace" "module" "declare" "abstract"
  "override" "satisfies" "keyof" "infer" "is"
] @keyword
[
  "+" "-" "*" "/" "%" "=" "==" "===" "!=" "!==" "<" ">" "<=" ">=" "&&" "||"
  "??" "=>" "?" ":"
] @operator
"#;

const GO: &str = r#"
(comment) @comment
(interpreted_string_literal) @string
(raw_string_literal) @string
(rune_literal) @string
(int_literal) @number
(float_literal) @number
(imaginary_literal) @number
(true) @constant
(false) @constant
(nil) @constant
(type_identifier) @type
(function_declaration name: (identifier) @function)
(method_declaration name: (field_identifier) @function)
(call_expression function: (identifier) @function)
[
  "break" "case" "chan" "const" "continue" "default" "defer" "else" "fallthrough"
  "for" "func" "go" "goto" "if" "import" "interface" "map" "package" "range"
  "return" "select" "struct" "switch" "type" "var"
] @keyword
[
  "+" "-" "*" "/" "%" "++" "--" "==" "!=" "<" "<=" ">" ">=" "&&" "||" "&" "|"
  "^" "<<" ">>" "&^" "=" ":=" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "<<=" ">>="
  "<-" "..."
] @operator
"#;

const JAVA: &str = r#"
(line_comment) @comment
(block_comment) @comment
(string_literal) @string
(character_literal) @string
(decimal_integer_literal) @number
(hex_integer_literal) @number
(octal_integer_literal) @number
(binary_integer_literal) @number
(decimal_floating_point_literal) @number
(hex_floating_point_literal) @number
(true) @constant
(false) @constant
(null_literal) @constant
(type_identifier) @type
(method_declaration name: (identifier) @function)
(method_invocation name: (identifier) @function)
[
  "abstract" "assert" "break" "case" "catch" "class" "continue" "default" "do"
  "else" "enum" "extends" "final" "finally" "for" "if" "implements" "import"
  "instanceof" "interface" "native" "new" "package" "private" "protected"
  "public" "return" "static" "strictfp" "switch" "synchronized"
  "throw" "throws" "transient" "try" "volatile" "while"
] @keyword
[
  "+" "-" "*" "/" "%" "++" "--" "==" "!=" "<" ">" "<=" ">=" "&&" "||" "!" "&" "|"
  "^" "~" "<<" ">>" ">>>" "=" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "<<=" ">>="
  ">>>=" "->" "::"
] @operator
"#;

const RUBY: &str = r#"
(comment) @comment
(string) @string
(integer) @number
(float) @number
(true) @constant
(false) @constant
(nil) @constant
(method name: (identifier) @function)
(singleton_method name: (identifier) @function)
(call method: (identifier) @function)
[
  "alias" "and" "begin" "break" "case" "class" "def" "do" "else" "elsif" "end"
  "ensure" "for" "if" "in" "module" "next" "or" "rescue" "retry" "return" "then"
  "unless" "until" "when" "while" "yield"
] @keyword
[
  "+" "-" "*" "/" "%" "**" "==" "!=" "<" ">" "<=" ">=" "<=>" "&&" "||" "=" "+="
  "-=" "*=" "/=" "%=" "**=" "<<" ">>" "&" "|" "^" "~"
] @operator
"#;

const HTML: &str = r#"
(comment) @comment
(tag_name) @tag
(erroneous_end_tag_name) @tag
(doctype) @constant
(attribute_name) @attribute
(attribute_value) @string
(quoted_attribute_value) @string
[
  "<" ">" "</" "/>"
] @operator
"#;

const CSS: &str = r#"
(comment) @comment
(tag_name) @tag
(class_name) @property
(id_name) @property
(property_name) @property
(string_value) @string
(integer_value) @number
(float_value) @number
(plain_value) @string
(color_value) @number
(unit) @number
[
  "~" ">" "+" "*" "/" "=" "^=" "|=" "~=" "$=" "*="
  "and" "or" "not" "only"
] @operator
"#;

const JSON: &str = r#"
(comment) @comment
(string) @string
(number) @number
(true) @constant
(false) @constant
(null) @constant
(pair key: (string) @property)
"#;

const TOML: &str = r#"
(comment) @comment
(string) @string
(integer) @number
(float) @number
(boolean) @constant
(bare_key) @property
(quoted_key) @string
"=" @operator
"#;

const XML: &str = r#"
(Comment) @comment
(STag (Name) @tag)
(ETag (Name) @tag)
(EmptyElemTag (Name) @tag)
(Attribute (Name) @property)
(Attribute (AttValue) @string)
(EntityRef) @constant
(CharRef) @constant
"xml" @keyword
[
  "<" ">" "</" "/>" "<?" "?>"
] @operator
"#;

const YAML: &str = r#"
(comment) @comment
(string_scalar) @string
(single_quote_scalar) @string
(double_quote_scalar) @string
(integer_scalar) @number
(float_scalar) @number
(boolean_scalar) @constant
(null_scalar) @constant
(tag) @type
(block_mapping_pair key: (flow_node (plain_scalar (string_scalar) @property)))
"#;
