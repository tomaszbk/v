import os

const vml_codegen_vexe = @VEXE
const vml_codegen_tests_dir = os.dir(@FILE)
const vml_codegen_v3_dir = os.dir(vml_codegen_tests_dir)
const vml_codegen_vlib_dir = os.dir(vml_codegen_v3_dir)

fn vml_codegen_mock_ui2() string {
	return (os.read_file(@FILE) or { panic(err) }).all_after('/* MOCK_UI2\n').all_before('\nMOCK_UI2 */')
}

fn test_vml_lowers_to_direct_ui2_elements() {
	v3_bin := vml_codegen_vexe
	pid := os.getpid()
	root := os.join_path(os.temp_dir(), 'v3_vml_codegen_${pid}_project')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'ui2', 'core')) or { panic(err) }
	os.write_file(os.join_path(root, 'v.mod'), "Module { name: 'vml_codegen' }\n") or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'ui2', 'v.mod'), "Module { name: 'ui2', subdirs: ['core'] }\n") or { panic(err) }
	os.write_file(os.join_path(root, 'ui2', 'core', 'ui2.v'), vml_codegen_mock_ui2()) or {
		panic(err)
	}
	os.write_file(os.join_path(root, 'form.vml'), 'Screen {
    id: root
    width: root.half
    property f64 half: root.width / 2
    Repeater {
        model: app.items
        key: item.id
        Label {
            text: "\${item.name}:\${index}"
            width: root.half
            on_click: app.select(item.id)
        }
    }
	ProgressBar { value: 25 max: 50 }
	Slider {
		id: volume
		bind.value: app.level
		min: 0
		max: 100
		step: 0.5
		orientation: "vertical"
		value_track: true
		on_change: app.select(4)
	}
	Switch { id: notifications bind.active: app.enabled on_active: app.select(5) }
	Spinner {
		id: location
		bind.text: app.location
		text_autoupdate: true
		on_change: app.choose("Work")
		Option { text: "Home" }
		Option { text: "Work" }
	}
	Checkbox { text: "Ready" checked: true }
	Rectangle { border_width: 2 border_right: 4 }
	Button { text: "Select" on_click: app.select(app.selected) }
}') or { panic(err) }
	source := "module main

import ui2

struct Item {
pub:
	id int
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
	return \$vml('form.vml')
}

