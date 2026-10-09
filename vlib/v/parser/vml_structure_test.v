module parser

import os
import v.pref

fn test_vml_interpolated_paths_keep_physical_string_locations() {
	root := parse_vml_source('View {\n    Label(text: "prefix\\\\n\${app.first}\n\${app.second}")\n}')!
	expression := root.children[0].properties[0].expr
	first := expression.parts[1].expr
	second := expression.parts[3].expr
	assert first.value == 'app.first'
	assert first.line == 2 && first.column == 29
	assert second.value == 'app.second'
	assert second.line == 3 && second.column == 3
}

fn test_vml_assignments_lower_only_writable_sources() {
	root := parse_vml_source('View { Button(on_tap: app.count++) }')!
	assert root.children[0].properties[0].expr.kind == .assignment
	for source in ['Label(text: app.count = 1)', 'TextInput(on_text: app.save())'] {
		if _ := parse_vml_source(source) {
			assert false, source
		}
	}
	for target in ['item.count', 'app.nested.count'] {
		parse_vml_source('Button(on_tap: ${target} = 1)') or {
			assert err.msg().contains('assignment target `${target}` is read-only'), err.msg()
			continue
		}
		assert false, 'accepted read-only assignment target `${target}`'
	}
}

fn test_vml_imports_expand_component_signatures_and_lexical_slots() {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_imports_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'caption.vml'), 'component Caption(text string = "default") { Label(id: "caption", text: text) }')!
	os.write_file(os.join_path(dir, 'card.vml'), 'import Caption\ncomponent Card(content slot) { View { Caption(text: "nested") Slot {} } }')!
	path := os.join_path(dir, 'main.vml')
	os.write_file(path, 'import Card\nView { Card(id: "first") { Label(text: app.title) } Card(id: "second") }')!
	root := parse_compiled_vml_file(path, '', [])!
	assert root.children.len == 2
	first := root.children[0]
	assert first.tag == '__Component' && first.component_name == 'Card'
	assert first.id == 'first'
	assert first.children[0].children.len == 2
	caption := first.children[0].children[0]
	assert caption.component_name == 'Caption'
	assert caption.children[0].source == os.real_path(os.join_path(dir, 'caption.vml'))
	assert first.children[0].children[1].caller_content
	assert root.children[1].children[0].children.len == 1
	os.write_file(os.join_path(dir, 'caption.vml'), 'component Wrong() { Label }')!
	parse_compiled_vml_file(path, '', []) or {
		assert err.msg().contains('component Caption')
		return
	}
	assert false, 'signature mismatch was accepted'
}

fn test_vml_import_cycle_reports_chain() {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_cycle_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'first.vml'), 'import Second\ncomponent First() { View { Second } }')!
	os.write_file(os.join_path(dir, 'second.vml'), 'import First\ncomponent Second() { View { First } }')!
	parse_compiled_vml_file(os.join_path(dir, 'first.vml'), '', []) or {
		assert err.msg().contains('cyclic VML import')
		assert err.msg().contains('first.vml') && err.msg().contains('second.vml')
		return
	}
	assert false, 'cycle was accepted'
}

fn test_vml_component_reuse_keeps_private_ids_and_source_locations() {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_positions_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'card.vml'), 'component Card(title string) {\n    View(id: "card") { Label(text: title) }\n}')!
	os.write_file(os.join_path(dir, 'main.vml'), 'import Card\nView { Card(id: "first", title: "one") Card(id: "second", title: "two") }')!
	root := parse_compiled_vml_file(os.join_path(dir, 'main.vml'), '', [])!
	for child in root.children {
		assert child.children[0].id == 'card'
		assert child.children[0].line == 2
		assert child.inputs[0].name == 'title'
	}
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains(".child('0.0')")
	assert generated.contains(".child('0.1')")
	assert compiler.locations.any(it.path.ends_with('card.vml') && it.line == 2)
}

fn test_vml_generated_item_paths_keep_import_source_location() {
	dir := os.join_path(os.vtmp_dir(), 'vml_component_item_positions_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'list.vml'), 'component List() {\n View { Repeater(model: app.items, key: item.id) { Label(text: item.missing) } }\n}')!
	os.write_file(os.join_path(dir, 'main.vml'), 'import List\nView { List }')!
	path := os.join_path(dir, 'main.v')
	os.write_file(path, "module main\nimport ui2\nfn build(mut app App) ui2.Element { return \$vml('main.vml') }\n")!
	mut parser := Parser.new(pref.new_preferences())
	ast := parser.parse_file(path)
	assert parser.diagnostics.len == 0, parser.diagnostics.str()
	assert ast.nodes.any(it.kind == .ident && it.value.starts_with('vml_item_'))
}

fn test_vml_inferred_types_relocate_every_nested_expression_link() {
	assert shift_vml_inferred_type('![]&ui2.Signal[typeof(__vml_expr_12)]', 100) == '![]&ui2.Signal[typeof(__vml_expr_112)]'
	assert shift_vml_inferred_type('fn(typeof(__vml_expr_1)) typeof(__vml_expr_22)', 10) == 'fn(typeof(__vml_expr_11)) typeof(__vml_expr_32)'
	assert shift_vml_inferred_type('[]int', 10) == '[]int'
}
