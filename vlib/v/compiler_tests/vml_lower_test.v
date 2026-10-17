import os

// Tests of the generic VML lowering against a mock ui2 with the generic node
// runtime: `$vml` documents build props values that the mock turns into
// elements, so the tests check what V accepts, how it reports errors at VML
// locations, and how reactive properties, bindings and events behave.

const vml_lower_vexe = @VEXE
const vml_lower_vlib_dir = os.dir(os.dir(os.dir(@FILE)))

fn vml_lower_mock_ui2() string {
	return (os.read_file(@FILE) or { panic(err) }).all_after('/* MOCK_UI2\n').all_before('\nMOCK_UI2 */')
}

// vml_lower_project creates a project whose `ui2` module is the mock below.
fn vml_lower_project(name string) string {
	root := os.join_path(os.vtmp_dir(), 'vml_lower_${name}_${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'ui2')) or { panic(err) }
	os.write_file(os.join_path(root, 'v.mod'), "Module { name: 'vml_lower' }\n") or { panic(err) }
	os.write_file(os.join_path(root, 'ui2', 'ui2.v'), vml_lower_mock_ui2()) or { panic(err) }
	return root
}

fn vml_lower_compile(root string, name string, mode []string) os.Result {
	mut args := [vml_lower_vexe, '-gc', 'boehm', '-no-retry-compilation', '-nocache', '-path',
		root + '|' + vml_lower_vlib_dir]
	args << mode
	args << os.join_path(root, name + '.v')
	return os.exec(args)
}

// vml_lower_run writes a document and the program that lowers it, then returns
// what the program printed.
fn vml_lower_run(root string, name string, document string, source string) string {
	os.write_file(os.join_path(root, name + '.vml'), document) or { panic(err) }
	os.write_file(os.join_path(root, name + '.v'), source) or { panic(err) }
	bin := os.join_path(root, name)
	compile := vml_lower_compile(root, name, ['-o', bin])
	assert compile.exit_code == 0, compile.output
	assert !compile.output.contains('warning:'), compile.output
	run := os.exec([bin])
	assert run.exit_code == 0, run.output
	return run.output.trim_space()
}

const vml_lower_app = r"module main

import ui2

struct Item {
	secret string
pub:
	id   int
	name string
}

struct App {
	hidden int
pub:
	items []Item
	ready bool
pub mut:
	level   f64
	changes int
	log     []string
}

pub fn (mut app App) changed() {
	app.changes++
	app.log << 'changed:${app.level}'
}

pub fn (mut app App) pick(id int) {
	app.log << 'pick:${id}'
}

fn build(mut app App) ui2.Element {
	return $vml('main.vml')
}
"

fn test_vml_lower_builds_props_nodes_with_bindings_and_events() {
	root := vml_lower_project('build')
	defer {
		os.rmdir_all(root) or {}
	}
	output := vml_lower_run(root, 'main', 'Column(align_items: center, style: [background(#112233), radius(radius.md)]) {
    Slider(id: "vol", bind.value: app.level, max: 10, on_change: app.changed())
    Label(text: "Level \${app.level} of \${vol.width}", style: [font_size(18), hover([background(color.accent)])])
    Repeater(model: app.items, key: item.id) {
        Button(text: "\${index}:\${item.name}", on_click: app.pick(item.id))
    }
}',
		vml_lower_app + r"
fn show(element ui2.Element) string {
	mut parts := []string{}
	for child in element.children {
		parts << '${child.kind}#${child.id}/${child.key}=${child.text}'
	}
	return '${element.kind} ${element.align} ${element.bg:06x} r${element.radius} [${parts.join(' ')}]'
}

fn main() {
	mut app := App{items: [Item{id: 7, name: 'a'}, Item{id: 9, name: 'b'}], level: 2}
	root := build(mut app)
	println(show(root))
	// The binding writes the model back before the handler runs.
	root.children[0].on_event(ui2.ElementEvent{kind: .change, value: 4})
	root.children[3].on_event(ui2.ElementEvent{kind: .click})
	println('${app.level} ${app.changes} ${app.log}')
	println(show(build(mut app)))
}
")
	assert output == "column center 112233 r8.0 [slider#vol/=2.0 label#/=Level 2.0 of 120.0 button#/7=0:a button#/9=1:b]
4.0 1 ['changed:4.0', 'pick:9']
column center 112233 r8.0 [slider#vol/=4.0 label#/=Level 4.0 of 120.0 button#/7=0:a button#/9=1:b]", output
}

fn test_vml_lower_components_forward_properties_to_their_root() {
	root := vml_lower_project('components')
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'counter.vml'), 'component Counter(title string, picked event(id int)) {
    state clicks := 0
    computed label := "\${title}:\${clicks}"
    Column {
        Label(text: label)
        Button(text: "+", on_click: { clicks = clicks + 1; picked(clicks) })
    }
}')!
	output := vml_lower_run(root, 'main', 'import Counter
Column {
    Counter(title: "n", on_picked: app.pick(id), align_items: end)
    Repeater(model: app.items, key: item.id) {
        Label(text: "row")
    }
}', vml_lower_app +
		r"
fn main() {
	mut app := App{items: [Item{id: 1}, Item{id: 2}]}
	root := build(mut app)
	counter := root.children[0]
	println('${counter.kind} ${counter.align} ${counter.children[0].text} ${root.children.len}')
	counter.children[1].on_event(ui2.ElementEvent{kind: .click})
	counter.children[1].on_event(ui2.ElementEvent{kind: .click})
	println('${app.log}')
}
")
	assert output == "column end n:0 3\n['pick:1', 'pick:2']", output
}

// V checks tags, properties and values against the props types and reports
// the errors at the VML location of the element or property.
fn test_vml_lower_reports_type_errors_at_vml_locations() {
	root := vml_lower_project('errors')
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'main.v'), vml_lower_app + '\nfn main() { mut app := App{}; _ = build(mut app) }\n')!
	for body, expected in {
		'Slider(maxx: 10)':                                         ['main.vml:2:12:', 'maxx']
		'Slider(max: "ten")':                                       ['main.vml:2:12:', 'max']
		'Column(align_items: strech)':                              ['main.vml:2:12:', 'strech']
		'Sldier(max: 1)':                                           ['main.vml:2:5:', 'Sldier`']
		'Label(style: [font_sise(3)])':                             ['main.vml:2:11:', 'font_sise']
		'Slider(bind.value: app.items)':                            ['main.vml:2:12:', '']
		'Slider(bind.value: app.ready)':                            ['main.vml:2:12:', 'mutable']
		'Label(text: app.hidden)':                                  ['main.vml:2:17:', 'public']
		'Label { Label(text: "x") }':                               ['main.vml:2:13:',
			'Label has no children']
		'Label(x: 4)':                                              ['main.vml:2:11:', 'x/y']
		'Button(on_click: app.missing())':                          ['main.vml:2:12:', 'missing']
		'Repeater(model: app.items, key: item.secret) { Label() }': ['main.vml:2:37:', 'public']
	} {
		os.write_file(os.join_path(root, 'main.vml'), 'Column {\n    ${body}\n}\n')!
		result := vml_lower_compile(root, 'main', ['-check'])
		assert result.exit_code != 0, body + '\n' + result.output
		assert result.output.contains(expected[0]), body + '\n' + result.output
		assert result.output.contains(expected[1]), body + '\n' + result.output
		assert !result.output.contains('<veb-template>'), body + '\n' + result.output
	}
}