fn main() {
	mut app := App{items: [Item{id: 7, name: 'a'}, Item{id: 8, name: 'b'}], level: 12.5, location: 'Home'}
	root := build(mut app)
	mut mutable_app := app
	ui2.dispatch[App](mut mutable_app, 'select', 9) or { panic(err) }
	println(root.children.len.str() + ' ' + root.children[0].text + ' ' + root.children[0].key + ' ' + ui2.callback_name(root.children[0].on_event))
	println(mutable_app.selected.str() + ' ' + root.children[2].accessibility_role)
	println(root.children[3].accessibility_role + ' ' + root.children[3].value.str() + ':' + root.children[3].min_value.str() + ':' + root.children[3].max_value.str() + ' ' + ui2.callback_name(root.children[3].on_event))
	println(root.children[4].accessibility_role + ' ' + root.children[4].checked.str() + ' ' + ui2.callback_name(root.children[4].on_event))
	println(root.children[5].accessibility_role + ' ' + root.children[5].text + ' ' + ui2.callback_name(root.children[5].on_event))
	println(root.children[6].accessibility_role + ' ' + root.children[7].box.border_left.str() + ':' + root.children[7].box.border_right.str() + ' ' + ui2.callback_name(root.children[8].on_event))
}
"
	main_path := os.join_path(root, 'main.v')
	os.write_file(main_path, source) or { panic(err) }
	bin := os.join_path(root, 'vml_codegen')
	compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang', '-no-retry-compilation',
		'-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}', '-b', 'c', '-o', bin,
		main_path])
	assert compile.exit_code == 0, compile.output
	assert !compile.output.contains('C compilation failed'), compile.output
	run := os.exec([bin])
	assert run.exit_code == 0, run.output
	assert run.output.trim_space() == '9 a:0 7 callback\n9 progressbar\nslider 12.5:0.0:100.0 callback\nswitch false callback\ncombobox Home callback\ncheckbox 2.0:4.0 callback', run.output
	os.write_file(os.join_path(root, 'review.vml'), 'Screen {
	id: review_root
	property f64 half: review_root.quarter * 2
	property f64 quarter: 25
	property int custom_selected: 1
	property color accent: "#00ff00"
	width: review_root.half
	background: "#ff0000"
	Rectangle { id: first width: 123 }
	Label { width: first.width }
	Repeater {
		model: app.items
		key: item
		Rectangle { id: repeated_first width: 77 }
		Button { width: repeated_first.width on_click: app.select(index + 1) }
	}
	Label { text: 1 + 2 }
	Label { text: app.count + 1 }
	Label { text: "count:" + app.count }
	Label { text: app.display_name() }
	Button { on_click: app.select(review_root.custom_selected) }
	Rectangle { width: app.content_width() background: review_root.accent }
	Label { text: 4 - 1 }
	Label { text: 3 * 4 }
	Label { text: 8 / 2 }
	Label { text: 7 % 4 }
	Button { on_click: app.select(-1) }
	Label { text: app.ready && app.enabled }
	Label { text: app.count > 0 }
}') or { panic(err) }
	review_path := os.join_path(root, 'review.v')
	os.write_file(review_path, "module main\n\nimport ui2\n\nstruct App {\npub:\n\titems []int\n\tcount int\n\tready bool\n\tenabled bool\npub mut:\n\tselected int\n}\n\npub fn (mut app App) select(value int) {\n\tapp.selected = value\n}\n\npub fn (app &App) display_name() string {\n\treturn 'display:\${app.count}'\n}\n\npub fn (app &App) content_width() int {\n\treturn 88\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('review.vml')\n}\n\nfn main() {\n\tmut app := App{items: [10], count: 2, ready: true}\n\troot := build(mut app)\n\tprintln(root.children[4].frame.width.str() + ' ' + root.box.bg.str() + ' ' + root.children[1].frame.width.str() + ' ' + root.children[3].frame.width.str() + ' ' + ui2.callback_name(root.children[3].on_event) + ' ' + root.children[4].text + ' ' + root.children[5].text + ' ' + root.children[6].text + ' ' + root.children[7].text + ' ' + ui2.callback_name(root.children[8].on_event) + ' ' + root.children[9].frame.width.str() + ':' + root.children[9].box.bg.str() + ' ' + root.children[10].text + ' ' + root.children[11].text + ' ' + root.children[12].text + ' ' + root.children[13].text + ' ' + ui2.callback_name(root.children[14].on_event) + ' ' + root.children[15].text + ' ' + root.children[16].text)\n}\n") or {
		panic(err)
	}
	review_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, review_path])
	assert review_compile.exit_code == 0, review_compile.output
	review_run := os.exec([bin])
	assert review_run.exit_code == 0, review_run.output
	assert review_run.output.trim_space() == '50.0 16711680 123.0 77.0 callback 3 3 count:2 display:2 callback 88.0:65280 3 12 4 3 callback false true', review_run.output
	os.write_file(os.join_path(root, 'events.vml'), 'Screen {
	TextInput { multiline: false id: message on_change: app.choose("Typed") }
	TextInput { id: notes on_change: app.choose("Notes") }
}') or { panic(err) }
	events_path := os.join_path(root, 'events.v')
	os.write_file(events_path, "module main\n\nimport ui2\n\nstruct App {}\n\npub fn (mut app App) choose(value string) {\n\t_ = app\n\t_ = value\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('events.vml')\n}\n\nfn main() {\n\tmut app := App{}\n\troot := build(mut app)\n\tprintln(ui2.callback_name(root.children[0].on_event)  + ' ' + ui2.callback_name(root.children[1].on_event) )\n}\n") or {
		panic(err)
	}
	events_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, events_path])
	assert events_compile.exit_code == 0, events_compile.output
	events_run := os.exec([bin])
	assert events_run.exit_code == 0, events_run.output
	assert events_run.output.trim_space() == 'callback callback', events_run.output
	os.write_file(os.join_path(root, 'nested.vml'), 'Screen {
	Repeater {
		model: app.rows
		key: item.id
		Repeater {
			model: item.values
			key: item
			Label { text: item }
		}
	}
}') or { panic(err) }
	nested_path := os.join_path(root, 'nested.v')
	os.write_file(nested_path, "module main\n\nimport ui2\n\nstruct Row {\npub:\n\tid int\n\tvalues []int\n}\n\nstruct App {\npub:\n\trows []Row\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('nested.vml')\n}\n\nfn main() {\n\tmut app := App{rows: [Row{id: 10, values: [1]}, Row{id: 20, values: [1]}]}\n\troot := build(mut app)\n\tprintln(root.children[0].key + ' ' + root.children[1].key)\n}\n") or {
		panic(err)
	}
	nested_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, nested_path])
	assert nested_compile.exit_code == 0, nested_compile.output
	nested_run := os.exec([bin])
	assert nested_run.exit_code == 0, nested_run.output
	assert nested_run.output.trim_space() == '3130/31:0 3230/31:0', nested_run.output
	os.write_file(os.join_path(root, 'geometry_color.vml'), 'Screen {
	Rectangle { id: box width: 100 height: box.width background: app.theme_color() }
	Rectangle { background: app.numeric_color() }
}') or { panic(err) }
	geometry_color_path := os.join_path(root, 'geometry_color.v')
	os.write_file(geometry_color_path, "module main\n\nimport ui2\n\nstruct App {}\n\npub fn (app &App) theme_color() string {\n\treturn '#112233'\n}\n\npub fn (app &App) numeric_color() u32 {\n\treturn u32(0x445566)\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('geometry_color.vml')\n}\n\nfn main() {\n\tmut app := App{}\n\troot := build(mut app)\n\tprintln(root.children[0].frame.width.str() + ':' + root.children[0].frame.height.str() + ':' + root.children[0].box.bg.str() + ' ' + root.children[1].box.bg.str())\n}\n") or {
		panic(err)
	}
	geometry_color_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, geometry_color_path])
	assert geometry_color_compile.exit_code == 0, geometry_color_compile.output
	geometry_color_run := os.exec([bin])
	assert geometry_color_run.exit_code == 0, geometry_color_run.output
	assert geometry_color_run.output.trim_space() == '100.0:100.0:1122867 4478310', geometry_color_run.output
	os.write_file(os.join_path(root, 'custom.vml'), 'Screen {
	id: root
	property Item selected: app.item
	property f32 ratio: 1 / 2
	Label { text: root.selected.name }
	Rectangle { width: root.ratio }
}') or { panic(err) }
	custom_path := os.join_path(root, 'custom.v')
	os.write_file(custom_path, "module main\n\nimport ui2\n\nstruct Item {\npub:\n\tname string\n}\n\nstruct App {\npub:\n\titem Item\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('custom.vml')\n}\n\nfn main() {\n\tmut app := App{item: Item{name: 'chosen'}}\n\troot := build(mut app)\n\tprintln(root.children[0].text + ' ' + root.children[1].frame.width.str())\n}\n") or {
		panic(err)
	}
	custom_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, custom_path])
	assert custom_compile.exit_code == 0, custom_compile.output
	custom_run := os.exec([bin])
	assert custom_run.exit_code == 0, custom_run.output
	assert custom_run.output.trim_space() == 'chosen 0.5', custom_run.output
	os.write_file(os.join_path(root, 'expressions.vml'), r'Screen {
	Repeater {
		model: app.values
		key: item
		Label { text: item-1 }
	}
	Repeater {
		model: app.items
		key: item.value
		Rectangle { background: item.color }
	}
	Label { text: "${app.label(\"}\")}" }
}') or { panic(err) }
	expressions_path := os.join_path(root, 'expressions.v')
	os.write_file(expressions_path, "module main\n\nimport ui2\n\nstruct Item {\npub:\n\tvalue int\n\tcolor string\n}\n\nstruct App {\npub:\n\tvalues []int\n\titems []Item\n}\n\nfn (app &App) label(value string) string {\n\t_ = app\n\treturn value\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('expressions.vml')\n}\n\nfn main() {\n\tmut app := App{values: [10], items: [Item{value: 1, color: '#112233'}]}\n\troot := build(mut app)\n\tprintln(root.children[0].text + ' ' + root.children[1].box.bg.str() + ' ' + root.children[2].text)\n}\n") or {
		panic(err)
	}
	expressions_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, expressions_path])
	assert expressions_compile.exit_code == 0, expressions_compile.output
	expressions_run := os.exec([bin])
	assert expressions_run.exit_code == 0, expressions_run.output
	assert expressions_run.output.trim_space() == '9 1122867 }', expressions_run.output
	os.write_file(os.join_path(root, 'form.vml'), 'Screen { MessageBox { Button { on_click: app.missing() } } }') or { panic(err) }
	invalid := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang', '-no-retry-compilation',
		'-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}', '-b', 'c', '-o', bin,
		main_path])
	assert invalid.exit_code != 0, invalid.output
	assert invalid.output.contains('missing'), invalid.output
	os.write_file(os.join_path(root, 'form.vml'), 'Screen { Button { MenuItem { on_click: app.missing() } } }') or { panic(err) }
	invalid_menu := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, main_path])
	assert invalid_menu.exit_code != 0, invalid_menu.output
	assert invalid_menu.output.contains('missing'), invalid_menu.output
	os.write_file(os.join_path(root, 'form.vml'), 'Screen { Button { on_click: app.private_action() } }') or { panic(err) }
	invalid_private := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, main_path])
	assert invalid_private.exit_code != 0, invalid_private.output
	assert invalid_private.output.contains('must be public'), invalid_private.output
	os.write_file(os.join_path(root, 'single_quotes.vml'), 'Screen { Label { text: \'It\\\'s "ready"\' tooltip: \'line one\\nline two\' } Label { text: "\${app.label(\'}\')}" } }') or {
		panic(err)
	}
	single_quotes_path := os.join_path(root, 'single_quotes.v')
	os.write_file(single_quotes_path, "module main\n\nimport ui2\n\nstruct App {}\n\npub fn (app &App) label(value string) string {\n\t_ = app\n\treturn value\n}\n\nfn build(mut app App) ui2.Element {\n\treturn \$vml('single_quotes.vml')\n}\n\nfn main() {\n\tmut app := App{}\n\troot := build(mut app)\n\tprintln(root.children[0].text + ':' + root.children[0].tooltip + ':' + root.children[1].text)\n}\n") or {
		panic(err)
	}
	single_quotes_compile := os.exec([v3_bin, '-new-compiler', '-gc', 'boehm', '-cc', 'clang',
		'-no-retry-compilation', '-nocache', '-path', '${root}' + '|' + '${vml_codegen_vlib_dir}',
		'-b', 'c', '-o', bin, single_quotes_path])
	assert single_quotes_compile.exit_code == 0, single_quotes_compile.output
	single_quotes_run := os.exec([bin])
	assert single_quotes_run.exit_code == 0, single_quotes_run.output
	assert single_quotes_run.output == 'It\'s "ready":line one\nline two:}\n', single_quotes_run.output
}

