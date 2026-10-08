# Compiled VML visual primitives

`$vml('view.vml')` constructs `ui2.Element` values with the installed ui2 module.
Build the compiler and its standard library from the same revision. Layout, font
measurement, rendering, interaction patches and editor state are implemented by ui2.
VML parsing happens during compilation; the application does not interpret these files.

Use V enums (`align: .right`), quoted strings, numeric values and bool conditions.
String interpolation is explicit: `text: "Count ${app.count}"`. There is no implicit
string/number conversion. Unknown elements, properties, enum values and computed types
are errors, including invalid expressions in inactive conditional arms. Diagnostics
identify the VML file, line and column and retain the enclosing `$vml` call site.

## Typography and Run

Text controls accept the fields of `ui2.TextStyle`: `color`, `background_color`,
`font_size` (or `size`), `font_family`, `weight`, `letter_spacing`, `line_height`,
`line_height_factor`, `baseline_offset`, `tabular_figures`, `bold`, `italic`,
`underline`, `strikethrough`, `shadow`, `outline`, `vertical_align`, `link`, `align`,
`valign`, `head_indent`, `first_line_indent`, `hyphenation_factor` and `lines`.
Sizes are logical units. Device DPI and composition scaling remain separate.

`Label` accepts either `text` or `Run` children. A Run is a text segment, not an
element: it has no identity, frame or input handler. Each Run inherits omitted
typography fields from its Label. Explicit false, zero, black and an alternate
`size` spelling override the inherited value. Wrapping and mixed baselines use
ui2's rich text measurement and rendering.

```vml
Label {
    width: 240 height: 100 font_size: 18 weight: 600 lines: 4
    Run { text: "An inherited segment " }
    Run { text: "and an override" size: 12 weight: 0 bold: false baseline_offset: 3 }
}
```

## Fixed compositions

`Absolute` contains explicitly positioned children (`x`/`y`).
`ScaledContent` requires positive `content_width` and `content_height`. Its frame
is the viewport; children receive the fixed logical composition dimensions.
ui2 fits the composition with contain scaling and handles clipping, inverse input
coordinates and IME caret projection. This does not change device DPI or reflow text.

```vml
ScaledContent {
    width: 400 height: 300 content_width: 800 content_height: 400
    Absolute {
        width: 800 height: 400
        Label { x: 600 y: 300 width: 180 height: 40 text: "Fixed geometry" }
    }
}
```

## Box and interaction styles

Containers, Label, Button, Dropdown, TextInput and Spinner accept box properties.
They lower to `ui2.BoxStyle`: `background`, `radius` (or `corner_radius`),
`transparent`, `border_color`, `border_width`, per-side border widths and colors,
`border_pattern: .solid` or `.dashed`, `dash_length`, `dash_gap`, `outline_color`,
`outline_width` and `outline_offset`. Color literals use `#RRGGBB`; dynamic colors
are typed integers.

Prefix a box property with `hover_`, `focus_`, `pressed_` or `disabled_` to produce
a sparse `ui2.BoxStylePatch`. Prefix `color` for a `ui2.TextStylePatch`. Omitted
fields remain absent; explicit false, zero and black are preserved. ui2 owns state
precedence and keeps these patches from changing layout.

```vml
Button {
    text: "Save" width: 120 height: 40 radius: 8
    hover_background: "#000000" hover_color: "#ffffff"
    focus_outline_width: 2 focus_outline_color: "#2563eb"
    pressed_background: "#93c5fd"
    on_tap: app.save()
}
```

## Flex and Grid

`Flex` uses `orientation: .horizontal` or `.vertical`. `Row` and `Column` select
those orientations. Container fields include `padding`, `padding_left`, `padding_top`,
`padding_right`, `padding_bottom`, `gap`, `line_gap`, `wrap`, `justify` and `align_items`.
Children accept `flex_basis`, `flex_grow`, `flex_shrink`, `min_width`, `min_height`,
`max_width`, `max_height` and `align_self`. Enum values match `ui2.FlexJustify` and
`ui2.LayoutAlignment`. Explicit dimensions supply preferred sizes; omitted leaf
dimensions are measured by ui2. Text height is remeasured at its allocated width.
With wrapping, an omitted cross-axis dimension includes every wrapped line: a Row
measures its height and a Column measures its width, including padding and line gaps.
A positive inherited dimension remains the offered size for nested containers.

Children can read an earlier sibling's geometry and typed `computed` properties,
including ids declared in its descendants. These references are resolved in declaration
order during preferred measurement, width measurement and final allocation. A child
with explicit height keeps its preferred bindings when width measurement skips it.
References to omitted dimensions use the sibling's measured size for that phase.
Later siblings remain unavailable; final builders expose the allocated sibling scope.

Static visual trees use shared typed builders for each node and placement phase.
Repeated calls with identical offered geometry and visible references share their result
within one `$vml` construction. The next construction starts fresh. Property expressions
should read stable application state during construction; event callbacks retain the live
application capture. This bounds generated subtree copies without moving layout or text
measurement out of ui2. Runtime work also depends on the number of distinct measurement
inputs; shared builders do not promise a linear bound for arbitrary responsive expressions.

`Grid` accepts `columns` (or `cols`), `rows`, `auto_columns_min_width`, `max_columns`,
`padding` and per-side padding, `spacing` (or `spacing_x`/`spacing_y`),
`col_default_width`, `row_default_height`, `col_force_default`, `row_force_default`
and the full `ui2.GridOrientation` enum. Children accept `column_span` and `row_span`.
The compiler calls ui2's layout functions and does not reproduce their algorithms.
Structural Repeater expansion inside Flex/Grid must precede allocation. This visual
lowering rejects that combination until the structural lowering supplies its children.

## Profiles and verification

On macOS and Windows, compile visual presentation with `-d ui2_custom_rendering`.
Linux and Android use the custom renderer. Native compilation rejects ScaledContent,
Run, numeric weights, tracking, custom line heights, baseline offsets, tabular figures,
custom font families, text backgrounds and advanced text decoration, paragraph indents,
per-side border colors, border-pattern declarations, outlines and interaction patches. It reports
the declaration rather than silently dropping it. Native platform appearance is not
promised to match custom rendering.
On iOS, `ui2_custom_rendering` does not select a custom renderer: UIKit remains native,
and the same presentation diagnostics apply with or without that flag.

`examples/ui2/vml_visual` is an independent example and executable parity fixture.
With ui2 installed in the module search path:

```sh
V_MACOS_V3_NO_FALLBACK=1 ./v -new-compiler -gc boehm -d ui2_custom_rendering test \
  examples/ui2/vml_visual
V_MACOS_V3_NO_FALLBACK=1 ./v -new-compiler -gc boehm -d ui2_custom_rendering run \
  examples/ui2/vml_visual
```

The fixtures compare styles and geometry with ui2's public API and runtime conversion,
check independent layout coordinates and exercise typed actions and UTF-8 bindings.
Focused regression fixtures cover vertical wrapping, nested sibling scopes, generated
source growth and property-evaluation counts at increasing layout depths. Renderer-profile
classification tests exercise target preferences without executing foreign platforms.
`TextInput` is the current input API; choose `multiline: false` for a single-line field.
Removed controls, Rectangle, legacy layout names, `units` and `property` are rejected.
