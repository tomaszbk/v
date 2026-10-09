module main

import ui2

fn root_references(mut app App) ui2.Element { return $vml('root_refs.vml') }

fn test_import_id_override_keeps_internal_root_references_and_caller_ids() {
	mut app := App{}
	root := root_references(mut app)
	assert root.children[0].frame.width == 77
	for index, width in [f64(100), 200, 77] {
		card := root.children[index + 1]
		assert card.id == ['first', 'second', 'third'][index]
		assert card.frame.width == width
		assert card.frame.height == width + 1
		assert card.children[0].text == 'root=${width}'
		card.children[1].on_event(ui2.ElementEvent{ kind: .tap })
		assert app.level == width
	}
	assert root.children[1].children[0].id != root.children[2].children[0].id
	assert root.children[4].frame.width == 100
	assert root.children[4].frame.height == 201
}
