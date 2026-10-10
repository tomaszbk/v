module main

import os
import ui2

fn event(kind ui2.ElementEventKind) ui2.ElementEvent { return ui2.ElementEvent{ kind: kind } }

fn test_compiled_outputs_and_events_match_declarations() {
	mut app := App{ rows: [Row{1, 'niño'}, Row{2, 'café'}] }
	compiled := parity(mut app)
	assert compiled.children.len == 5
	assert compiled.children.map(it.kind) == [ui2.Kind.label, .button, .button, .text_field, .button]
	assert compiled.children.map(it.text) == ['Imported', 'niño', 'café', app.message, 'Increment']
	assert compiled.children.map(it.key) == ['', '1', '2', '', '']
	assert compiled.children.map(it.frame) == [ui2.rect(0, 0, 280, 28), ui2.rect(0, 0, 100, 32),
		ui2.rect(0, 0, 100, 32), ui2.rect(0, 0, 180, 32), ui2.rect(0, 0, 100, 32)]
	compiled.children[2].on_event(event(.tap))
	compiled.children[4].on_event(event(.tap))
	compiled.children[3].on_event(ui2.ElementEvent{ kind: .change, text: 'mañana ñ' })
	assert app.selected == 2 && app.count == 1
	assert app.message == 'mañana ñ' && app.copied == 'mañana ñ'
}

fn test_keyed_rows_keep_ids_and_callbacks_across_reorder() {
	mut app := App{ rows: [Row{1, 'niño'}, Row{2, 'café'}] }
	before := build(mut app)
	app.rows.reverse_in_place()
	app.count = 123
	before.compiled_node.component.invalidate_app() or { panic(err) }
	after := before.compiled_node.element()
	assert before.children[2].key == after.children[3].key
	assert before.children[2].id == after.children[3].id
	for index, child in before.children[2].children {
		assert child.id == after.children[3].children[index].id
	}
	assert before.children[0].children[0].id != before.children[1].children[0].id
	after.children[3].children[1].on_event(event(.tap))
	assert app.selected == 1
	after.children[2].children[2].on_event(event(.tap))
	assert app.selected == 2
	// An action reads the live model, even when invoked through an older tree.
	before.children[5].on_event(event(.tap))
	assert app.count == 124
}

fn test_nested_keys_encode_segments_without_separator_collisions() {
	mut app := App{ groups: [Group{'a/b', [Row{1, 'first'}]}, Group{'a', [Row{1, 'second'}]}] }
	root := nested(mut app)
	assert root.children.len == 2
	assert root.children[0].key != root.children[1].key
	assert root.children[0].id != root.children[1].id
	root.children[1].on_event(event(.tap))
	assert app.selected == 1
	app.groups.reverse_in_place()
	root.compiled_node.component.invalidate_app() or { panic(err) }
	after := root.compiled_node.element()
	assert root.children[0].id == after.children[1].id
}

fn test_menus_match_public_api_and_route_typed_actions() {
	mut app := App{}
	actual := menus(mut app)
	assert actual.len == 1 && actual[0].title == 'File'
	assert actual[0].items[0].id == 'create'
	assert actual[0].items[0].title == 'New' && actual[0].items[0].shortcut == 'cmd+n'
	assert actual[0].items[1].separator
	assert actual[0].items[2].title == 'Selection'
	assert actual[0].items[2].items[0].checked
	assert !actual[0].items[2].items[1].enabled
	actual[0].items[0].on_select(event(.tap))
	actual[0].items[2].items[0].on_select(event(.tap))
	assert app.count == 1 && app.selected == 7
}

fn test_interface_and_pointer_arrays_check_declared_schemas_when_empty() {
	mut app := App{}
	assert schemas(mut app).children.len == 0
	app.interface_rows = [RowContract(Row{3, 'niño'})]
	app.pointer_rows = [&Row{4, 'café'}]
	root := schemas(mut app)
	assert root.children.len == 2
	assert root.children[0].text == 'niño' && root.children[0].key == '3'
	assert root.children[1].text == 'café' && root.children[1].key == '4'
	root.children[1].on_event(event(.tap))
	assert app.selected == 4
}

fn test_boolean_numeric_and_text_bindings_run_before_assignment_and_action() {
	mut app := App{}
	compiled := bindings(mut app)
	compiled.children[0].on_event(ui2.ElementEvent{ kind: .change, checked: true })
	assert app.enabled && app.checked_copy
	compiled.children[1].on_event(ui2.ElementEvent{ kind: .change, checked: false })
	assert !app.enabled && !app.checked_copy
	compiled.children[2].on_event(ui2.ElementEvent{ kind: .change, value: 73.5 })
	assert app.level == 73.5 && app.last_level == 73.5
	compiled.children[3].on_event(ui2.ElementEvent{ kind: .change, text: 'niño café' })
	assert app.message == 'niño café' && app.copied == 'niño café'
	compiled.children[4].on_event(ui2.ElementEvent{ kind: .change, value: 7.25 })
	assert app.quantity == 7 && app.last_quantity == 7
	compiled.children[3].on_event(event(.submit))
	assert app.count == 1
}

fn test_invalid_keys_fail_before_a_tree_reaches_the_backend() {
	bin := os.join_path(os.vtmp_dir(), 'vml_structure_invalid_keys_${os.getpid()}')
	defer { os.rm(bin) or {} }
	compile := os.exec([@VEXE, '-b', 'c', '-gc', 'boehm', '-nocache', '-cc', 'clang',
		'-no-retry-compilation', '-d', 'ui2_headless', '-o', bin, @DIR])
	assert compile.exit_code == 0, compile.output
	for option, message in {
		'--duplicate-key':     'duplicate compiled VML list key'
		'--empty-key':         'compiled VML list key cannot be empty'
		'--duplicate-sibling': 'duplicate sibling key'
	} {
		result := os.exec([bin, option])
		assert result.exit_code != 0, result.output
		assert result.output.contains(message), result.output
		assert result.output.contains('.vml:'), result.output
	}
}

fn test_named_v_callback_keeps_binding_payload() {
	mut app := App{}
	root := named_binding(mut app)
	root.on_event(ui2.ElementEvent{ kind: .change, text: 'niño' })
	assert app.message == 'niño'
}
