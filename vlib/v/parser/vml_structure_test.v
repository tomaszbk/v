module parser

import os
import v.pref

fn test_vml_interpolated_paths_keep_physical_string_locations() {
	source := 'View {\n Label { text: "prefix\\n\${app.first}\n\${app.second}" }\n}'
	root := parse_vml_source(source)!
	expr := root.children[0].properties[0].expr
	first := expr.parts[1].expr
	second := expr.parts[3].expr
	assert first.value == 'app.first'
	assert first.line == 2 && first.column == 27
	assert second.value == 'app.second'
	assert second.line == 3 && second.column == 3
}

fn test_vml_assignments_are_only_event_expressions() {
	root := parse_vml_source('View { Button { on_tap: app.count = app.count + 1 } }')!
	assert root.children[0].properties[0].expr.kind == .assignment
	for source in ['Label { text: app.count = 1 }', 'Button { on_tap: item.count = 1 }',
		'Button { on_tap: app.nested.count = 1 }', 'TextInput { multiline: false on_text: app.save() }'] {
		if _ := parse_vml_source(source) {
			assert false, source
		}
	}
}

fn test_vml_imports_expand_nested_modules_and_overrides() {
	dir := os.join_path(os.vtmp_dir(), 'vml_structure_imports_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'caption.vml'), 'module Caption\nLabel { id: caption text: "default" }')!
	os.write_file(os.join_path(dir, 'card.vml'), 'module Card\nimport Caption\nView { Caption { text: "nested" } }')!
	path := os.join_path(dir, 'main.vml')
	os.write_file(path, 'import Card\nView { Card { id: first Label { text: "appended" } } Card { id: second } }')!
	root := parse_compiled_vml_file(path, '', [])!
	assert root.children.len == 2
	assert root.children[0].imported
	assert root.children[0].id == 'first'
	assert root.children[0].children.len == 2
	assert root.children[1].children.len == 1
	assert root.children[0].children[0].properties[1].expr.value == 'nested'
	assert root.children[0].children[0].source == os.real_path(os.join_path(dir, 'caption.vml'))
	os.write_file(os.join_path(dir, 'caption.vml'), 'module Wrong\nLabel {}')!
	parse_compiled_vml_file(path, '', []) or {
		assert err.msg().contains('module Caption')
		return
	}
	assert false, 'module mismatch was accepted'
}

fn test_vml_import_cycle_reports_chain() {
	dir := os.join_path(os.vtmp_dir(), 'vml_structure_cycle_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'first.vml'), 'module First\nimport Second\nView { Second {} }')!
	os.write_file(os.join_path(dir, 'second.vml'), 'module Second\nimport First\nView { First {} }')!
	parse_compiled_vml_file(os.join_path(dir, 'first.vml'), '', []) or {
		assert err.msg().contains('cyclic VML import')
		assert err.msg().contains('first.vml') && err.msg().contains('second.vml')
		return
	}
	assert false, 'cycle was accepted'
}

fn test_vml_imports_keep_the_defining_documents_module_scope() {
	dir := os.join_path(os.vtmp_dir(), 'vml_structure_scoped_imports_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'module Card\nView { Label { text: "inside" } }')!
	os.write_file(os.join_path(dir, 'label.vml'), 'module Label\nView { Button { text: "outside" } }')!
	os.write_file(os.join_path(dir, 'main.vml'), 'import Card\nimport Label\nView { Card { Label {} } Label {} }')!
	root := parse_compiled_vml_file(os.join_path(dir, 'main.vml'), '', [])!
	assert root.children[0].children[0].tag == 'Label'
	assert root.children[0].children[1].tag == 'View'
	assert root.children[0].children[1].children[0].tag == 'Button'
	assert root.children[1].children[0].tag == 'Button'
}

fn test_vml_generated_item_paths_keep_import_source_location() {
	dir := os.join_path(os.vtmp_dir(), 'vml_structure_positions_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'list.vml'), 'module List\nView {\n Repeater { model: app.items key: item.id\n Label { text: item.missing }\n }\n}')!
	os.write_file(os.join_path(dir, 'main.vml'), 'import List\nView { List {} }')!
	path := os.join_path(dir, 'main.v')
	os.write_file(path, "module main\nimport ui2\nfn build(mut app App) ui2.Element { return \$vml('main.vml') }\n")!
	mut parser := Parser.new(pref.new_preferences())
	ast := parser.parse_file(path)
	assert parser.diagnostics.len == 0, parser.diagnostics.str()
	mut found := false
	for node in ast.nodes {
		if node.kind == .ident && node.value.starts_with('vml_item_') {
			if location := ast.source_position(node.pos) {
				if location.filename.ends_with('list.vml') && location.line == 4 { found = true }
			}
		}
	}
	assert found, 'item path must point to imported VML'
}
