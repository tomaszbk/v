# Compiled VML components and structure

`$vml('screen.vml')` parses a document at compile time and lowers it to ui2's
public V API. Visual documents return `ui2.Element`; standalone `Menu` or
`MenuBar` documents return `[]ui2.Menu`. Import ui2 in the calling V file.
`$vml('screen.vml', frame)` accepts an explicit `ui2.Rect`; the default follows
the window's logical viewport.

```v ignore
fn build(mut app App) ui2.Element {
    return $vml('screen.vml')
}
```

`app` always refers to the calling application's live instance, including
services and ordinary V methods. The generated callbacks borrow that instance.
Each retained callback captures the signals, geometry and functions its body
uses. Compiled documents support builds with V's `-W` flag.
Use `ui2.run_compiled_vml` with the builder and the application's pointer. ui2
creates the retained document once and updates affected properties and keyed
child groups. Parsing, expression evaluation and layout are not interpreted at
runtime; ui2 owns signals, lifecycle, layout, rendering and editor state.

## Component declarations

Each component lives in a `.vml` file. Import names resolve to `Name.vml` or
`name.vml` relative to the importing document. Missing files, mismatched
component names and import cycles are diagnosed at the source location.

```text
component Counter(title string = "Count", changed event(value int)) {
    state count := 0
    computed doubled := count * 2
    fn increment() { count++; changed(count) }
    Column(spacing: 12) {
        Label(text: title)
        Label(text: doubled)
        Button(text: "Add", on_tap: increment)
    }
}
```

```text
import Counter
Row {
    Counter(title: "First", on_changed: app.observe)
    Counter(title: "Second")
}
```

Inputs are typed and read-only. An input without a default is required. Private
`state` infers its V type and initializes once per instance. `computed` infers
its type and is a pure lazy memo; it cannot assign state, emit an event or call
an action. Both Counter instances have independent state and lifecycle.

Members and local element ids use unprefixed names. `app` is reserved, and
collisions between inputs, state, computed values, functions, refs, ids and
function parameters are errors. Output events validate their payload even
without a listener. A listener must return void and accept either no arguments
or exactly the declared payload types.

## Writable connections and actions

A signature can declare a bindable input, for example `bind name string = ""`.
`Editor(bind.name: app.name)` connects it to a writable source. Passing an
ordinary value keeps the input read-only. Editable local copies use `state`.

```text
component Editor(bind name string = "", changed event(value string)) {
    Column {
        TextInput(bind.text: name, on_change: changed(name))
        Button(on_tap: { name = ""; changed(name) }, text: "Clear")
    }
}
```

`text: value` reads; `bind.text: value` also writes. Display text accepts strings
and numbers, with numbers formatted using `.str()`. Editing text remains string
only: numeric conversion must be explicit. Checkbox/switch bindings require
bool, and slider bindings require a numeric source. App binding targets must
be public mutable top-level fields.

Local `fn` declarations, callback references, short actions and inline blocks
share ordinary V expression types. Built-in element callback references accept
`fn ()` or `fn (ui2.ElementEvent)` returning void. Method calls validate their
argument count and types. The binding commits the event payload before an
explicit action runs; actions batch signal writes. Event ids do not choose
handlers, and unrelated event kinds do not invoke a binding.

`mount { ... }`, `unmount { ... }` and `cleanup { ... }` register instance hooks.
Mount runs once when attached; removal disposes owned effects and descendants.
Unmount and cleanup can read the instance's existing state and memos. Callbacks
from disposed instances are ignored. Lifecycle-owned tasks use ui2's component
runtime API.

## Slots and typed refs

Declare slots in the public signature, such as `content slot` or `header slot`.
Ordinary invocation content supplies the default slot; `Slot(name: "header")`
selects named content. Slot expressions retain the author's lexical signals
and app, while their resource lifetime belongs to the receiving instance.

```text
component Panel(header slot, content slot) {
    Column {
        Slot(name: "header")
        Slot {}
    }
}
```

`ref name_field TextInput` declares a typed ref; `TextInput(ref: name_field)`
connects it to that exact control kind. Refs become available after mount and
expire on disposal. They expose typed runtime operations such as
`name_field.focus()!` and `name_field.set_text("ready")!`. Refs are excluded
from binding and snapshot data. `TextInput` and `TextArea` are distinct types.

An invocation such as `Card(id: "card", key: "item", ref: card_ref)` aliases the
component's real root. `card.width` and the other geometry members read that
root's reactive frame; geometry used as a layout input requires `Absolute`.
The invocation key applies to the root, and a typed ref must match its control
kind. The root keeps its private authored id and namespace; neither its other
ids nor its private members become visible to the caller. Anonymous roots keep
an empty public id. A component whose root uses `x` or `y` requires an
`Absolute` parent at its invocation; imported definitions retain this requirement.

## Keyed child groups

```text
Column {
    Label(text: "Rows")
    Repeater(model: app.rows, key: item.id) {
        Button(text: item.name, on_tap: app.select(item.id))
    }
    Label(text: "End")
}
```

A model is a V array. `item` and `index` belong to each keyed instance; V checks
item fields and inactive expressions even for an empty array. Keys must be
nonempty and unique in a repeater. Use a business identity that survives
reorder. Each item can produce multiple roots, nested child groups and
components. Static siblings keep their declaration order.

ui2 reuses keyed nodes during reorder, updates item/index signals, creates only
insertions and disposes removals. Local ids are namespaced by component and
keyed instance; anonymous declarations keep an empty public id and use private
retained identity. Explicit ids and keys remain validated. Focus, selection,
scroll, IME and unchanged local edit buffers survive unrelated updates.

## Menus and diagnostics

```text
MenuBar {
    Menu(title: "File") {
        MenuItem(id: "create", text: "New", shortcut: "cmd+n", on_tap: app.create)
        MenuSeparator()
    }
}
```

Pass the result to `ui2.set_menu_bar`. Nested items use typed `ui2.Menu` and
`ui2.MenuItem` declarations and validate before installation. Named arguments
are the only property syntax; ids and ordinary strings require quotes. VML enum
arguments use bare names, for example `align: right`. Conditions require bool;
other than display text, properties have no implicit string/number conversion.

Diagnostics report the originating VML file, line and column and retain the
calling `$vml` location. Native profiles reject unsupported custom presentation
properties instead of silently changing their meaning. Parser tests do not
require an installed ui2 module; runtime acceptance uses a matching compiler
and ui2 revision, for example `-path '/path/to/modules|@vlib|@vmodules'` with
`/path/to/modules/ui2` pointing to the checkout.
