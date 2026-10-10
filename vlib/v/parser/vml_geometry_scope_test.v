module parser

import os

fn test_vml_layout_inputs_reject_element_geometry_outside_absolute() {
	for source in [
		'Screen(id: "root") { View(width: root.width - 32) }',
		'Column(id: "root") { View(height: root.height / 2) }',
		'Row(id: "root") { View(min_width: root.width / 2) }',
		'Row(id: "root") { View(max_height: root.height) }',
		'Row(id: "root") { View(flex_basis: root.width / 2) }',
		'Column(id: "root", gap: root.width / 10) { View }',
		'Grid(id: "root", columns: 2, padding: root.height / 20) { View }',
		'Grid(id: "root", columns: 2, col_default_width: root.width / 2) { View }',
		'Grid(id: "root", columns: 2, row_default_height: root.height / 2) { View }',
		'Column(id: "root", padding_left: app.limit(root.width, 10)) { View }',
		'Screen(id: "root") { View(width: app.wide ? 20 : -root.width) }',
		'Column(id: "root") { Repeater(model: app.rows, key: item.id) { View(width: root.width) } }',
		'Column { Repeater(model: app.rows, key: item.id) { View(width: anchor.width) } View(id: "anchor", width: 20) }',
	] {
		parse_vml_source(source) or {
			assert err.msg().contains('element geometry'), err.msg()
			assert err.msg().contains('parent Absolute'), err.msg()
			continue
		}
		assert false, 'accepted geometry-dependent layout input: ${source}'
	}
	parse_vml_source('Screen(id: "root") {\n    View(width: root.width)\n}') or {
		assert err.msg().contains('line 2, column 10'), err.msg()
		return
	}
	assert false, 'accepted geometry-dependent child width'
}

fn test_vml_absolute_children_allow_geometry_inputs_and_repeater_delegates() {
	parse_vml_source('Absolute(id: "root") {
    Column(width: root.width - 20, gap: root.height / 10, padding: root.width / 20) { View }
    Grid(columns: 2, width: root.width, col_default_width: root.width / 2,
        row_default_height: root.height / 2) { View }
    Repeater(model: app.rows, key: item.id) { View(x: index * 10, width: root.width, height: item.height) }
}')!
	// Preferred-size input belongs to the Absolute child; the probe reads the
	// allocated Flex ancestor through that child without feeding Flex allocation.
	parse_vml_source('Row { Column(id: "content", width: 100, flex_grow: 1) {
    Absolute { Label(text: "width=\${content.width}", width: content.width, height: 20) }
} }')!
}

fn test_vml_model_dimensions_and_viewport_predicates_are_not_layout_geometry() {
	parse_vml_source('Column(id: "root", gap: app.width / 10) {
    View(width: app.width, height: app.size.height, hidden: root.width < 150)
    Grid(columns: root.width < 600 ? 1 : 2, padding: app.padding) { View }
    Repeater(model: app.rows, key: item.id) { View(width: item.width, height: item.height) }
}')!
	parse_vml_source('component Box(size Size) {
    state local := app.size
    Column { View(width: size.width, height: local.height) }
}')!
}

