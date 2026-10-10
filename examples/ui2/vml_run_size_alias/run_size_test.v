// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
// vtest vflags: -d ui2_custom_rendering
module main

import ui2

@[heap]
pub struct RunSizeApp {
pub mut:
	count int = 19
}

fn run_size_tree(mut app RunSizeApp) ui2.Element {
	return $vml('runs.vml', ui2.rect(0, 0, 300, 120))
}

fn test_static_run_size_alias_overrides_inherited_font_size() ! {
	mut app := &RunSizeApp{}
	initial := run_size_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	assert root.element().children[0].text_runs.map(it.style.size) == [f64(28), 18, 12]
	assert root.element().children[0].text == 'InheritedStaticFont size'
	root.element().children[2].on_event(ui2.ElementEvent{ kind: .click })
	assert root.element().children[0].text_runs.map(it.style.size) == [f64(28), 18, 12]
}

fn test_dynamic_run_size_alias_overrides_inherited_font_size_without_recreating_nodes() ! {
	mut app := &RunSizeApp{}
	initial := run_size_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	static_node := root.element().children[0].compiled_node
	dynamic_node := root.element().children[1].compiled_node
	for count in [19, 21, 23] {
		current := root.element()
		assert current.children[0].compiled_node == static_node
		assert current.children[1].compiled_node == dynamic_node
		assert current.children[1].text_runs.map(it.style.size) == [f64(count), f64(count) / 2]
		assert current.children[1].text == 'InheritedDynamic'
		assert app.count == count
		current.children[2].on_event(ui2.ElementEvent{ kind: .click })
	}
}
