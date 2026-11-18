# Compiled VML visual primitives

`$vml('view.vml')` constructs `ui2.Element` values with the installed ui2 module.
Build the compiler and its standard library from the same revision. Layout, font
measurement, rendering, interaction patches and editor state are implemented by ui2.
VML parsing happens during compilation; the application does not interpret these files.

Use bare VML enum names (`text_align(right)`), quoted strings, numeric values and bool conditions.
String interpolation is explicit: `text: "Count ${app.count}"`. Display text accepts
numbers and strings; other properties have no implicit string/number conversion.
Unknown elements, properties, enum values and inferred declaration types
are errors, including invalid expressions in inactive conditional arms. Diagnostics
identify the VML file, line and column and retain the enclosing `$vml` call site.

## Typography and Run

Text controls use `style: [...]` with typed helpers: `foreground`, `text_background`,
`font_size`, `font_family`, `weight`, `letter_spacing`, `line_height`,
`line_height_factor`, `baseline_offset`, `tabular_figures`, `italic`,
`underline`, `strikethrough`, `shadow`, `text_outline`, `vertical_align`, `link`, `text_align`,
`text_valign`, `head_indent`, `first_line_indent`, `hyphenation_factor` and `lines`.
Use `weight(700)` for bold and `weight(400)` for regular text.
Sizes are logical units. Device DPI and composition scaling remain separate.

`Label` accepts either `text` or `Run` children. A Run is a text segment, not an
element: it has no identity, frame or input handler. Each Run inherits omitted
typography fields from its Label. Explicit false, zero and black
override the inherited value. Wrapping and mixed baselines use
ui2's rich text measurement and rendering.

```vml
Label(
    width: 240,
    height: 100,
    style: [font_size(18), weight(600), lines(4)],
) {
    Run(text: "An inherited segment ")
    Run(text: "and an override", style: [font_size(12), weight(400), baseline_offset(3)])
}
```

## Fixed compositions

`Absolute` contains explicitly positioned children (`x`/`y`).
`ScaledContent` requires positive `content_width` and `content_height`. Its frame
is the viewport; children receive the fixed logical composition dimensions.
ui2 fits the composition with contain scaling and handles clipping, inverse input
coordinates and IME caret projection. This does not change device DPI or reflow text.

```vml
ScaledContent(
    width: 400,
    height: 300,
    content_width: 800,
    content_height: 400,
) {
    Absolute(
        width: 800,
        height: 400,
    ) {
        Label(x: 600, y: 300, width: 180, height: 40, text: "Fixed geometry")
    }
}
```

## Overlay surfaces

`Dialog`, `Popover`, `MenuOverlay`, `ContextMenu` and `Tooltip` retain their content
and present it in ui2's window overlay layer. Their `width` and `height` describe
the surface; ui2 resolves its global position, clipping, focus and dismissal.
`MenuOverlay` is separate from the application's `Menu`/`MenuBar` declarations.
These surfaces require the custom renderer. `Popup` and `ModalView` are removed.

```vml
Dialog(
    id: "confirmation",
    width: 320,
    height: 180,
    open: app.confirm_open,
    on_dismiss: app.close_confirmation(),
) {
    Column {
        Label(text: "Save the changes?")
        Button(text: "Save", on_click: app.save())
    }
}
```

Anchored surfaces use `anchor: "control_id"` or `point: app.point` with a typed
`ui2.OverlayPoint` in window logical coordinates. `placement` uses bare enum names
such as `bottom_start`, `top_end` or `right`; `gap` and `margin` are nonnegative
logical distances. `owner` identifies the declaration owner, and `initial_focus`
selects a control inside a keyboard overlay. Dismissal requests call `on_dismiss`;
the handler updates the controlled `open` source. `dismiss_on_escape` and
`dismiss_on_outside` select which requests are enabled. `backdrop` accepts a typed
`ui2.BoxStyle`, and `backdrop_opacity` is between zero and one.

Quoted `anchor`, `owner` and `initial_focus` names resolve within the component's
namespace, including keyed repeater instances. Values supplied by V expressions
or an opaque `OverlayConfig` contain resolved control ids; V code can obtain one
with `component.control_id("local_name")`.
An overlay's quoted component invocation alias must refer to a component declared
earlier, because the invocation exposes its actual private root id. Forward
references to ordinary local controls, including `initial_focus`, remain valid.