// Errors inside imported components point at the component's own file.
fn test_vml_lower_reports_imported_component_errors_at_their_location() {
	root := vml_lower_project('imports')
	defer {
		os.rmdir_all(root) or {}
	}
	os.write_file(os.join_path(root, 'main.v'), "module main
import ui2
struct Item {
	secret string
pub:
	id   int
	name string
}
struct App {
	private_value int
pub:
	items    []Item
	readonly int
pub mut:
	count int
	text  string
}
pub fn (mut app App) unsupported(value bool) { _ = value }
pub fn (mut app App) select(value int) { app.count = value }
fn build(mut app App) ui2.Element { return \$vml('main.vml') }
fn main() { mut app := App{items: [Item{id: 3}]}; _ = build(mut app) }
")!
	os.write_file(os.join_path(root, 'main.vml'), 'import Content\nColumn { Content {} }')!
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
		'Button(on_text: app.select(1))',
		'TextField(text: "removed")',
		'Button(on_click: app.unsupported(1))',
		'Button(on_click: app.select("wrong"))',
		'Button(on_click: app.select(app.count ? 1 : 2))',
		'Button(on_click: app.select(app.count == "7" ? 1 : 2))',
		'Button(on_click: app.select(false || app.count == "7" ? 1 : 2))',
		'Button(on_click: app.select(app.text + "bad"))',
		'Button { Label(text: "child") }',
		'Repeater(model: app.items, key: item.id) { Button(on_click: app.select(item.missing)) }',
	] {
		os.write_file(import_path, 'component Content() {\n    Column {\n        ${body}\n    }\n}\n')!
		result := vml_lower_compile(root, 'main', ['-check'])
		assert result.exit_code != 0, body + '\n' + result.output
		assert result.output.contains('content.vml:3:'), body + '\n' + result.output
		assert !result.output.contains('<veb-template>:'), body + '\n' + result.output
	}
	os.write_file(import_path, 'component Content() {\n    Column {\n        Repeater(model: app.items, key: item.id) { Button(on_click: app.count = item.id) }\n    }\n}\n')!
	bin := os.join_path(root, 'valid')
	valid := vml_lower_compile(root, 'main', ['-o', bin])
	assert valid.exit_code == 0, valid.output
	run := os.exec([bin])
	assert run.exit_code == 0, run.output
}

