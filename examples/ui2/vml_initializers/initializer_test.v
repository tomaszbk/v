// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
module main

import os
import ui2

@[heap]
pub struct InitializerApp {
pub mut:
	count          int = 7
	geometry_width f64 = 80
	text_calls     int
	width_calls    int
	input_calls    int
	run_calls      int
	option_calls   int
	menu_calls     int
	basis_calls    int
}

// next_count records evaluation of display text.
pub fn (mut app InitializerApp) next_count() int {
	app.text_calls++
	return app.count + 1
}

// next_width records evaluation of preferred width.
pub fn (mut app InitializerApp) next_width() f64 {
	app.width_calls++
	return f64(app.count + 10)
}

// next_input records evaluation of a component input.
pub fn (mut app InitializerApp) next_input() int {
	app.input_calls++
	return app.count + 2
}

// next_run records evaluation of Run content.
pub fn (mut app InitializerApp) next_run() int {
	app.run_calls++
	return app.count + 5
}

// next_option records evaluation of an Option title.
pub fn (mut app InitializerApp) next_option() int {
	app.option_calls++
	return app.count + 3
}

// next_menu records evaluation of a MenuItem title.
pub fn (mut app InitializerApp) next_menu() int {
	app.menu_calls++
	return app.count + 4
}

// next_basis records evaluation of a flex child rule.
pub fn (mut app InitializerApp) next_basis() f64 {
	app.basis_calls++
	return f64(app.count + 30)
}

// resize updates the width source through a VML action.
pub fn (mut app InitializerApp) resize() {
	app.geometry_width = 120
}

fn geometry_tree(mut app InitializerApp) ui2.Element {
	return $vml('geometry.vml', ui2.rect(0, 0, 300, 300))
}

fn initializers_tree(mut app InitializerApp) ui2.Element {
	return $vml('view.vml', ui2.rect(0, 0, 300, 200))
}

fn test_property_and_input_initializers_evaluate_once_then_once_per_action() ! {
	mut app := &InitializerApp{}
	initial := initializers_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	mut layout := &ui2.LayoutTree{}
	layout.replace(initial)!
	first_node := root.element().children[0].compiled_node
	input_node := root.element().children[1].compiled_node
	for count in [7, 8, 9] {
		current := layout.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{})!
		assert current.children[0].compiled_node == first_node
		assert current.children[1].compiled_node == input_node
		assert current.children[0].text == (count + 1).str()
		assert current.children[0].frame.width == count + 10
		assert current.children[1].text == (count + 2).str()
		evaluations := count - 6
		assert [app.text_calls, app.width_calls, app.input_calls, app.run_calls, app.option_calls,
			app.menu_calls, app.basis_calls] ==
			[evaluations, evaluations, evaluations, evaluations, evaluations, evaluations, evaluations]
		assert app.text_calls == count - 6
		assert app.width_calls == count - 6
		assert app.input_calls == count - 6
		assert current.children[4].text_runs[0].text == (count + 5).str()
		assert current.children[5].menu[0].title == (count + 3).str()
		assert current.children[6].menu[0].title == (count + 4).str()
		assert current.children[7].children[0].frame.width == count + 30
		assert app.run_calls == count - 6
		assert app.option_calls == count - 6
		assert app.menu_calls == count - 6
		assert app.basis_calls == count - 6
		current.children[3].on_event(ui2.ElementEvent{ kind: .tap })
		layout.patch('root', root.element())!
	}
}

fn test_own_geometry_is_available_before_initializing_text() ! {
	mut app := &InitializerApp{}
	initial := initializers_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	assert root.element().children[2].children[0].text == 'width=100.0'
}

fn test_input_default_type_error_reports_the_input_location_and_vml_callsite() ! {
	raw_dir := os.join_path(os.vtmp_dir(), 'vml_input_default_${os.getpid()}')
	os.mkdir_all(raw_dir)!
	dir := os.real_path(raw_dir)
	defer { os.rmdir_all(dir) or {} }
	view := os.join_path(dir, 'view.vml')
	source := os.join_path(dir, 'main.v')
	os.write_file(source, 'import ui2
struct Wrong { count int }
fn main() { mut app := Wrong{}; _ = $vml("view.vml") }')!
	os.write_file(view, 'component Typed(valid bool = app.count) { Label(text: "value") }')!
	result := os.exec([@VEXE, '-b', 'c', '-cc', 'clang', '-o', os.join_path(dir, 'probe'), source])
	assert result.exit_code != 0, result.output
	assert result.output.contains('cannot use `int` as type `!bool`'), result.output
	assert result.output.contains('${view}:1:17:'), result.output
	assert result.output.contains('called from ${source}:3:'), result.output
}

fn test_self_and_sibling_geometry_remain_live_after_an_app_action() ! {
	mut app := &InitializerApp{}
	initial := geometry_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	mut layout := &ui2.LayoutTree{}
	layout.replace(initial)!
	_ = layout.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{})!
	box := root.element().children[0].compiled_node
	sibling := root.element().children[1].compiled_node
	current := root.element()
	assert current.children[0].frame.width == 80
	assert current.children[0].frame.height == 160
	assert current.children[1].frame.width == 90
	assert current.children[1].frame.height == 161
	assert current.children[2].text == '80.0x160.0'
	assert current.children[4].menu[0].title == 'Width 80.0'
	current.children[3].on_event(ui2.ElementEvent{ kind: .tap })
	layout.patch('root', root.element())!
	_ = layout.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{})!
	updated := root.element()
	assert updated.children[0].compiled_node == box
	assert updated.children[1].compiled_node == sibling
	assert updated.children[0].frame.width == 120
	assert updated.children[0].frame.height == 240
	assert updated.children[1].frame.width == 130
	assert updated.children[1].frame.height == 241
	assert updated.children[2].text == '120.0x240.0'
	assert updated.children[4].menu[0].title == 'Width 120.0'
	assert layout.stats().builds == 1
}
