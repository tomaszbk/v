module main

import ui2

fn root_references(mut app App) ui2.Element { return $vml('root_refs.vml') }

fn test_component_ids_export_geometry_and_preserve_private_root_ids() {
	mut app := App{}
	root := root_references(mut app)
	assert root.children[0].frame.width == 77
	root_ids := root.children[1..4].map(it.id)
	assert root_ids[0] != root_ids[1] && root_ids[1] != root_ids[2]
	assert root_ids[0] != root_ids[2]
	for index, width in [f64(100), 200, 77] {
		card := root.children[index + 1]
		assert card.id.len > 0
		assert card.id !in ['first', 'second', 'third']
		assert card.frame.width == width
		assert card.frame.height == width + 1
		assert card.children[0].text == 'root=${width}'
		card.children[1].on_event(ui2.ElementEvent{ kind: .tap })
		assert app.level == width
	}
	assert root.children[1].children[0].id != root.children[2].children[0].id
	assert root.children[4].frame.width == 100
	assert root.children[4].frame.height == 201
	updated := root.compiled_node.element()
	assert updated.children[1..4].map(it.id) == root_ids
	for index in 1 .. 4 {
		assert updated.children[index].compiled_node == root.children[index].compiled_node
	}
}