/* MOCK_UI2
module ui2

// A minimal stand-in for ui2's generic VML runtime: the same public names and
// signatures the generic lowering emits. Reactive properties are evaluated on
// every build, so a document built again sees the model's current values.

pub struct Rect { pub: x f64 y f64 width f64 height f64 }
pub fn vml_bounds() Rect { return Rect{width: 800, height: 600} }

pub enum ElementEventKind { click change }
pub struct ElementEvent { pub: kind ElementEventKind value f64 text string }
pub type ElementCallback = fn (ElementEvent)
pub enum Align { start center end stretch }
pub type DisplayText = string | int | f64

pub fn (text DisplayText) str() string {
	return match text {
		string { text }
		int { text.str() }
		f64 { text.str() }
	}
}

pub struct Element {
pub:
	kind     string
	id       string
	key      string
	text     string
	align    Align
	bg       u32
	radius   f64
	frame    Rect
	children []Element
	on_event ElementCallback = unsafe { nil }
}

pub struct StylePatch { pub: bg ?u32 radius ?f64 size ?f64 }
pub fn compose_styles(styles []StylePatch) StylePatch {
	mut result := StylePatch{}
	for style in styles {
		result = StylePatch{
			bg:     if v := style.bg { ?u32(v) } else { result.bg }
			radius: if v := style.radius { ?f64(v) } else { result.radius }
			size:   if v := style.size { ?f64(v) } else { result.size }
		}
	}
	return result
}
pub fn style_background(color u32) StylePatch { return StylePatch{bg: color} }
pub fn style_radius(radius f64) StylePatch { return StylePatch{radius: radius} }
pub fn style_font_size(size f64) StylePatch { return StylePatch{size: size} }
pub fn style_hover(styles []StylePatch) !StylePatch { return compose_styles(styles) }

// Props types. `build` makes the element; `event` applies an event to the
// props and returns the handler to run after the bindings.
pub struct ColumnProps { pub mut: align_items Align style StylePatch }
pub fn (p ColumnProps) build(children []Element) Element { return Element{kind: 'column', align: p.align_items, bg: p.style.bg or { 0 }, radius: p.style.radius or { 0 }, children: children} }
pub fn (mut p ColumnProps) event(e ElementEvent) ElementCallback { return unsafe { nil } }
pub fn (p ColumnProps) frame() Rect { return Rect{width: 800} }

pub struct SliderProps { pub mut: value f64 max f64 = 100 on_change ElementCallback = unsafe { nil } }
pub fn (p SliderProps) build(children []Element) Element { return Element{kind: 'slider', text: p.value.str()} }
pub fn (mut p SliderProps) event(e ElementEvent) ElementCallback {
	p.value = e.value
	return p.on_change
}
pub fn (p SliderProps) frame() Rect { return Rect{width: 120, height: 20} }

pub struct LabelProps { pub mut: text DisplayText x f64 style StylePatch }
pub fn (p LabelProps) build(children []Element) Element { return Element{kind: 'label', text: p.text.str()} }
pub fn (mut p LabelProps) event(e ElementEvent) ElementCallback { return unsafe { nil } }
pub fn (p LabelProps) frame() Rect { return Rect{width: 40} }

pub struct ButtonProps { pub mut: text string on_click ElementCallback = unsafe { nil } }
pub fn (p ButtonProps) build(children []Element) Element { return Element{kind: 'button', text: p.text} }
pub fn (mut p ButtonProps) event(e ElementEvent) ElementCallback { return p.on_click }
pub fn (p ButtonProps) frame() Rect { return Rect{width: 60} }

pub fn vml_guard_child[P, C]() {
	$if P is LabelProps || P is SliderProps || P is ButtonProps { $compile_error('Label has no children') }
}
pub fn vml_guard_positioned[Q]() {
	$if Q is ColumnProps { $compile_error('x/y require an Absolute parent') }
}

pub fn vml_assign[T, V](current T, value V) T {
	_ = current
	$if T is V {
		return value
	} $else $if T is $int || T is $float {
		return T(value)
	} $else {
		$compile_error('VML binding requires a source of the field type')
	}
}

pub fn vml_callback[F](callback F, config VmlCallbackConfig) ElementCallback {
	$if F is fn () {
		return fn [callback] [F](event ElementEvent) { callback() }
	} $else {
		return callback
	}
}
@[params]
pub struct VmlCallbackConfig { pub: refresh bool = true }

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

@[heap]
pub struct SignalScope {}
pub fn (mut scope SignalScope) effect(name string, run fn () !) ! { run()! }

type VmlRender = fn () ![]Element

@[params]
pub struct VmlDocumentConfig { pub: follow_viewport bool }
@[params]
pub struct VmlSourceLocation { pub: source string line int column int }
@[params]
pub struct VmlNodeOptions { pub: id string identity string path string key string slot int = -1 src VmlSourceLocation }

@[heap]
pub struct CompiledVmlComponent {
pub:
	scope &SignalScope = &SignalScope{}
	name  string
mut:
	values map[string]voidptr
	root   VmlRender = unsafe { nil }
}

pub fn (mut component CompiledVmlComponent) child(name string) !&CompiledVmlComponent { return &CompiledVmlComponent{name: component.name + '/' + name} }
pub fn (author &CompiledVmlComponent) slot_child(mut host CompiledVmlComponent, name string) !&CompiledVmlComponent { return &CompiledVmlComponent{name: host.name + '/' + name} }
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
pub fn (mut component CompiledVmlComponent) computed[T](name string, compute fn () !T) !&Memo[T] { return &Memo[T]{compute: compute} }
pub fn (component &CompiledVmlComponent) callback(action fn (ElementEvent) !) ElementCallback {
	return fn [action] (event ElementEvent) { action(event) or { panic(err) } }
}
pub fn (mut component CompiledVmlComponent) on_mount(name string, action fn () !) ! { action()! }
pub fn (mut component CompiledVmlComponent) on_unmount(name string, action fn ()) ! {}
pub fn (mut component CompiledVmlComponent) on_cleanup(name string, cleanup fn ()) ! {}
pub fn (mut component CompiledVmlComponent) prepare_theme_tokens(names []string) ! {}
pub fn (component &CompiledVmlComponent) color_token(name string) !u32 { return 0xabcdef }
pub fn (component &CompiledVmlComponent) radius_token(name string) !f64 { return 8 }
pub fn (component &CompiledVmlComponent) spacing_token(name string) !f64 { return 4 }
pub fn (component &CompiledVmlComponent) font_size_token(name string) !f64 { return 14 }

@[heap]
pub struct VmlDocument {
pub mut:
	owner &CompiledVmlComponent
}
pub fn vml_document(frame Rect, cfg VmlDocumentConfig) !&VmlDocument { return &VmlDocument{owner: &CompiledVmlComponent{name: 'root'}} }
pub fn (mut d VmlDocument) finish() !Element { return d.owner.root()![0] }

@[heap]
pub struct VmlWidgetNode[P] {
mut:
	props    P
	id       string
	key      string
	setters  []fn (mut P) !
	binds    []fn (P) !
	children []VmlRender
}

@[heap]
pub struct VmlSegment {
mut:
	children []VmlRender
}

fn new_node[P](props P, o VmlNodeOptions) &VmlWidgetNode[P] {
	return &VmlWidgetNode[P]{props: props, id: o.id, key: o.key}
}
pub fn vml_root[P](mut owner CompiledVmlComponent, props P, o VmlNodeOptions) !&VmlWidgetNode[P] {
	node := new_node(props, o)
	owner.root = fn [node] [P]() ![]Element { return [node.element()!] }
	return node
}
pub fn vml_child[P, N](mut parent N, mut owner CompiledVmlComponent, props P, o VmlNodeOptions) !&VmlWidgetNode[P] {
	node := new_node(props, o)
	parent.children << fn [node] [P]() ![]Element { return [node.element()!] }
	return node
}
pub fn (mut n VmlWidgetNode[P]) prop(name string, set fn (mut P) !) ! {
	set(mut n.props)!
	n.setters << set
}
pub fn (mut n VmlWidgetNode[P]) bind(name string, write fn (P) !) ! { n.binds << write }
pub fn (n &VmlWidgetNode[P]) geometry() !Rect { return n.props.frame() }
fn (n &VmlWidgetNode[P]) element() !Element {
	mut node := unsafe { n }
	for set in node.setters { set(mut node.props)! }
	mut children := []Element{}
	for render in node.children { children << render()! }
	element := node.props.build(children)
	return Element{
		...element
		id:       node.id
		key:      node.key
		on_event: fn [mut node] [P](event ElementEvent) { node.dispatch(event) }
	}
}
fn (mut n VmlWidgetNode[P]) dispatch(event ElementEvent) {
	handler := n.props.event(event)
	for write in n.binds { write(n.props) or { panic(err) } }
	if handler != unsafe { nil } { handler(event) }
}

@[heap]
pub struct VmlRepeat[T] {
	items fn () ![]T = unsafe { nil }
	key   fn (T) string = unsafe { nil }
	build fn (mut CompiledVmlComponent, mut VmlSegment, &Signal[T]) ! = unsafe { nil }
	src   VmlSourceLocation
}
fn (r &VmlRepeat[T]) render() ![]Element {
	mut result := []Element{}
	mut seen := map[string]bool{}
	for index, item in r.items()! {
		key := r.key(item)
		if key in seen { return error('${r.src.source}:${r.src.line}: duplicate key `${key}`') }
		seen[key] = true
		mut owner := &CompiledVmlComponent{name: 'item:' + key}
		owner.state('@index', index)!
		mut segment := &VmlSegment{}
		r.build(mut owner, mut segment, &Signal[T]{value: item})!
		for render in segment.children {
			for element in render()! {
				result << Element{ ...element, key: if element.key == '' { key } else { key + '/' + element.key } }
			}
		}
	}
	return result
}
pub fn vml_repeat[T, N](mut parent N, name string, items fn () ![]T, key fn (T) string, build fn (mut CompiledVmlComponent, mut VmlSegment, &Signal[T]) !, src VmlSourceLocation) ! {
	repeat := &VmlRepeat[T]{items: items, key: key, build: build, src: src}
	parent.children << fn [repeat] [T]() ![]Element { return repeat.render()! }
}
MOCK_UI2 */