fn test_vml_component_private_ids_do_not_leak_into_caller_layout_scope() {
	parse_vml_source('component Box(root Size) {
    Column { View(width: root.width) }
}')!
	dir := os.join_path(os.vtmp_dir(), 'vml_geometry_private_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	component := os.join_path(dir, 'box.vml')
	document := os.join_path(dir, 'main.vml')
	os.write_file(component, 'component Box() { Absolute(id: "size") { View(width: size.width) } }')!
	os.write_file(os.join_path(dir, 'host.vml'), 'import Box\ncomponent Host(size Size) { Column { Box {} View(width: size.width) } }')!
	os.write_file(document, 'import Host\nScreen(id: "size") { Host(size: app.size) }')!
	parse_compiled_vml_file(document, '', [])!
	os.write_file(component, 'component Box() { Column(id: "root") { View(width: root.width) } }')!
	os.write_file(document, 'import Box\nAbsolute { Box {} }')!
	parse_compiled_vml_file(document, '', []) or {
		assert err.msg().contains('element geometry'), err.msg()
		return
	}
	assert false, 'an outer Absolute must not grant geometry inputs to nested Column children'
}

fn test_vml_slot_geometry_uses_the_author_ids_and_actual_parent_layout() {
	dir := os.join_path(os.vtmp_dir(), 'vml_geometry_slots_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	component := os.join_path(dir, 'card.vml')
	document := os.join_path(dir, 'main.vml')
	os.write_file(component, 'component Card(content slot) { Absolute { Slot {} } }')!
	os.write_file(document, 'import Card\nScreen(id: "root") { Card { View(width: root.width) } }')!
	parse_compiled_vml_file(document, '', [])!
	// A member of the author's component remains data even when the receiving
	// component has an element with the same local name.
	os.write_file(component, 'component Card(content slot) { Column(id: "root") { Slot {} } }')!
	os.write_file(os.join_path(dir, 'host.vml'), 'import Card\ncomponent Host(root Size) { Card { View(width: root.width) } }')!
	os.write_file(document, 'import Host\nScreen { Host(root: app.size) }')!
	parse_compiled_vml_file(document, '', [])!
	os.write_file(component, 'component Card(content slot) { Column { Slot {} } }')!
	os.write_file(document, 'import Card\nScreen(id: "root") { Card { View(width: root.width) } }')!
	parse_compiled_vml_file(document, '', []) or {
		assert err.msg().contains('${os.real_path(document)}:2:34:'), err.msg()
		assert err.msg().contains('element geometry'), err.msg()
		return
	}
	assert false, 'slot content must obey its visual parent in its author scope'
}

fn test_component_invocation_geometry_exports_only_the_root_alias() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_alias_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card() { View(id: "private", width: 100) { Label(id: "caption", text: private.width) } }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Card\nAbsolute { Card(id: "public") View(width: public.width) }')!
	root := parse_compiled_vml_file(document, '', [])!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('(vml_node_0_0.frame() or { panic(err) }).width'), generated
	// The invocation exports one alias; its private root and descendants remain lexical.
	scope := validate_vml_geometry_scope(root.children[0], 'Absolute', VmlScope{}, VmlScope{})!
	assert 'public' in scope.ids && 'private' !in scope.ids && 'caption' !in scope.ids
	for parent in ['Column', 'Row'] {
		os.write_file(document, 'import Card\n${parent} { Card(id: "public") View(width: public.width) }')!
		parse_compiled_vml_file(document, '', []) or {
			assert err.msg().contains('element geometry'), err.msg()
			assert err.msg().contains('parent Absolute'), err.msg()
			continue
		}
		assert false, 'accepted component geometry under ${parent}'
	}
}

fn test_component_invocation_ref_checks_the_real_nested_root_type() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_ref_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card() { View(id: "private") }')!
	os.write_file(os.join_path(dir, 'nested.vml'), 'import Card\ncomponent Nested() { Card {} }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Nested\ncomponent Host() { ref target Button Absolute { Nested(ref: target) } }')!
	root := parse_compiled_vml_file(document, '', [])!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('ref `target` requires Button; received View'), generated
	assert generated.contains('vml_ref_0_target.bind(vml_node_0_root_0)'), generated
}

fn test_imported_positioned_roots_validate_the_actual_invocation_parent() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_parent_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	definition := 'component Positioned(x f64 = 0, y f64 = 0) { View(x: x, y: y, width: 100) }'
	parse_vml_source(definition)!
	os.write_file(os.join_path(dir, 'positioned.vml'), definition)!
	os.write_file(os.join_path(dir, 'nested.vml'), 'import Positioned\ncomponent Nested() { Positioned(x: 12, y: 13) }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Nested\nAbsolute { Nested {} }')!
	parse_compiled_vml_file(document, '', [])!
	for source in ['import Nested\nRow { Nested {} }', 'import Nested\nColumn { Nested {} }',
		'import Nested\nNested {}', definition] {
		os.write_file(document, source)!
		parse_compiled_vml_file(document, '', []) or {
			assert err.msg().contains('x/y require a parent Absolute'), err.msg()
			continue
		}
		assert false, 'accepted positioned component without Absolute: ${source}'
	}
	// Deferring the root never exempts an invalid descendant.
	os.write_file(os.join_path(dir, 'positioned.vml'), 'component Positioned() { Column { View(x: 12) } }')!
	os.write_file(document, 'import Positioned\nAbsolute { Positioned {} }')!
	parse_compiled_vml_file(document, '', []) or {
		assert err.msg().contains('x/y require a parent Absolute'), err.msg()
		return
	}
	assert false, 'accepted a positioned descendant under Column'
}
