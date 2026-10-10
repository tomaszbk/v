import os
import ui2

struct NumericTextApp {
pub mut:
	count   int    = 7
	amount  f64    = 12.5
	caption string = 'Español: niño, café'
	ready   bool   = true
	numbers []int  = [21, 34]
	calls   int
}

pub fn (mut app NumericTextApp) next_count() int {
	app.calls++
	return app.count + 1
}

fn numeric_text_build(mut app NumericTextApp) ui2.Element {
	return $vml('numeric_text.vml')
}

fn test_vml_formats_numeric_text_and_preserves_string_bindings() {
	mut app := NumericTextApp{}
	root := numeric_text_build(mut app)
	assert root.children[0].text == '7'
	assert root.children[1].text == '8'
	assert root.children[2].text == '12.5'
	assert root.children[3].text == 'Español: niño, café'
	assert root.children[4].text == '7'
	assert root.children[5].text == '8'
	assert app.calls == 1
	assert root.children[7].text == '21'
	assert root.children[8].text == '0'
	assert root.children[9].text == '34'
	assert root.children[10].text == '1'
	assert root.children[11].menu[0].title == '7'
	assert root.children[12].menu[0].title == '7'
	assert root.children[13].children[0].text == '7'
	root.children[6].on_event(ui2.ElementEvent{ kind: .change, text: 'mañana' })
	assert app.caption == 'mañana'
	assert app.calls == 2
	app.count = 9
	app.ready = false
	root.compiled_node.component.invalidate_app() or { panic(err) }
	updated := root.compiled_node.element()
	assert updated.children[0].compiled_node == root.children[0].compiled_node
	assert updated.children[6].id == root.children[6].id
	assert updated.children[0].text == '9'
	assert updated.children[3].text == 'mañana'
	assert updated.children[4].text == 'waiting'
	assert updated.children[11].menu[0].title == 'waiting'
	assert updated.children[13].children[1].text == 'waiting'
	assert updated.children[5].text == '10'
	assert app.calls == 3
}

fn test_vml_text_rejects_non_numeric_values_and_keeps_writeback_typed() {
	dir := os.join_path(os.vtmp_dir(), 'vml_numeric_text_errors_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'main.v'), 'import ui2
struct App {
pub mut:
    count int
    ready bool
    values []int
}
fn main() {
    mut app := App{}
    _ = \$vml("view.vml")
}')!
	for entry in [
		['Label(text: app.ready)', 'VML text requires a string or number'],
		['Label(text: app.values)', 'VML text requires a string or number'],
		['Label(text: app.ready ? 1 : app.values)', 'VML text requires a string or number'],
		['TextInput(bind.text: app.count)', 'string'],
		['TextInput(placeholder: app.count)', 'string'],
		['Label(text: "count: " + app.count)', 'cannot use `int`'],
	] {
		os.write_file(os.join_path(dir, 'view.vml'), entry[0])!
		result := os.exec([@VEXE, '-b', 'c', '-cc', 'clang', '-o', os.join_path(dir, 'probe'),
			os.join_path(dir, 'main.v')])
		assert result.exit_code != 0, 'unexpectedly accepted ${entry[0]}'
		assert result.output.contains(entry[1]), result.output
	}
}

fn test_vml_menu_text_formats_numbers() {
	mut app := NumericTextApp{}
	menus := $vml('numeric_menus.vml')
	assert menus[0].title == '7'
	assert menus[0].items[0].title == '12.5'
	app.ready = false
	updated := $vml('numeric_menus.vml')
	assert updated[0].title == 'waiting'
}

fn test_vml_run_text_formats_numbers() {
	$if ui2_custom_rendering ? {
		mut app := NumericTextApp{}
		label := $vml('numeric_runs.vml')
		assert label.text == '7 / 12.5'
		assert label.text_runs[0].text == '7'
		assert label.text_runs[2].text == '12.5'
	}
}
