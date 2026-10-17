module parser

import os

// Element ids name nodes in their lexical scope: `id.width` reads the node's
// reactive geometry, a component invocation exports only its own id, and
// slot content keeps the ids of the document that wrote it.
fn test_component_invocation_geometry_exports_only_the_root_alias() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_alias_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card() { View(id: "private", width: 100) { Label(id: "caption", text: private.width) } }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Card\nAbsolute { Card(id: "public") View(width: public.width, height: private.height) }')!
	root := parse_vml_file(document)!
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains('(vml_node_0_0_root.geometry() or { panic(err) }).width'), generated
	// The private id stays inside the component: the caller's path is left to V.
	assert generated.contains('\t\theight: private.height\n'), generated
	assert generated.contains('vml_p.text = (vml_node_0_0_root.geometry() or { panic(err) }).width'), generated
}

fn test_slot_content_reads_the_ids_of_its_author() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_geometry_slots_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card(content slot) { Absolute(id: "root") { Slot {} } }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Card\nScreen(id: "root") { Card { View(width: root.width) } }')!
	root := parse_vml_file(document)!
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains('mut vml_slot_component_0_0_root_0 := vml_root_component.slot_child(mut vml_component_0_0, '), generated
	assert generated.contains('vml_p.width = (vml_node_0.geometry() or { panic(err) }).width'), generated
	assert !generated.contains('vml_p.width = (vml_node_0_0_root.geometry()'), generated
}

// A ref binds the actual root node of a component invocation; V checks that
// the ref's props type matches the node's.
fn test_component_invocation_ref_binds_the_real_nested_root() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_ref_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card() { View(id: "private") }')!
	os.write_file(os.join_path(dir, 'nested.vml'), 'import Card\ncomponent Nested() { Card {} }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Nested\ncomponent Host() { ref target Button Absolute { Nested(ref: target) } }')!
	root := parse_vml_file(document)!
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains("mut vml_ref_0_target := vml_component_0.ref[ui2.ButtonProps]('target') or { panic(err) }"), generated
	assert generated.contains('vml_ref_0_target.bind_widget(mut vml_node_0_root_0_root_root) or { panic(err) }'), generated
}

// Positioned children are a parent rule: the guard names the actual parent of
// an imported root.
fn test_imported_positioned_roots_guard_the_actual_invocation_parent() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_parent_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'positioned.vml'), 'component Positioned(x f64 = 0, y f64 = 0) { View(x: x, y: y, width: 100) }')!
	os.write_file(os.join_path(dir, 'nested.vml'), 'import Positioned\ncomponent Nested() { Positioned(x: 12, y: 13) }')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Nested\nRow { Nested {} }')!
	root := parse_vml_file(document)!
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains('ui2.vml_guard_positioned[ui2.RowProps]()'), generated
	assert generated.contains('ui2.vml_guard_child[ui2.RowProps, ui2.ViewProps]()'), generated
}
