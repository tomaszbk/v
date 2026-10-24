# Parsing

Main-module functions cannot be named `dump`, `sizeof`, `typeof`, or `isreftype`.
These names have builtin syntax, so the compiler reports a redefinition error at the function
declaration. Methods, C declarations, and qualified functions in other modules can use these names.

Compiled `$vml` lowers a document generically: each tag names a props type (`Slider` is
`ui2.SliderProps`, `pkg.Gauge` is `pkg.GaugeProps`) that V type-checks at the VML location, and
the document returns a `ui2.Element`. Lists and bare calls in a property are helper values of the
property's namespace (`style: [font_size(18)]` is `ui2.style_compose(ui2.style_font_size(18))`).
See [VML structure](../../../doc/vml_structure.md) for the language; widgets, their properties
and helper namespaces are documented with ui2.

`compiled_vml_import_candidates(source, directory)` returns ordered candidate paths for each
VML import directive. Cache consumers follow the selected files transitively and track earlier
missing candidates. The helper shares directive parsing and path resolution with VML lowering.

Parenthesized expressions may span lines, including a line break before the closing `)`.
Line comments in a multiline condition preserve its grouping and any following `&&` or `||`.

A struct initializer may put its opening `{` on the next line after the type name,
including qualified names and generic types. An explicit `;` still ends the preceding statement.

`Parser.preload_source(path, source)` supplies a source snapshot for subsequent parsing and
sibling declaration scans. `clear_preloaded_sources()` restores disk reads for those paths.
Parallel prepasses and full parses use the same preloaded text, including empty sources.
Set `Parser.keep_source_texts` to keep parsed text in `FlatAst.source_texts`, keyed by file ID,
after parser buffers are released. The checker can index import lines from these snapshots.
The compiler driver preloads module-validation reads only when the module cache is disabled;
cache-enabled builds retain disk reads so parsing and cache signatures use the existing flow.

Bare builtin compile-time flags, such as `$if windows`, retain their compile-time meaning
even when a local variable has the same name. This applies to `$if` statements and expressions.
