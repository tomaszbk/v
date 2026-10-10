// vtest vflags: -d ui2_custom_rendering
module main

import ui2

struct CompositionRow {
pub:
	id   int
	name string
}

struct CompositionGroup {
pub:
	id   int
	rows []CompositionRow
}

@[heap]
struct CompositionApp {
pub mut:
	rows     []CompositionRow
	groups   []CompositionGroup
	observed f64
	extra    f64
}

fn import_layout_scope() ui2.Element { return $vml('import_layout_scope.vml') }

fn measured_sibling_capture(mut app CompositionApp) ui2.Element {
	return $vml('measured_sibling_capture.vml')
}

fn repeater_placement(mut app CompositionApp) ui2.Element {
	return $vml('repeater_placement.vml')
}

fn repeater_scaled(mut app CompositionApp) ui2.Element {
	return $vml('repeater_scaled.vml')
}

fn test_imported_layouts_export_their_root_and_preserve_caller_refs() {
	root := import_layout_scope()
	assert root.children[1].id.len == 0
	assert root.children[3].id.len == 0
	assert root.children[1].children[0].id != 'private'
	assert root.children[3].children[0].id != root.children[1].children[0].id
	assert root.children[2].frame == ui2.rect(0, 0, 23, 29)
	assert root.children[4].frame == ui2.rect(0, 0, 23, 29)
	assert root.children[5].frame == ui2.rect(0, 0, 100, 40)
}

fn test_measured_geometry_callbacks_keep_imported_and_repeated_row_values() {
	mut app := &CompositionApp{ rows: [CompositionRow{7, 'ñ'}, CompositionRow{9, 'Niñez'}] }
	root := measured_sibling_capture(mut app)
	app.extra = 100
	root.children[0].children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.observed == root.children[0].children[0].frame.width + 100
	for row in root.children[1..] {
		row.children[1].on_event(ui2.ElementEvent{ kind: .tap })
		assert app.observed == row.children[0].frame.width + 100
	}
	retained := root.children[1].children[1].on_event
	width := root.children[1].children[0].frame.width
	app.rows.reverse_in_place()
	root.compiled_node.component.invalidate_app() or { panic(err) }
	reordered := root.compiled_node.element()
	assert reordered.children[2].id == root.children[1].id
	app.rows = []CompositionRow{}
	app.extra = 200
	retained(ui2.ElementEvent{ kind: .tap })
	assert app.observed == width + 200
}

fn test_repeaters_preserve_absolute_intrinsic_placement_and_explicit_zero() {
	rows := [CompositionRow{7, 'first'}, CompositionRow{9, 'second'}]
	mut app := &CompositionApp{ rows: rows, groups: [CompositionGroup{1, rows}] }
	root := repeater_placement(mut app)
	first := root.children[0].frame
	assert first.width > 0 && first.width < 300
	assert first.height > 0 && first.height < 200
	assert root.children.len == 9
	for index in 1 .. 5 {
		frame := root.children[index].frame
		assert frame.width == first.width && frame.height == first.height
		assert frame.x == f64((index - 1) % 2) * 10 && frame.y == 0
	}
	for child in root.children[5..7] {
		assert child.frame.width == 0 && child.frame.height == 0
	}
	assert root.children[5..7].map(it.key) == ['zero-7', 'zero-9']
	direct := root.children[7]
	repeated := root.children[8]
	assert repeated.frame == direct.frame
	for child in repeated.children {
		assert child.frame == direct.children[0].frame
	}
}

fn test_repeaters_receive_scaled_logical_content_and_keep_explicit_zero() {
	rows := [CompositionRow{7, 'first'}, CompositionRow{9, 'second'}]
	mut app := &CompositionApp{ rows: rows, groups: [CompositionGroup{1, rows}] }
	root := repeater_scaled(mut app)
	assert root.frame == ui2.rect(0, 0, 400, 300)
	assert root.content_size == ui2.LayoutSize{ width: 800, height: 600 }
	assert root.children.len == 7
	for child in root.children[..5] {
		assert child.frame == ui2.rect(0, 0, 800, 600)
	}
	for child in root.children[5..] {
		assert child.frame == ui2.rect(0, 0, 0, 0)
	}
	assert root.children[5..].map(it.key) == ['zero-7', 'zero-9']
}