`ContextMenu` requests opening through `on_open` after a right click on its anchor;
the event carries window logical `x`/`y` coordinates for the controlled `point`.
`Tooltip` requests opening after anchored hover or focus and requests dismissal
when that target is left. `tooltip_delay` is a nonnegative duration in seconds,
defaulting to 0.5. These callbacks update the explicit `open` source.

`View(overlay: app.config)` accepts a typed `ui2.OverlayConfig`. Overlay arguments
and authored `hidden` update one retained surface; closing and reopening preserve
its child identities. Overlay refs declare the `View` marker type.
Native-profile compilation reports unsupported overlays.

`Scroll(scroll_mode: horizontal_only)` and `Scroll(scroll_mode: both)` select scrolling
axes through the typed `ui2.ScrollMode` enum; the default is `vertical_only`.

## Box and interaction styles

Containers and controls accept box helpers through `style: [...]`.
They compose `ui2.StylePatch` values: `background`, `radius`,
`transparent`, `border_color`, `border_width`, per-side border widths and colors,
`border_pattern(solid)` or `border_pattern(dashed)`, `dash_length`, `dash_gap`, `outline_color`,
`outline_width` and `outline_offset`. Color literals use `#RRGGBB`; dynamic colors
are typed integers.

Use `hover([...])`, `focus([...])`, `pressed([...])` or `disabled([...])` to produce
a sparse interaction patch with box helpers and `foreground`. Omitted
fields remain absent; explicit false, zero and black are preserved. ui2 owns state
precedence and keeps these patches from changing layout.

```vml
Button(
    text: "Save",
    width: 120,
    height: 40,
    on_click: app.save(),
    style: [
        radius(8),
        hover([background("#000000"), foreground("#ffffff")]),
        focus([outline_width(2), outline_color("#2563eb")]),
        pressed([background("#93c5fd")]),
    ],
)
```

## Named styles, variants and theme tokens

A file or component body can declare `style name = [...]`. Names can refer to
other styles, including later declarations; duplicate names, member collisions
and cycles are errors. Lists compose in order, so the last supplied field wins.
Style values are typed `ui2.StylePatch`; a component can accept an input of that
type and application methods can return it.

```vml
style card = [background(color.surface), padding(spacing.medium), radius(radius.medium)]
style highlighted = [card, background(color.accent)]

component Card(active bool = false) {
    View(style: [active ? highlighted : card]) {
        Label(text: "Content", style: [font_size(typography.body)])
    }
}

Column(spacing: 12) { Card() Card(active: true) }
```

`color`, `spacing`, `radius` and `typography` are reserved token namespaces.
Their values read the owning component's theme signals. ui2 supplies default
tokens and inherits local theme overrides; `set_vml_theme(element, theme)` and
`CompiledVmlComponent.set_theme(theme)` update existing styled nodes. The runner's
`theme` configuration supplies startup tokens, including custom names.
Style changes update retained elements; dropping a field restores its original
unstyled value. Presentation arguments such as `background:`, `color:`,
`corner_radius:`, `bold:` and `font_size:` are rejected.

## Bindings and actions

`Checkbox(bind.checked: app.checked)` reads the application's bool reactively. Its
typed `.change` callback writes `event.checked` back to that
field, including false. An explicit `on_change` action runs after the binding, so
it observes the committed state. Action arguments written as `app.field` read the
live application field when the event is handled.

```vml
Checkbox(bind.checked: app.checked, on_change: app.changed())
```

`on_click` remains an independent tap action; it does not apply the checkbox binding.
Unrelated event kinds do not run the change binding or action. Callbacks belong to
their element declarations; an event id does not select another element's action.

## Flex and Grid

`Flex` uses `orientation: horizontal` or `vertical`. `Row` and `Column` select
those orientations. Container fields include `gap`, `line_gap`, `wrap`, `justify`
and `align_items`. Padding uses `style: [padding(...)]` or the per-side helpers
`padding_left`, `padding_top`, `padding_right` and `padding_bottom`.
Children accept `flex_basis`, `flex_grow`, `flex_shrink`, `min_width`, `min_height`,
`max_width`, `max_height` and `align_self`. Enum values match `ui2.FlexJustify` and
`ui2.LayoutAlignment`. Explicit dimensions supply preferred sizes; omitted leaf
dimensions are measured by ui2. Text height is remeasured at its allocated width.
With wrapping, an omitted cross-axis dimension includes every wrapped line: a Row
measures its height and a Column measures its width, including padding and line gaps.
A positive inherited dimension remains the offered size for nested containers.
An unconstrained main axis uses the natural dimension that the returned frame will have
when measuring wrapping. Explicit dimensions and width-pass allocations retain zero.
A padded Grid measures child heights at its chosen natural, inherited or allocated width;
invalid explicit dimensions still produce ui2 layout errors.
Grid selects its width once. A width-measurement pass uses its allocated width, even at
zero. Other preferred passes use an authored width when present, then a positive
inherited width when available.
Otherwise, ui2's first preferred measurement supplies the natural width. The second
preferred measurement uses that selected width to resolve automatic columns and the
omitted height; it does not select another width. Padding and gaps remain part of the
natural extent. For example, five 20-by-20 children offered width 300 with
`auto_columns_min_width: 100` select width 60, then measure five rows and height 100.
Authored heights and allocated frames retain their dimensions, including zero.

