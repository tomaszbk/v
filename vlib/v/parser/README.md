# Parsing

Main-module functions cannot be named `dump`, `sizeof`, `typeof`, or `isreftype`.
These names have builtin syntax, so the compiler reports a redefinition error at the function
declaration. Methods, C declarations, and qualified functions in other modules can use these names.

Compiled `$vml` builds ui2 elements through its typed runtime API. See
[compiled VML visual primitives](../../../doc/vml-visual.md) for typography and Run inheritance,
ScaledContent, interaction patches, Flex/Grid allocation, native profiles and executable fixtures.

`compiled_vml_import_candidates(source, directory)` returns ordered candidate paths for each
VML import directive. Cache consumers follow the selected files transitively and track earlier
missing candidates. The helper shares directive parsing and path resolution with VML lowering.
