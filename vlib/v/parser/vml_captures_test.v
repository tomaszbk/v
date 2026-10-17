module parser

import vml

fn test_keyed_repeater_captures_only_referenced_geometry_and_callbacks() {
	root := parse_vml_source('Column(id: "outer") {
        View(id: "unrelated", width: 10, height: 20)
        Absolute(id: "list", width: 100, height: 80) {
            Repeater(model: app.rows, key: app.prefix + item.id) {
                Button(width: list.width, text: item.name, on_click: choose)
            }
        }
    }')!
	mut compiler := VmlCompiler{ uses_app: true, callback_captures: ['choose', 'unused'] }
	generated := compiler.lower(root)
	header := generated.split_into_lines().filter(it.contains('ui2.vml_repeat('))[0]
	model := header.all_after('ui2.vml_repeat(').all_after('fn [').all_before(']')
	key := header.all_after('return app.rows }').all_after('fn [').all_before(']')
	builder := header.all_after('string {').all_after('}, fn [').all_before(']')
	assert model.split(', ').sorted() == ['mut app', 'mut vml_root_component'], model
	assert key.split(', ').sorted() == ['mut app', 'vml_collection_0_1_0'], key
	// Items read the list's geometry and the callback; nothing else is captured.
	assert builder.split(', ').sorted() == ['choose', 'vml_collection_0_1_0', 'vml_node_0_1'], builder
}

fn test_bound_input_readers_capture_getters_and_writers_capture_setters() {
	definition := parse_vml_source('component Editor(bind text string = "") {
        computed copy := text
        fn clear() { text = "" }
        Button(text: copy, on_click: clear)
    }')!
	invocation := parse_vml_source('TextInput(bind.text: app.name)')!
	root := &vml.Node{ ...definition, properties: invocation.properties }
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	reader := generated.split_into_lines().filter(it.contains('.computed[') && it.contains("('copy'"))[0]
	writer := generated.split_into_lines().filter(it.contains('vml_fn_0_clear := fn'))[0]
	assert reader.contains('mut vml_input_0_text'), reader
	assert !reader.contains('vml_set_input_0_text'), reader
	assert writer.contains('vml_set_input_0_text'), writer
	assert !writer.contains('mut vml_input_0_text'), writer
}

fn test_nested_repeater_does_not_capture_shadowed_outer_item_or_unused_state() {
	root := parse_vml_source('component List() {
        state selected := 0
        state unused := 0
        Column {
            Repeater(model: app.groups, key: item.id) {
                Repeater(model: item.rows, key: item.id) {
                    Button(text: item.name + "vml_state_0_unused", on_click: selected = item.id)
                }
            }
        }
    }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	headers := generated.split_into_lines().filter(it.contains('ui2.vml_repeat('))
	assert headers.len == 2
	inner_builder := headers[1].all_after('string {').all_after('}, fn [').all_before(']')
	assert inner_builder.contains('mut vml_state_0_selected'), inner_builder
	assert !inner_builder.contains('vml_state_0_unused'), inner_builder
	assert !inner_builder.contains('vml_item_signal_0_root_0,'), inner_builder
	assert !inner_builder.contains('mut app'), inner_builder
	inner_key_captures := headers[1].all_after(' { return ').all_after('fn [').all_before(']')
	assert inner_key_captures == 'vml_collection_0_root_0_0', inner_key_captures
}
