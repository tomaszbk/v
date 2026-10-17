# Parsing

Main-module functions cannot be named `dump`, `sizeof`, `typeof`, or `isreftype`.
These names have builtin syntax, so the compiler reports a redefinition error at the function
declaration. Methods, C declarations, and qualified functions in other modules can use these names.

Compiled `$vml` lowers a document generically: each tag names a props type (`Slider` is
`ui2.SliderProps`, `pkg.Gauge` is `pkg.GaugeProps`) that V type-checks at the VML location, and
the document returns a `ui2.Element`. See [VML structure](../../../doc/vml_structure.md) for the
language; widgets and their properties are documented with ui2.

`compiled_vml_import_candidates(source, directory)` returns ordered candidate paths for each
VML import directive. Cache consumers follow the selected files transitively and track earlier
missing candidates. The helper shares directive parsing and path resolution with VML lowering.

Parenthesized expressions may span lines, including a line break before the closing `)`.
Line comments in a multiline condition preserve its grouping and any following `&&` or `||`.