Children of `Absolute` can use an earlier sibling's geometry in layout inputs,
including ids declared in its descendants. Other layouts take dimensions from
application data, component inputs or state. Geometry signals expose allocated
logical frames and may be read in text, callbacks and viewport predicates.
Dependent properties react after ui2 resolves layout. Later siblings remain unavailable.
The compiler emits authored declarations and delegates measurement and final
allocation to ui2's retained `LayoutTree`. It creates each node once and
registers effects for dynamic properties. Window resize updates viewport and
geometry dependencies without recreating components.

`Grid` accepts `columns` (or `cols`), `rows`, `auto_columns_min_width`, `max_columns`,
`spacing` (or `spacing_x`/`spacing_y`),
`col_default_width`, `row_default_height`, `col_force_default`, `row_force_default`
and the full `ui2.GridOrientation` enum. Padding uses the same style helpers.
Children accept `column_span` and `row_span`.
The compiler calls ui2's layout functions and does not reproduce their algorithms.
Keyed Repeater groups flatten into the container alongside static siblings before
allocation, with each child retaining its typed layout constraints.

## Motion and presence

Elements accept `opacity` from zero to one and a typed `ui2.MotionConfig` through `motion`.
The configuration stays in ordinary V application logic and supplies enter/exit styles,
transitions, reduced motion, and an optional injectable clock. VML only lowers these values to
the retained ui2 element:

```text
View(
    motion: app.panel_motion,
    opacity: app.panel_opacity,
    hidden: !app.panel_shown,
    translate_x: app.panel_offset,
) {
    Label(text: "Panel")
}
```

Changes to these arguments patch the same retained node. `hidden` requests enter or exit;
the runtime retains an exiting element until its transition completes. Ordinary opacity and
transform arguments are the present target. The runtime owns interpolation and scheduling,
including immediate completion when reduced motion is enabled. Explicit opacity or motion
requires the custom profile and produces a diagnostic in the native profile.

## Profiles and verification

On macOS and Windows, compile visual presentation with `-d ui2_custom_rendering`.
Linux and Android use the custom renderer. Native compilation rejects ScaledContent,
Run, weights other than 400 or 700, tracking, custom line heights, baseline offsets,
tabular figures,
custom font families, text backgrounds and advanced text decoration, paragraph indents,
per-side border colors, border-pattern declarations, outlines and interaction patches. It reports
the declaration rather than silently dropping it. Native platform appearance is not
promised to match custom rendering. Native validation also checks each control's
supported fields at runtime when applying typed or dynamic style values.
On iOS, `ui2_custom_rendering` does not select a custom renderer: UIKit remains native,
and the same presentation diagnostics apply with or without that flag.

`examples/ui2/vml_visual` is an independent example and executable parity fixture.
With ui2 installed in the module search path:

```sh
V_MACOS_V3_NO_FALLBACK=1 ./v -b c -cc clang -d ui2_custom_rendering test \
  examples/ui2/vml_visual
V_MACOS_V3_NO_FALLBACK=1 ./v -b c -cc clang -d ui2_custom_rendering run \
  examples/ui2/vml_visual
```

The fixtures compare styles and geometry with ui2's public API and independent expected values,
check independent layout coordinates and exercise typed actions and UTF-8 bindings.
Focused regression fixtures cover unoffered Row/Column wrapping, padded Grid axes,
automatic columns at the selected width and its fractional thresholds,
explicit zero dimensions, nested sibling scopes, generated
source growth and property-evaluation counts at increasing layout depths. Renderer-profile
classification tests exercise target preferences without executing foreign platforms.
`TextInput` is a single-line field. Use `TextArea` for multiline and rich editing.
Removed controls, Rectangle, legacy layout names, `units` and `property` are rejected.
