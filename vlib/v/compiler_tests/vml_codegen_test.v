import os

const vml_codegen_vexe = @VEXE
const vml_codegen_tests_dir = os.dir(@FILE)
const vml_codegen_v3_dir = os.dir(vml_codegen_tests_dir)
const vml_codegen_vlib_dir = os.dir(vml_codegen_v3_dir)

fn vml_codegen_mock_ui2() string {
	return (os.read_file(@FILE) or { panic(err) }).all_after('/* MOCK_UI2\n').all_before('\nMOCK_UI2 */')
}

// vml_codegen_project creates a project whose `ui2` module is the mock below.
fn vml_codegen_project(name string) string {
	root := os.join_path(os.vtmp_dir(), 'vml_codegen_${name}_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'ui2', 'core')) or { panic(err) }
	os.write_file(os.join_path(root, 'v.mod'), "Module { name: 'vml_codegen' }\n") or { panic(err) }
	os.write_file(os.join_path(root, 'ui2', 'v.mod'), "Module { name: 'ui2', subdirs: ['core'] }\n") or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'ui2', 'core', 'ui2.v'), vml_codegen_mock_ui2()) or {
		panic(err)
	}
	return root
}

// vml_codegen_compile builds `root/name.v` with the flat compiler and the mock ui2.
fn vml_codegen_compile(root string, name string, mode []string) os.Result {
	mut args := [vml_codegen_vexe, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', root + '|' + vml_codegen_vlib_dir]
	args << mode
	args << os.join_path(root, name + '.v')
	return os.exec(args)
}

// vml_codegen_run writes a document and the program that lowers it, then returns
// what the program printed after building and driving the retained tree.
fn vml_codegen_run(root string, name string, document string, source string) string {
	os.write_file(os.join_path(root, name + '.vml'), document) or { panic(err) }
	os.write_file(os.join_path(root, name + '.v'), source) or { panic(err) }
	bin := os.join_path(root, name)
	compile := vml_codegen_compile(root, name, ['-b', 'c', '-o', bin])
	assert compile.exit_code == 0, compile.output
	assert !compile.output.contains('C compilation failed'), compile.output
	run := os.exec([bin])
	assert run.exit_code == 0, run.output
	return run.output.trim_space()
}

fn test_vml_lowers_to_retained_ui2_nodes() {
	root := vml_codegen_project('lowering')
	defer {
		os.rmdir_all(root) or {}
	}
	// Keyed repeater items, typed widget configs, two-way bindings and style
	// patches, with callbacks that mutate the application model.
	form := vml_codegen_run(root, 'form', r'Screen(id: "root") {
    Repeater(model: app.items, key: item.id) {
        Label(text: "${item.name}:${index}", on_click: app.select(item.id))
    }
    ProgressBar(value: 25, max: 50)
    Slider(id: "volume", bind.value: app.level, min: 0, max: 100, step: 0.5, on_change: app.select(4))
    Switch(id: "notifications", bind.active: app.enabled, on_active: app.select(5))
    Spinner(id: "location", bind.text: app.location, on_change: app.choose("Work")) {
        Option(text: "Home")
        Option(text: "Work")
    }
    Checkbox(text: "Ready", checked: true)
    View(style: [border_width(2), border_right(4)])
    Button(text: "Select", on_click: app.select(app.selected + 10))
}',
		r"module main

import ui2

struct Item {
pub:
	id   int
	name string
}

struct App {
pub:
	items []Item
pub mut:
	selected int
	level    f64
	enabled  bool
	location string
}

pub fn (mut app App) select(id int) {
	app.selected = id
}

pub fn (mut app App) choose(value string) {
	app.location = value
}

fn (mut app App) private_action() {
	app.selected = -1
}

fn build(mut app App) ui2.Element {
	return $vml('form.vml')
}

fn main() {
	mut app := App{items: [Item{id: 7, name: 'a'}, Item{id: 8, name: 'b'}], level: 12.5, location: 'Home'}
	root := build(mut app)
	c := root.children
	println('${c.len} ${c[0].text}/${c[0].key} ${c[1].text}/${c[1].key}')
	c[1].on_event(ui2.ElementEvent{kind: .click})
	println('select ${app.selected}')
	println('${c[2].accessibility_role} ${c[2].value}/${c[2].max_value}')
	c[3].on_event(ui2.ElementEvent{kind: .change, value: 40})
	println('${c[3].kind} ${c[3].id} ${c[3].value}:${c[3].min_value}:${c[3].max_value}:${c[3].step} level=${app.level} select=${app.selected}')
	c[4].on_event(ui2.ElementEvent{kind: .change, checked: true})
	println('${c[4].kind} ${c[4].checked} enabled=${app.enabled} select=${app.selected}')
	c[5].on_event(ui2.ElementEvent{kind: .change, text: 'Elsewhere'})
	println('${c[5].kind} ${c[5].text} ${c[5].accessibility_value} location=${app.location}')
	println('${c[6].kind} ${c[6].text} ${c[6].checked}')
	println('${c[7].kind} ${c[7].box.border_left}:${c[7].box.border_right}')
	c[8].on_event(ui2.ElementEvent{kind: .click})
	c[8].on_event(ui2.ElementEvent{kind: .change})
	println('${c[8].kind} ${c[8].text} select=${app.selected}')
}
")
	assert form == '9 a:0/7 b:1/8\nselect 8\nprogressbar 25.0/50.0\nslider volume 12.5:0.0:100.0:0.5 level=40.0 select=4\nswitch_control false enabled=true select=5\ndropdown Home Home|Work location=Work\ncheckbox Ready true\nview 2.0:4.0\nbutton Select select=15', form
	// Component inputs, state, computed values, arithmetic display coercions
	// and action blocks that write component state.
	review := vml_codegen_run(root, 'review', r'component Review(half f64 = 50, custom_selected int = 1) {
    state quarter := 25.0
    state picks := 0
    computed doubled := quarter * 2
    Column(id: "review_root", width: half, spacing: 2, style: [background(#ff0000)]) {
        Label(text: 1 + 2)
        Label(text: app.count + 1)
        Label(text: "count:${app.count}")
        Label(text: app.display_name())
        Button(text: "Pick", on_click: app.select(custom_selected))
        View(width: app.content_width(), style: [background(#00ff00)])
        Label(text: 4 - 1)
        Label(text: 3 * 4)
        Label(text: 8 / 2)
        Label(text: 7 % 4)
        Button(on_click: { picks = picks + 1; app.select(picks - 10) })
        Label(text: app.ready && app.enabled ? "both" : "not both")
        Label(text: doubled)
    }
}
Review(custom_selected: 3)',
		r"module main

import ui2

struct App {
pub:
	count   int
	ready   bool
	enabled bool
pub mut:
	selected int
}

pub fn (mut app App) select(value int) {
	app.selected = value
}

pub fn (app &App) display_name() string {
	return 'display:${app.count}'
}

pub fn (app &App) content_width() int {
	return 88
}

fn build(mut app App) ui2.Element {
	return $vml('review.vml')
}

fn main() {
	mut app := App{count: 2, ready: true}
	root := build(mut app)
	c := root.children
	println('${root.id} ${root.frame.width} ${root.box.bg:06x} ${root.layout.orientation} gap=${root.layout.gap} ${c.len}')
	println(c.map(it.text).join('|'))
	c[4].on_event(ui2.ElementEvent{kind: .click})
	println('select=${app.selected} ${c[5].frame.width}:${c[5].box.bg:06x}')
	c[10].on_event(ui2.ElementEvent{kind: .click})
	print('select=${app.selected} ')
	c[10].on_event(ui2.ElementEvent{kind: .click})
	println('select=${app.selected}')
}
")
	assert review == 'review_root 50.0 ff0000 vertical gap=2.0 13\n3|3|count:2|display:2|Pick||3|12|4|3||not both|50.0\nselect=3 88.0:00ff00\nselect=-9 select=-8', review
	// Nested repeaters scope their item keys by the enclosing key.
	nested := vml_codegen_run(root, 'nested', 'Screen {
    Repeater(model: app.rows, key: item.id) {
        Repeater(model: item.values, key: item) {
            Label(text: item)
        }
    }
}',
		r"module main

import ui2

struct Row {
pub:
	id     int
	values []int
}

struct App {
pub:
	rows []Row
}

fn build(mut app App) ui2.Element {
	return $vml('nested.vml')
}

fn main() {
	mut app := App{rows: [Row{id: 10, values: [1, 2]}, Row{id: 20, values: [3]}]}
	root := build(mut app)
	println(root.children.map('${it.key}=${it.text}').join(' '))
}
")
	assert nested == '10/1=1 10/2=2 20/3=3', nested
	// Element references read retained geometry; styles accept model colors.
	geometry := vml_codegen_run(root, 'geometry', r'Absolute {
    View(id: "box", width: 100, height: box.width, style: [background(app.theme_color())])
    Label(text: "${box.width}x${box.height}", x: box.width, y: 4)
}',
		r"module main

import ui2

struct App {}

pub fn (app &App) theme_color() u32 {
	return u32(0x112233)
}

fn build(mut app App) ui2.Element {
	return $vml('geometry.vml')
}

fn main() {
	mut app := App{}
	root := build(mut app)
	c := root.children
	println('${c[0].id} ${c[0].frame.width}x${c[0].frame.height} ${c[0].box.bg:06x}')
	println('${c[1].text} ${c[1].frame.x}:${c[1].frame.y}')
}
")
	assert geometry == 'box 100.0x100.0 112233\n100.0x100.0 100.0:4.0', geometry
	// Interpolation escapes, single-quoted strings and text input events.
	expressions := vml_codegen_run(root, 'expressions', 'Screen {
    Repeater(model: app.values, key: item) {
        Label(text: item - 1)
    }
    Label(text: "\${app.label(\\"}\\")}")
    Label(text: \'It\\\'s "ready"\', tooltip: \'line one\\nline two\')
    Label(text: "\${app.label(\'}\')}")
    TextInput(id: "message", on_change: app.choose("Typed"))
}',
		r"module main

import ui2

struct App {
pub:
	values []int
pub mut:
	typed string
}

pub fn (app &App) label(value string) string {
	return '<${value}>'
}

pub fn (mut app App) choose(value string) {
	app.typed = value
}

fn build(mut app App) ui2.Element {
	return $vml('expressions.vml')
}

fn main() {
	mut app := App{values: [10, 20]}
	root := build(mut app)
	c := root.children
	for child in c[..c.len - 1] {
		println('${child.kind} ${child.key} text=${child.text} tooltip=${child.tooltip}')
	}
	input := c[c.len - 1]
	input.on_event(ui2.ElementEvent{kind: .change, text: 'x'})
	println('${input.kind} ${input.id} typed=${app.typed}')
}
")
	assert expressions == 'label 10 text=9 tooltip=\nlabel 20 text=19 tooltip=\nlabel  text=<}> tooltip=\nlabel  text=It\'s "ready" tooltip=line one\nline two\nlabel  text=<}> tooltip=\ntext_field message typed=Typed', expressions
	// MenuBar documents lower to typed ui2.Menu values.
	menus := vml_codegen_run(root, 'menus', 'MenuBar {
    Menu(title: "File") {
        MenuItem(text: "New", shortcut: "cmd+n", checked: false, enabled: true, on_click: app.count = 1)
        MenuSeparator()
    }
}',
		r"module main

import ui2

struct App {
pub mut:
	count int
}

fn build(mut app App) []ui2.Menu {
	return $vml('menus.vml')
}

fn main() {
	mut app := App{}
	menus := build(mut app)
	for menu in menus {
		println('${menu.title}: ' + menu.items.map('${it.title}[${it.shortcut}|${it.checked}|${it.enabled}|${it.separator}]').join(' '))
	}
	menus[0].items[0].on_select(ui2.ElementEvent{kind: .click})
	println('count=${app.count}')
}
")
	assert menus == 'File: New[cmd+n|false|true|false] [|false|true|true]\ncount=1', menus
	// Generated code is type-checked against the application model.
	for document, expected in {
		'Screen { View { Button(on_click: app.missing()) } }':                   'missing'
		'Screen { Button { MenuItem(text: "Open", on_click: app.missing()) } }': 'missing'
		'Screen { Button(on_click: app.private_action()) }':                     'must be public'
	} {
		os.write_file(os.join_path(root, 'form.vml'), document) or { panic(err) }
		invalid := vml_codegen_compile(root, 'form', ['-b', 'c', '-o', os.join_path(root, 'form')])
		assert invalid.exit_code != 0, invalid.output
		assert invalid.output.contains(expected), invalid.output
		assert invalid.output.contains('form.vml:1:'), invalid.output
	}
}

/* MOCK_UI2
module ui2

// A minimal stand-in for ui2's compiled VML runtime: the same public names and
// signatures the lowering emits, with eager semantics (effects and structure
// updates run once, keyed lists build every item when bound, layout returns the
// declared tree) so tests can type-check and run lowered documents.

pub enum Kind { screen view label image button checkbox dropdown text_field text_area scroll slider switch_control }
pub enum Align { left center right }
pub enum VAlign { top middle bottom }
pub enum Orientation { horizontal vertical }
pub enum LayoutOrientation { horizontal vertical }
pub enum LayoutAlignment { auto start center end stretch }
pub enum FlexJustify { start center end space_between }
pub enum ElementEventKind { click change submit scroll pointer_down pointer_drag pointer_up long_press swipe_left link }

pub struct Rect { pub: x f64 y f64 width f64 height f64 }
pub struct LayoutSize { pub: width f64 height f64 }
pub struct LayoutPadding { pub: left f64 top f64 right f64 bottom f64 }
pub struct LayoutSpec { pub: orientation LayoutOrientation gap f64 }
pub struct BoxStyle { pub: bg u32 = 0xffffff radius f64 transparent bool border_color u32 border_left f64 border_top f64 border_right f64 border_bottom f64 }
pub struct BoxStylePatch { pub: bg ?u32 radius ?f64 transparent ?bool border_color ?u32 border_left ?f64 border_top ?f64 border_right ?f64 border_bottom ?f64 }
pub struct TextStylePatch { pub: color ?u32 }
pub struct InteractionStyle { pub: hover BoxStylePatch focus BoxStylePatch pressed BoxStylePatch disabled BoxStylePatch hover_text TextStylePatch focus_text TextStylePatch pressed_text TextStylePatch disabled_text TextStylePatch }
pub struct TextStyle { pub: color u32 = 0x111111 background_color u32 size f64 = 15 font_family string weight int bold bool italic bool underline bool strikethrough bool align Align valign VAlign = .middle lines int = 1 }
pub struct StylePatch { pub: box BoxStylePatch }
pub struct ElementEvent { pub: kind ElementEventKind id string x f64 y f64 text string value f64 checked bool target string }
pub type ElementCallback = fn (ElementEvent)
pub struct MenuEntry { pub: on_select ElementCallback = unsafe { nil } id string title string }
pub struct Menu { pub: title string items []MenuItem }
pub struct MenuItem { pub: on_select ElementCallback = unsafe { nil } id string title string shortcut string separator bool checked bool enabled bool = true items []MenuItem }
pub struct SliderStyle { pub: track_color u32 = 0xcbd5e1 value_track_color u32 = 0x93c5fd thumb_color u32 = 0x2563eb track_width f64 = 4 thumb_size f64 = 20 }
pub struct SwitchStyle { pub: inactive_track_color u32 = 0xcbd5e1 active_track_color u32 = 0x22c55e thumb_color u32 = 0xffffff disabled_track_color u32 = 0xe2e8f0 disabled_thumb_color u32 = 0xf8fafc }
pub struct ManagedScreen { pub: name string content Element }
pub struct CompiledVmlMetadata { pub: screen ?ManagedScreen }

pub struct Element {
pub:
	compiled_node         &CompiledVmlNode     = unsafe { nil }
	compiled_metadata     &CompiledVmlMetadata = unsafe { nil }
	kind                  Kind
	id                    string
	on_event              ElementCallback = unsafe { nil }
	key                   string
	text                  string
	checked               bool
	image_path            string
	tooltip               string
	placeholder           string
	frame                 Rect
	layout_input          ?Rect
	layout                LayoutSpec
	box                   BoxStyle
	interaction_style     InteractionStyle
	text_style            TextStyle
	native_style          bool
	keyboard              int
	long_press            bool
	swipe_left            bool
	readonly              bool
	disable_scroll        bool
	secure                bool
	clickable             bool
	button_behavior       bool
	draggable             bool
	opacity               f64 = 1
	rotation              f64
	translate_x           f64
	translate_y           f64
	scale_x               f64 = 1
	scale_y               f64 = 1
	origin_x              f64
	origin_y              f64
	cursor                string
	menu                  []MenuEntry
	children              []Element
	hidden                bool
	enabled               bool = true
	accessibility_role    string
	accessibility_label   string
	accessibility_value   string
	autocorrect           bool = true
	padding_left          f64  = 12
	value                 f64
	min_value             f64
	max_value             f64 = 100
	step                  f64
	orientation           Orientation
	padding               f64 = 16
	value_track           bool
	slider_style          SliderStyle
	switch_style          SwitchStyle
}

pub fn (element Element) with_layout_frame(frame Rect) Element {
	return Element{ ...element, frame: frame, layout_input: frame }
}

pub fn rect(x f64, y f64, width f64, height f64) Rect { return Rect{x, y, width, height} }
pub fn vml_bounds() Rect { return Rect{width: 800, height: 600} }
pub fn request_refresh() {}
pub fn validate_element_tree(root Element) ! { _ = root }
pub fn validate_menus(menus []Menu) ! { _ = menus }
pub fn menu_separator() MenuItem { return MenuItem{separator: true} }

pub fn vml_display_text[T](value T) string {
	$if T is string {
		return value
	} $else $if T is $int || T is $float {
		return value.str()
	} $else {
		$compile_error('VML text requires a string or number')
	}
}

pub fn vml_binding_number[T](current T, value f64) T {
	_ = current
	$if T is $int || T is $float {
		return T(value)
	} $else {
		$compile_error('VML numeric binding requires a numeric writable source')
	}
}

// Styles: only box patches are modeled.
pub fn compose_styles(styles []StylePatch) StylePatch {
	mut box := BoxStylePatch{}
	for style in styles {
		patch := style.box
		box = BoxStylePatch{
			bg:            if v := patch.bg { ?u32(v) } else { box.bg }
			radius:        if v := patch.radius { ?f64(v) } else { box.radius }
			border_left:   if v := patch.border_left { ?f64(v) } else { box.border_left }
			border_top:    if v := patch.border_top { ?f64(v) } else { box.border_top }
			border_right:  if v := patch.border_right { ?f64(v) } else { box.border_right }
			border_bottom: if v := patch.border_bottom { ?f64(v) } else { box.border_bottom }
		}
	}
	return StylePatch{box: box}
}
pub fn style_background(color u32) StylePatch { return StylePatch{box: BoxStylePatch{bg: color}} }
pub fn style_radius(radius f64) StylePatch { return StylePatch{box: BoxStylePatch{radius: radius}} }
pub fn style_border_width(width f64) StylePatch { return StylePatch{box: BoxStylePatch{border_left: width, border_top: width, border_right: width, border_bottom: width}} }
pub fn style_border_right(width f64) StylePatch { return StylePatch{box: BoxStylePatch{border_right: width}} }

// Widget constructors.
pub struct ProgressBarConfig { pub: id string frame Rect value f64 max f64 = 100 background u32 = 0xe2e8f0 color u32 = 0x3b82f6 radius f64 = 4 }
pub fn progress_bar(config ProgressBarConfig) Element { return Element{kind: .view, id: config.id, frame: config.frame, value: config.value, max_value: config.max, accessibility_role: 'progressbar', accessibility_value: '${config.value} of ${config.max}'} }
pub struct SliderConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect min f64 max f64 = 100 value f64 step f64 orientation Orientation padding f64 = 16 value_track bool style SliderStyle }
pub fn slider(config SliderConfig) Element { return Element{kind: .slider, id: config.id, on_event: config.on_event, frame: config.frame, value: config.value, min_value: config.min, max_value: config.max, step: config.step, orientation: config.orientation, padding: config.padding, value_track: config.value_track, slider_style: config.style, accessibility_role: 'slider'} }
pub struct SwitchConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect active bool style SwitchStyle }
pub fn switch_control(config SwitchConfig) Element { return Element{kind: .switch_control, id: config.id, on_event: config.on_event, frame: config.frame, checked: config.active, switch_style: config.style, accessibility_role: 'switch'} }
pub struct SpinnerConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect text string values []string text_autoupdate bool box BoxStyle text_style TextStyle }
pub fn spinner(config SpinnerConfig) Element { return Element{kind: .dropdown, id: config.id, on_event: config.on_event, frame: config.frame, text: config.text, box: config.box, text_style: config.text_style, accessibility_role: 'combobox', accessibility_value: config.values.join('|')} }
pub struct TextInputConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect text string placeholder string password bool readonly bool enabled bool = true autocorrect bool = true keyboard int padding_left f64 = 12 box BoxStyle text_style TextStyle }
pub fn text_input(config TextInputConfig) !Element { return Element{kind: .text_field, id: config.id, on_event: config.on_event, frame: config.frame, text: config.text, placeholder: config.placeholder, secure: config.password, readonly: config.readonly, box: config.box, text_style: config.text_style} }

// Layout: children are positioned by the authored frames only.
pub struct FlexChild { pub: element Element basis f64 = -1 grow f64 shrink f64 = 1 minimum_width f64 minimum_height f64 maximum_width f64 = -1 maximum_height f64 = -1 align_self LayoutAlignment = .auto }
pub struct GridSpan { pub: column_span int = 1 row_span int = 1 }
pub struct VmlChildLayout { pub: flex FlexChild grid GridSpan }
pub struct FlexConfig { pub: id string frame Rect box BoxStyle orientation LayoutOrientation padding LayoutPadding gap f64 line_gap f64 = -1 wrap bool justify FlexJustify align LayoutAlignment = .stretch children []FlexChild }
pub fn flex(config FlexConfig) !Element { return Element{kind: .view, id: config.id, frame: config.frame, box: config.box, layout: LayoutSpec{orientation: config.orientation, gap: config.gap}, children: config.children.map(it.element)} }
pub struct LayoutConstraints { pub: min_width f64 min_height f64 max_width f64 = -1 max_height f64 = -1 }
pub struct LayoutEnvironment { pub: version u64 font_version u64 scale f64 = 1 }
pub fn measure_layout_text(text string, style TextStyle, width f64) LayoutSize { return LayoutSize{width: text.len * style.size / 2, height: style.size} }
pub struct LayoutTree { mut: root Element }
pub fn (mut tree LayoutTree) replace(root Element) ! { tree.root = root }
pub fn (mut tree LayoutTree) resolve(constraints LayoutConstraints, measure fn (string, TextStyle, f64) LayoutSize, environment LayoutEnvironment) !Element {
	_ = constraints
	_ = measure
	_ = environment
	return tree.root
}

// Reactive values recompute on every read.
@[heap]
pub struct Signal[T] { mut: value T }
pub fn (mut signal Signal[T]) get() !T { return signal.value }
pub fn (signal &Signal[T]) peek() !T { return signal.value }
pub fn (mut signal Signal[T]) set(value T) !bool {
	signal.value = value
	return true
}
@[heap]
pub struct Memo[T] { compute fn () !T = unsafe { nil } }
pub fn (mut memo Memo[T]) get() !T { return memo.compute()! }

pub struct VmlDocumentConfig {}
@[params]
pub struct VmlNodeConfig { pub: identity string authored_width bool authored_height bool inherit_width bool inherit_height bool }
@[params]
pub struct VmlSourceLocation { pub: source string line int column int }

@[heap]
pub struct SignalEffect {}
@[heap]
pub struct SignalScope {}
pub fn (mut scope SignalScope) effect(name string, run fn () !) !&SignalEffect {
	_ = name
	run()!
	return &SignalEffect{}
}

@[heap]
pub struct CompiledVmlComponent {
pub:
	scope &SignalScope = &SignalScope{}
	name  string
mut:
	values map[string]voidptr
}

pub fn new_vml_document(name string, config VmlDocumentConfig) !&CompiledVmlComponent {
	_ = config
	return &CompiledVmlComponent{name: name}
}
pub fn (mut component CompiledVmlComponent) child(name string) !&CompiledVmlComponent { return &CompiledVmlComponent{name: component.name + '/' + name} }
pub fn (author &CompiledVmlComponent) slot_child(mut host CompiledVmlComponent, name string) !&CompiledVmlComponent { return &CompiledVmlComponent{name: host.name + '/' + name} }
pub fn (component &CompiledVmlComponent) control_id(authored_id string) string { return authored_id }
pub fn (component &CompiledVmlComponent) watch_app() ! {}
pub fn (mut component CompiledVmlComponent) state[T](name string, initial T) !&Signal[T] {
	if existing := component.values[name] {
		return unsafe { &Signal[T](existing) }
	}
	signal := &Signal[T]{value: initial}
	component.values[name] = voidptr(signal)
	return signal
}
pub fn (mut component CompiledVmlComponent) state_factory[T](name string, initialize fn () !T) !&Signal[T] { return component.state[T](name, initialize()!) }
pub fn (mut component CompiledVmlComponent) computed[T](name string, compute fn () !T) !&Memo[T] {
	_ = name
	return &Memo[T]{compute: compute}
}
pub fn (mut component CompiledVmlComponent) geometry(id string, initial Rect) !&Signal[Rect] { return component.state[Rect]('@geometry:' + id, initial) }
pub fn (component &CompiledVmlComponent) callback(action fn (ElementEvent) !) ElementCallback {
	return fn [action] (event ElementEvent) {
		action(event) or { panic(err) }
	}
}
pub fn (mut component CompiledVmlComponent) on_mount(name string, action fn () !) ! { action()! }
pub fn (mut component CompiledVmlComponent) on_unmount(name string, action fn ()) ! { _ = action }
pub fn (mut component CompiledVmlComponent) on_cleanup(name string, cleanup fn ()) ! { _ = cleanup }
pub fn (mut component CompiledVmlComponent) element(declaration Element, config VmlNodeConfig) !&CompiledVmlNode {
	mut node := &CompiledVmlNode{component: component, declaration: declaration}
	node.set_element_children(declaration.children)!
	return node
}
pub fn (mut component CompiledVmlComponent) fragment(identity string) !&CompiledVmlNode {
	_ = identity
	return &CompiledVmlNode{component: component, fragment: true}
}

struct VmlChildSegment {
	name string
mut:
	nodes []&CompiledVmlNode
}

@[heap]
pub struct CompiledVmlNode {
	component &CompiledVmlComponent = unsafe { nil }
	fragment  bool
mut:
	declaration Element
	children    []&CompiledVmlNode
	segments    []VmlChildSegment
}

fn (node &CompiledVmlNode) presented() []Element {
	if !node.fragment { return [node.element()] }
	mut result := []Element{}
	for child in node.children { result << child.presented() }
	return result
}
pub fn (node &CompiledVmlNode) element() Element {
	mut children := []Element{}
	for child in node.children { children << child.presented() }
	return Element{ ...node.declaration, compiled_node: unsafe { node }, children: children }
}
pub fn (mut node CompiledVmlNode) set_element_children(declarations []Element) ! {
	mut children := []&CompiledVmlNode{}
	for declaration in declarations {
		if declaration.compiled_node != unsafe { nil } {
			children << declaration.compiled_node
		} else {
			children << node.component.element(declaration)!
		}
	}
	node.children = children
}
pub fn (mut node CompiledVmlNode) set_segment(name string, nodes []&CompiledVmlNode) ! {
	mut found := false
	for mut segment in node.segments {
		if segment.name == name {
			segment.nodes = nodes.clone()
			found = true
		}
	}
	if !found { node.segments << VmlChildSegment{name: name, nodes: nodes.clone()} }
	mut children := []&CompiledVmlNode{}
	for segment in node.segments { children << segment.nodes }
	node.children = children
}
// prefix_key scopes the keys of presented elements by their enclosing list key.
fn (mut node CompiledVmlNode) prefix_key(key string) {
	if node.fragment {
		for mut child in node.children { child.prefix_key(key) }
		return
	}
	scoped := if node.declaration.key == '' { key } else { key + '/' + node.declaration.key }
	node.declaration = Element{ ...node.declaration, key: scoped }
}
pub fn (mut node CompiledVmlNode) set_child_layout(rule VmlChildLayout) ! { _ = rule }
pub fn (node &CompiledVmlNode) frame() !Rect { return node.declaration.frame }
pub fn (mut node CompiledVmlNode) follow_viewport(width bool, height bool) {}
pub fn (mut node CompiledVmlNode) structure(name string, update fn () !Element) ! { node.declaration = update()! }
pub fn (mut node CompiledVmlNode) effect(property string, update fn (Element) !Element) ! { node.declaration = update(node.element())! }
pub fn (mut node CompiledVmlNode) style(compute fn () !StylePatch) ! {
	patch := compute()!.box
	box := node.declaration.box
	node.declaration = Element{
		...node.declaration
		box: BoxStyle{
			...box
			bg:            patch.bg or { box.bg }
			radius:        patch.radius or { box.radius }
			border_left:   patch.border_left or { box.border_left }
			border_top:    patch.border_top or { box.border_top }
			border_right:  patch.border_right or { box.border_right }
			border_bottom: patch.border_bottom or { box.border_bottom }
		}
	}
}

@[heap]
pub struct VmlKeyedList[T] {
	parent  &CompiledVmlNode = unsafe { nil }
	key     fn (T) string    = unsafe { nil }
	build   fn (mut CompiledVmlComponent, &Signal[T]) ![]&CompiledVmlNode = unsafe { nil }
	segment string
}

pub fn new_vml_keyed_list[T](mut parent CompiledVmlNode, name string, key fn (T) string, build fn (mut CompiledVmlComponent, &Signal[T]) ![]&CompiledVmlNode) !&VmlKeyedList[T] {
	parent.set_segment('list:' + name, []&CompiledVmlNode{})!
	return &VmlKeyedList[T]{parent: &parent, key: key, build: build, segment: 'list:' + name}
}
pub fn (mut list VmlKeyedList[T]) bind(source fn () ![]T, location VmlSourceLocation) ! {
	items := source()!
	mut nodes := []&CompiledVmlNode{}
	mut keys := map[string]bool{}
	for index, item in items {
		key := list.key(item)
		if key in keys { return error('${location.source}:${location.line}:${location.column}: duplicate compiled VML list key `${key}`') }
		keys[key] = true
		mut owner := list.parent.component.child('item:' + key)!
		// Seed the index before building: the mock evaluates effects only once.
		owner.state('@index', index)!
		item_nodes := list.build(mut owner, &Signal[T]{value: item})!
		for item_node in item_nodes {
			mut keyed := unsafe { item_node }
			keyed.prefix_key(key)
			nodes << keyed
		}
	}
	mut parent := unsafe { list.parent }
	parent.set_segment(list.segment, nodes)!
}
MOCK_UI2 */

fn test_vml_structure_checks_empty_lists_branches_actions_and_import_locations() {
	root := vml_codegen_project('structure')
	defer {
		os.rmdir_all(root) or {}
	}
	main_path := os.join_path(root, 'main.v')
	os.write_file(main_path, "module main
import ui2
struct Item {
 secret string
pub:
 id int
 name string
}
struct App {
 private_value int
pub:
 items []Item
 readonly int
pub mut:
 count int
 text string
}
pub fn (mut app App) unsupported(value bool) { _ = value }
pub fn (mut app App) select(value int) { app.count = value }
fn build(mut app App) ui2.Element { return \$vml('main.vml') }
fn main() { mut app := App{items: [Item{id: 3}]}; _ = build(mut app) }
")!
	os.write_file(os.join_path(root, 'main.vml'), 'import Content\nView { Content {} }')!
	import_path := os.join_path(root, 'content.vml')
	// Each body sits on line 3 of the imported component.
	for body in [
		'Repeater(model: app.items, key: item.id) { Label(text: item.missing) }',
		'Repeater(model: app.items, key: item.id) { Label(text: item.secret) }',
		'Label(text: app.private_value)',
		'Label(text: "\${app.private_value}")',
		'Label(text: true ? "ok" : app.missing)',
		'Label(text: app.items)',
		'Repeater(model: app.count, key: item) { Label(text: "bad") }',
		'Repeater(model: app.items, key: item.missing) { Label(text: "bad") }',
		'Button(on_click: app.readonly = 1)',
		'Button(on_click: app.count = "wrong")',
		'Slider(bind.value: app.items)',
		'TextInput(on_text: app.select(1))',
		'TextField(text: "removed")',
		'Button(on_click: app.unsupported(1))',
		'Button(on_click: app.select("wrong"))',
		'Button(on_click: app.select(app.count ? 1 : 2))',
		'Button(on_click: app.select(app.count == "7" ? 1 : 2))',
		'Button(on_click: app.select(false || app.count == "7" ? 1 : 2))',
		'Button(on_click: app.select(app.text + "bad"))',
		'Button { MenuItem(text: app.items) }',
		'Repeater(model: app.items, key: item.id) { Button(on_click: app.select(item.missing)) }',
	] {
		os.write_file(import_path, 'component Content() {\n    View {\n        ${body}\n    }\n}\n')!
		result := vml_codegen_compile(root, 'main', ['-check'])
		assert result.exit_code != 0, body + '\n' + result.output
		assert result.output.contains('content.vml:3:'), result.output
		assert !result.output.contains('<veb-template>:'), result.output
	}
	os.write_file(import_path, 'component Content() {\n    View {\n        Repeater(model: app.items, key: item.id) { Button(on_click: app.count = item.id) }\n    }\n}\n')!
	valid := os.exec([@VEXE, '-nocache', '-path', root + '|' + vml_codegen_vlib_dir, '-o',
		os.join_path(root, 'valid'), main_path])
	assert valid.exit_code == 0, valid.output
	run := os.exec([os.join_path(root, 'valid')])
	assert run.exit_code == 0, run.output
	// Menu properties use V's string/bool slots rather than display coercions.
	main_source := os.read_file(main_path)!
	os.write_file(main_path, main_source.replace('ui2.Element', '[]ui2.Menu'))!
	for title, body in {
		'valid':    'Menu(title: "File") { MenuItem(text: "New", shortcut: "cmd+n", checked: false, enabled: true, on_click: app.count = 1) }'
		'title':    'Menu(title: app.count)'
		'shortcut': 'Menu(title: "File") { MenuItem(text: "New", shortcut: app.count) }'
		'checked':  'Menu(title: "File") { MenuItem(text: "New", checked: app.count) }'
		'enabled':  'Menu(title: "File") { MenuItem(text: "New", enabled: app.count == "7") }'
		'text':     'Menu(title: "File") { MenuItem(text: app.items) }'
	} {
		os.write_file(os.join_path(root, 'main.vml'), 'MenuBar {\n    ${body}\n}\n')!
		result := vml_codegen_compile(root, 'main', ['-check'])
		if title == 'valid' {
			assert result.exit_code == 0, result.output
		} else {
			assert result.exit_code != 0, title + '\n' + result.output
			assert result.output.contains('main.vml:2:'), result.output
		}
	}
}