/* MOCK_UI2
module ui2

pub enum Kind { screen view label image button checkbox dropdown text_field text_area scroll slider switch_control }
pub enum Align { left center right }
pub enum Orientation { horizontal vertical }
pub struct Rect { pub: x f64 y f64 width f64 height f64 }
pub struct BoxStyle { pub: bg u32 = 0xffffff radius f64 transparent bool border_color u32 border_left f64 border_top f64 border_right f64 border_bottom f64 }
pub struct TextStyle { pub: color u32 = 0x111111 background_color u32 size f64 = 15 font_family string bold bool italic bool underline bool strikethrough bool shadow bool outline bool vertical_align string link string align Align head_indent f64 first_line_indent f64 hyphenation_factor f64 lines int = 1 }
pub enum ElementEventKind { tap change submit scroll pointer_down pointer_drag pointer_up long_press swipe_left link }
pub struct ElementEvent { pub: kind ElementEventKind text string value f64 checked bool }
pub type ElementCallback = fn (ElementEvent)
pub struct MenuEntry { pub: id string title string on_select ElementCallback = unsafe { nil } }
pub struct Menu { pub: title string items []MenuItem }
pub struct MenuItem { pub: id string title string items []MenuItem on_select ElementCallback = unsafe { nil } shortcut string checked bool enabled bool = true separator bool }
pub fn menu_separator() MenuItem { return MenuItem{separator: true} }
pub fn validate_menus(menus []Menu) ! { _ = menus }
pub struct SliderStyle { pub: track_color u32 value_track_color u32 thumb_color u32 track_width f64 thumb_size f64 }
pub struct SwitchStyle { pub: inactive_track_color u32 active_track_color u32 thumb_color u32 disabled_track_color u32 disabled_thumb_color u32 }
pub struct Element { pub: kind Kind id string on_event ElementCallback = unsafe { nil } key string text string checked bool image_path string tooltip string placeholder string frame Rect box BoxStyle text_style TextStyle native_style bool keyboard int disable_scroll bool long_press bool swipe_left bool readonly bool persistent_scrollbars bool secure bool clickable bool draggable bool rotation f64 cursor string menu []MenuEntry children []Element hidden bool enabled bool = true accessibility_role string accessibility_label string accessibility_value string autocorrect bool = true padding_left f64 = 12 value f64 min_value f64 max_value f64 step f64 orientation Orientation padding f64 value_track bool slider_style SliderStyle switch_style SwitchStyle }
pub struct TextInputConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect text string placeholder string multiline bool = true password bool readonly bool disable_scroll bool box BoxStyle text_style TextStyle keyboard int }
pub fn text_input(config TextInputConfig) !Element { return Element{kind: if config.multiline { .text_area } else { .text_field }, id: config.id, on_event: config.on_event, frame: config.frame, text: config.text, placeholder: config.placeholder, secure: config.password, readonly: config.readonly, disable_scroll: config.disable_scroll, box: config.box, text_style: config.text_style, keyboard: config.keyboard} }
pub const keyboard_default = 0
pub const keyboard_decimal = 8
pub fn bounds() Rect { return Rect{width: 800, height: 600} }
pub fn rect(x f64, y f64, width f64, height f64) Rect { return Rect{x, y, width, height} }
pub fn parse_hex_color(value string) u32 { return if value == '#112233' { u32(0x112233) } else { u32(0) } }
pub struct ProgressBarConfig { pub: id string frame Rect value f64 max f64 = 100 background u32 color u32 radius f64 }
pub fn progress_bar(config ProgressBarConfig) Element { return Element{kind: .view, id: config.id, frame: config.frame, accessibility_role: 'progressbar', accessibility_label: 'Progress', accessibility_value: '${config.value} of ${config.max}'} }
pub struct SliderConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect min f64 max f64 = 100 value f64 step f64 orientation Orientation padding f64 value_track bool style SliderStyle }
pub fn slider(config SliderConfig) Element { return Element{kind: .slider, id: config.id, on_event: config.on_event, frame: config.frame, value: config.value, min_value: config.min, max_value: config.max, step: config.step, orientation: config.orientation, padding: config.padding, value_track: config.value_track, slider_style: config.style, accessibility_role: 'slider', accessibility_label: 'Slider', accessibility_value: config.value.str()} }
pub struct SwitchConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect active bool style SwitchStyle }
pub fn switch_control(config SwitchConfig) Element { return Element{kind: .switch_control, id: config.id, on_event: config.on_event, frame: config.frame, checked: config.active, switch_style: config.style, accessibility_role: 'switch', accessibility_label: 'Switch', accessibility_value: if config.active { 'on' } else { 'off' }} }
pub struct SpinnerConfig { pub: id string on_event ElementCallback = unsafe { nil } frame Rect text string values []string text_autoupdate bool box BoxStyle text_style TextStyle }
pub fn spinner(config SpinnerConfig) Element { assert config.values == ['Home', 'Work']; return Element{kind: .dropdown, id: config.id, on_event: config.on_event, frame: config.frame, text: if config.text_autoupdate && config.values.len > 0 { config.values[0] } else { config.text }, box: config.box, text_style: config.text_style, accessibility_role: 'combobox', accessibility_label: 'Spinner'} }
pub struct MessageBoxAction { pub: id string on_event ElementCallback = unsafe { nil } title string }
pub struct MessageBoxConfig { pub: id string frame Rect title string text string hidden bool width f64 height f64 actions []MessageBoxAction }
pub fn custom_message_box(config MessageBoxConfig) Element { return Element{kind: .view, id: config.id, frame: config.frame, text: config.text, hidden: config.hidden} }
pub type CompiledVmlArgument = int | string
pub struct CompiledVmlCallbackConfig { pub: binding_property string binding_target string action_name string arguments []CompiledVmlArgument argument_path string }
pub fn compiled_vml_callback[T](mut model T, config CompiledVmlCallbackConfig) ElementCallback { return fn (event ElementEvent) { _ = event } }
pub fn callback_name(callback ElementCallback) string { return if voidptr(callback) != unsafe { nil } { 'callback' } else { '' } }
pub fn request_refresh() {}
pub fn validate_element_tree(root Element) ! { _ = root }
pub fn dispatch[T](mut model T, name string, argument int) ! {
	$for method in T.methods {
		if method.name == name {
			$if method.is_pub && method.typ is fn ( int ) {
				model.$method(argument)
				return
			} $else {
				return error('unsupported method')
			}
		}
	}
	return error('unknown method')
}
MOCK_UI2 */

