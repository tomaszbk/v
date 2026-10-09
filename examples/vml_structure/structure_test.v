module main

import os
import ui2

fn event(kind ui2.ElementEventKind) ui2.ElementEvent { return ui2.ElementEvent{ kind: kind } }

fn test_compiled_runtime_outputs_and_events_match() {
	mut app := App{ rows: [Row{1, 'niño'}, Row{2, 'café'}] }
	mut runtime := ui2.new_vml_app_file(os.join_path(@DIR, 'parity.vml'), app)!
	compiled := parity(mut app)
	interpreted := runtime.build(ui2.bounds())!
	assert compiled.children.len == interpreted.children.len
	for i, child in compiled.children {
		other := interpreted.children[i]
		assert child.kind == other.kind
		assert child.text == other.text
		assert child.key == other.key
		assert child.frame == other.frame
	}
	for i in [1, 2, 4] {
		compiled.children[i].on_event(event(.tap))
		interpreted.children[i].on_event(event(.tap))
	}
	compiled.children[3].on_event(ui2.ElementEvent{ kind: .change, text: 'mañana ñ' })
	interpreted.children[3].on_event(ui2.ElementEvent{ kind: .change, text: 'mañana ñ' })
	assert app.selected == runtime.state().selected
	assert app.count == runtime.state().count
	assert app.message == runtime.state().message
	assert app.copied == runtime.state().copied
}

fn test_keyed_rows_keep_ids_and_callbacks_across_reorder() {
	mut app := App{ rows: [Row{1, 'niño'}, Row{2, 'café'}] }
	before := build(mut app)
	app.rows.reverse_in_place()
	app.count = 123
	after := build(mut app)
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
	after := nested(mut app)
	assert root.children[0].id == after.children[1].id
}

fn test_menus_match_public_api_and_route_typed_actions() {
	mut app := App{}
	actual := menus(mut app)
	expected := ui2.menu_bar_from_vml('MenuBar { Menu { title: "File" MenuItem { id: create text: "New" shortcut: "cmd+n" } MenuSeparator {} Menu { title: "Selection" MenuItem { id: choose text: "Choose" checked: true } MenuItem { id: disabled text: "Disabled" enabled: false } } } }')!
	assert actual[0].title == expected[0].title
	assert actual[0].items[0].id == expected[0].items[0].id
	assert actual[0].items[0].shortcut == expected[0].items[0].shortcut
	assert actual[0].items[1].separator
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
	runtime := ui2.element_from_vml_model_file(os.join_path(@DIR, 'schemas.vml'), app, ui2.bounds())!
	assert root.children.len == 2
	for index, child in root.children {
		assert child.text == runtime.children[index].text
		assert child.key == runtime.children[index].key
	}
	root.children[1].on_event(event(.tap))
	assert app.selected == 4
}

fn test_boolean_numeric_and_text_bindings_run_before_assignment_and_action() {
	mut app := App{}
	mut runtime := ui2.new_vml_app_file(os.join_path(@DIR, 'bindings.vml'), app)!
	compiled := bindings(mut app)
	interpreted := runtime.build(ui2.bounds())!
	payloads := [
		ui2.ElementEvent{ kind: .change, checked: true },
		ui2.ElementEvent{ kind: .change, checked: false },
		ui2.ElementEvent{ kind: .change, value: 73.5 },
		ui2.ElementEvent{ kind: .change, text: 'niño café' },
		ui2.ElementEvent{ kind: .change, value: 7.25 },
	]
	for index, payload in payloads {
		compiled.children[index].on_event(payload)
		interpreted.children[index].on_event(payload)
		assert app.enabled == runtime.state().enabled
		assert app.checked_copy == runtime.state().checked_copy
		assert app.level == runtime.state().level
		assert app.last_level == runtime.state().last_level
		assert app.message == runtime.state().message
		assert app.copied == runtime.state().copied
		assert app.quantity == runtime.state().quantity
		assert app.last_quantity == runtime.state().last_quantity
	}
	compiled.children[3].on_event(event(.submit))
	interpreted.children[3].on_event(event(.submit))
	assert app.count == 1 && app.count == runtime.state().count
}

fn test_invalid_keys_fail_before_a_tree_reaches_the_backend() {
	bin := os.join_path(os.vtmp_dir(), 'vml_structure_invalid_keys_${os.getpid()}')
	defer { os.rm(bin) or {} }
	compile := os.exec([@VEXE, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', 'clang',
		'-no-retry-compilation', '-d', 'ui2_headless', '-o', bin, @DIR])
	assert compile.exit_code == 0, compile.output
	for option, message in {
		'--duplicate-key':     'duplicate Repeater key'
		'--empty-key':         'Repeater key cannot be empty'
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
