// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
module main

import ui2

@[heap]
pub struct ComputedApp {
pub mut:
	name          string = 'niñez'
	caption_calls int
	seed_calls    int
	unused_calls  int
}

// caption records each evaluation of the shared lazy memo.
pub fn (mut app ComputedApp) caption() string {
	app.caption_calls++
	return app.name
}

// seed records initialization of component state.
pub fn (mut app ComputedApp) seed() int {
	app.seed_calls++
	return 10
}

// unused records evaluation of a memo with no consumer.
pub fn (mut app ComputedApp) unused() int {
	app.unused_calls++
	return 99
}

fn computed_app_tree(mut app ComputedApp) ui2.Element {
	return $vml('view.vml', ui2.rect(0, 0, 240, 160))
}

fn test_computed_app_reads_refresh_after_binding_and_external_invalidation() ! {
	mut app := &ComputedApp{}
	initial := computed_app_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	assert initial.children.map(it.text) == ['niñez', 'niñez', 'niñez', '10', '0']
	assert app.caption_calls == 1 && app.seed_calls == 1 && app.unused_calls == 0

	initial.children[2].on_event(ui2.ElementEvent{ kind: .change, text: 'canción' })
	assert app.name == 'canción'
	bound := root.element()
	assert bound.children.map(it.text) == ['canción', 'canción', 'canción', '10', '0']
	assert app.caption_calls == 2 && app.seed_calls == 1 && app.unused_calls == 0

	app.name = 'mañana'
	root.component.invalidate_app()!
	external := root.element()
	assert external.children.map(it.text) == ['mañana', 'mañana', 'mañana', '10', '0']
	assert app.caption_calls == 3 && app.seed_calls == 1 && app.unused_calls == 0

	external.children[4].on_event(ui2.ElementEvent{ kind: .click })
	local := root.element()
	assert local.children[4].text == '2'
	assert app.seed_calls == 1 && app.unused_calls == 0
	for index, child in initial.children {
		assert bound.children[index].compiled_node == child.compiled_node
		assert external.children[index].compiled_node == child.compiled_node
		assert local.children[index].compiled_node == child.compiled_node
		assert local.children[index].id == child.id
	}
}