fn test_vml_structure_checks_empty_lists_branches_actions_and_import_locations() {
	root := os.join_path(os.vtmp_dir(), 'vml_structure_codegen_${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'ui2', 'core'))!
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, 'v.mod'), "Module { name: 'structure' }")!
	os.write_file(os.join_path(root, 'ui2', 'v.mod'), "Module { name: 'ui2', subdirs: ['core'] }")!
	os.write_file(os.join_path(root, 'ui2', 'core', 'ui2.v'), vml_codegen_mock_ui2())!
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
fn main() { mut app := App{}; _ = build(mut app) }
")!
	os.write_file(os.join_path(root, 'main.vml'), 'import Content\nView { Content {} }')!
	import_path := os.join_path(root, 'content.vml')
	for body in [
		'Repeater { model: app.items key: item.id Label { text: item.missing } }',
		'Repeater { model: app.items key: item.id Label { text: item.secret } }',
		'Label { text: app.private_value }',
		'Label { text: "\${app.private_value}" }',
		'Label { text: true ? "ok" : app.missing }',
		'Repeater { model: app.count key: item Label { text: "bad" } }',
		'Repeater { model: app.items key: item Label { text: "bad" } }',
		'Button { on_click: app.readonly = 1 }',
		'Button { on_click: app.count = "wrong" }',
		'Slider { bind.value: app.items }',
		'TextInput { multiline: false on_text: app.select(1) }',
		'TextField { text: \"removed\" }',
		'Button { on_click: app.unsupported(true) }',
		'Button { on_click: app.select("wrong") }',
		'Button { on_click: app.select(app.count ? 1 : 2) }',
		'Button { on_click: app.select(app.count == "7" ? 1 : 2) }',
		'Button { on_click: app.select(false || app.count == "7" ? 1 : 2) }',
		'Button { on_click: app.select(app.text + "bad") }',
		'Button { MenuItem { text: app.count } }',
		'Repeater { model: app.items key: item.id Button { on_click: app.select(item.missing) } }',
	] {
		os.write_file(import_path, 'module Content\nView {\n ${body}\n}')!
		result := os.exec([@VEXE, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', 'clang',
			'-no-retry-compilation', '-path', root + '|' + vml_codegen_vlib_dir, '-check', main_path])
		assert result.exit_code != 0, body + '\n' + result.output
		assert result.output.contains('content.vml:3:'), result.output
		assert !result.output.contains('<veb-template>:'), result.output
	}
	os.write_file(import_path, 'module Content\nView { Repeater { model: app.items key: item.id Button { on_click: app.count = item.id } } }')!
	valid := os.exec([@VEXE, '-nocache', '-path', root + '|' + vml_codegen_vlib_dir, '-o',
		os.join_path(root, 'valid'), main_path])
	assert valid.exit_code == 0, valid.output
	run := os.exec([os.join_path(root, 'valid')])
	assert run.exit_code == 0, run.output
	// Menu properties use V's string/bool slots rather than display coercions.
	main_source := os.read_file(main_path)!
	os.write_file(main_path, main_source.replace('ui2.Element', '[]ui2.Menu'))!
	os.write_file(os.join_path(root, 'main.vml'), 'import Content\nContent {}')!
	for title, body in {
		'valid':    'Menu { title: "File" MenuItem { text: "New" shortcut: "cmd+n" checked: false enabled: true on_click: app.count = 1 } }'
		'title':    'Menu { title: app.count }'
		'shortcut': 'Menu { title: "File" MenuItem { text: "New" shortcut: app.count } }'
		'checked':  'Menu { title: "File" MenuItem { text: "New" checked: app.count } }'
		'enabled':  'Menu { title: "File" MenuItem { text: "New" enabled: app.count == "7" } }'
	} {
		os.write_file(import_path, 'module Content\nMenuBar {\n ${body}\n}')!
		result := os.exec([@VEXE, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', 'clang',
			'-no-retry-compilation', '-path', root + '|' + vml_codegen_vlib_dir, '-check', main_path])
		if title == 'valid' {
			assert result.exit_code == 0, result.output
		} else {
			assert result.exit_code != 0, title + '\n' + result.output
			assert result.output.contains('content.vml:3:'), result.output
		}
	}
}
