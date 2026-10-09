# Compiled VML structure

`$vml('screen.vml')` parses a file at compile time and lowers it to the public ui2 API.
The usual result is `ui2.Element`; a `Menu` or `MenuBar` root returns `[]ui2.Menu`.
Import ui2 and provide a mutable `app` parameter when a document reads or writes its model:

```v ignore
fn build(mut app App) ui2.Element {
    return $vml('screen.vml')
}
```

Use `ui2.run_compiled_vml` with this builder to give callbacks access to the live model.
The compiler emits typed callbacks, ordinary V expressions and API declarations. ui2 owns
rendering, editing, event delivery and retained interaction state.

## File imports

```text
import Card
View {
    Card { id: first }
    Card { id: second }
}
```

`Card` resolves to `Card.vml` or `card.vml` beside the importing file. The imported file must
start with `module Card`. Imports in that file resolve relative to its own directory. Missing
files, duplicate directives, mismatched modules and import cycles are errors.

An import reuses a tree. Properties on its invocation override root properties; passed children
are appended. Each invocation has a stable namespace for its internal control ids. This is tree
reuse only; it introduces no private model, component state, slots or lifecycle.

## Repeaters

```text
View {
    Repeater {
        model: app.rows
        key: item.id
        Button { id: select text: item.name on_tap: app.select(item.id) }
    }
}
```

Model paths expose public fields, matching ui2 model schemas. The model is a V array, including
arrays of structs, pointers or interfaces. `item` and `index`
are scoped to its body. V checks item fields, action signatures and inactive expression branches
even when the array is empty. Keys are scalar values and must be nonempty and unique per repeater.
Choose a business identity that survives reorder; an index cannot provide that guarantee.

Repeated controls get ids derived from their source position and encoded key segments. Descendant
ids retain the enclosing repeat identity. Nested repeaters encode each key independently, so
separators in business keys cannot merge identities. An explicit element `key` remains its sibling
key; otherwise a single child uses the repeater key and multiple children add a source-child suffix.
ui2 validates duplicate ids and sibling keys before the generated builder returns its tree.

Stable ids and keys let ui2 retain focus, local edits, selection, scroll and IME across unrelated
updates and reorder. The lowering does not add reconciliation or reset editor state.

## Actions and assignments

```text
TextInput { multiline: false
    id: message
    bind.text: app.message
    on_change: app.copied = app.message
}
Button { text: "Increment" on_tap: app.count = app.count + 1 }
Button { text: "Select" on_tap: app.select(item.id) }
```

Bindings and assignments target public mutable top-level app fields. Assignments are supported
only in event properties. Bindings write the event payload before the action or assignment runs.
An assignment reads the live app at invocation time and captures repeater-local values from its
own row. It is an ordinary typed V assignment followed by ui2 refresh invalidation.

App action methods must be public and have one of these signatures: no arguments, one `int`, or
one `string`, returning nothing. Arguments are checked by V and evaluated at event time after the
binding write, including compound expressions such as `app.count + item.id`. Row/local values
are captured when building that row; app reads use the live borrowed model. An explicit V
callback can also be referenced by name or a callback field. Bindings write and request refresh
before forwarding the original event once; a nil callback still allows the binding write.
Scroll events require `on_scroll`; named `on_tap` callbacks keep pointer/gesture fallbacks.
A control id identifies its source; it does not select a
handler. Use `on_change` for text changes; obsolete `on_text` is rejected. Inline blocks,
increments and component handlers belong to later compiler work.

## Menus

A `MenuItem` child of an element lowers to `ui2.MenuEntry`, with its own typed `on_select` callback.
`Option` children of a dropdown lower to entries with their displayed text as identity.
Application menus use a standalone document:

```text
MenuBar {
    Menu {
        title: "File"
        MenuItem { id: create text: "New" shortcut: "cmd+n" on_tap: app.create() }
        MenuSeparator {}
        Menu { title: "More" MenuItem { id: help text: "Help" } }
    }
}
```

Pass the returned array to `ui2.set_menu_bar`. Titles, shortcuts, checked/enabled state, separators
and nested items use `ui2.Menu` and `ui2.MenuItem`; `ui2.validate_menus` checks the result before
installation. Menu properties are validated rather than silently ignored. Empty declarations use
modern typed array initializers; populated arrays use inferred array literals.
Titles and shortcuts are strings; checked/enabled/separator flags are bool. V checks menu fields
and action expressions without implicit string/number conversion.

## Running the public fixtures

`examples/vml_structure` provides import, nested-list, menu, assignment and event-parity fixtures.
It requires a matching ui2 checkout exposing the typed callback API. Set an isolated module path:

```sh
V_MACOS_V3_NO_FALLBACK=1 ./v -new-compiler -gc boehm -nocache \
  -path '@vlib:/path/to/modules:@vmodules' -o /tmp/vml_structure examples/vml_structure
/tmp/vml_structure
V_MACOS_V3_NO_FALLBACK=1 ./v -new-compiler -gc boehm -nocache \
  -path '@vlib:/path/to/modules:@vmodules' test examples/vml_structure
V_MACOS_V3_NO_FALLBACK=1 ./v -new-compiler -gc boehm -nocache \
  -path '@vlib:/path/to/modules:@vmodules' -d ui2_custom_rendering \
  -o /tmp/vml_structure_custom examples/vml_structure
/tmp/vml_structure_custom --window
```

Here `/path/to/modules/ui2` is the ui2 checkout. The fixtures compare supported output and events
with the existing runtime API, and verify identity stability after reorder. Compiler/parser tests
also run without installing ui2. Generated diagnostics identify the originating VML file and line,
including imported declarations, and retain the `$vml` call site.
