module parser

fn test_keyed_repeater_captures_only_referenced_geometry_and_callbacks() {
	root := parse_vml_source('Column(id: "outer") {
        View(id: "unrelated", width: 10, height: 20)
        Absolute(id: "list", width: 100, height: 80) {
            Repeater(model: app.rows, key: app.prefix + item.id) {
                Button(width: list.width, text: item.name, on_tap: choose)
            }
        }
    }')!
	mut compiler := VmlCompiler{ uses_app: true, callback_captures: ['choose', 'unused'] }
	generated := compiler.compile(root)
	header := generated.split_into_lines().filter(it.contains('ui2.new_vml_keyed_list['))[0]
	builder := header.all_after('string {').all_after('}, fn [')
	assert builder.contains('mut vml_node_0_1'), builder
	assert builder.contains('vml_collection_0_1_0'), builder
	assert builder.contains('mut vml_geometry_0_1'), builder
	assert builder.contains('choose'), builder
	assert !header.contains('vml_geometry_0,'), header
	assert !header.contains('vml_geometry_0_0'), header
	assert !header.contains('vml_property_0_0_width'), header
	assert !header.contains('vml_property_0_0_height'), header
	assert !header.contains('unused'), header
	assert !builder.contains('mut app'), builder
	assert header.all_after(', fn [').all_before(']').contains('mut app'), header
	for callback in generated.split_into_lines().filter(it.contains('fn [')) {
		assert !callback.contains('[vml_property_0_1_width'), callback
		assert !callback.contains(', vml_property_0_1_width'), callback
	}
}

fn test_bound_input_readers_capture_getters_and_writers_capture_setters() {
	definition := parse_vml_source('component Editor(bind text string = "") {
        computed copy := text
        fn clear() { text = "" }
        Button(text: copy, on_tap: clear)
    }')!
	invocation := parse_vml_source('TextInput(bind.text: app.name)')!
	root := &VmlNode{ ...definition, properties: invocation.properties }
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	reader := generated.split_into_lines().filter(it.contains('.computed['))[0]
	writer := generated.split_into_lines().filter(it.contains('vml_fn_0_clear := fn'))[0]
	assert reader.contains('mut vml_input_0_text'), reader
	assert !reader.contains('vml_set_input_0_text'), reader
	assert writer.contains('vml_set_input_0_text'), writer
	assert !writer.contains('mut vml_input_0_text'), writer
}

fn test_structural_effect_captures_current_inputs_and_event_references() {
	root := parse_vml_source('Column(id: "outer") {
        View(id: "unrelated", width: 10, height: 20)
        ProgressBar(id: "progress", value: app.value, width: app.width)
        ToggleButton(id: "toggle", text: "Toggle", on_tap: choose)
        MessageBox(text: "Confirm") { Button(text: "OK", on_tap: choose) }
    }')!
	mut compiler := VmlCompiler{ uses_app: true, callback_captures: ['choose', 'unused'] }
	generated := compiler.compile(root)
	headers := generated.split_into_lines().filter(it.contains(".structure('@widget',"))
	assert headers.len == 3
	assert headers[0].contains('mut app'), headers[0]
	assert headers[0].contains('mut vml_node_0_1'), headers[0]
	assert headers[0].contains('mut vml_root_component'), headers[0]
	assert !headers[0].contains('vml_property_0_0_width'), headers[0]
	assert !headers[0].contains('vml_geometry_0'), headers[0]
	assert !headers[0].contains('choose'), headers[0]
	assert !headers[0].contains('unused'), headers[0]
	assert !headers[1].contains('mut app'), headers[1]
	assert !headers[1].contains('vml_property_0_0_height'), headers[1]
	assert headers[2].contains('vml_message_action_0_3_0'), headers[2]
}

fn test_nested_repeater_does_not_capture_shadowed_outer_item_or_unused_state() {
	root := parse_vml_source('component List() {
        state selected := 0
        state unused := 0
        Column {
            Repeater(model: app.groups, key: item.id) {
                Repeater(model: item.rows, key: item.id) {
                    Button(text: item.name + "vml_state_0_unused", on_tap: selected = item.id)
                }
            }
        }
    }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	headers := generated.split_into_lines().filter(it.contains('ui2.new_vml_keyed_list['))
	assert headers.len == 2
	inner_builder := headers[1].all_after('string {').all_after('}, fn [')
	assert inner_builder.contains('mut vml_state_0_selected'), inner_builder
	assert !inner_builder.contains('vml_state_0_unused'), inner_builder
	assert !inner_builder.contains('vml_item_signal_0_root_0,'), inner_builder
	assert !inner_builder.contains('mut app'), inner_builder
	inner_key_captures := headers[1].all_after(', fn [').all_before(']')
	assert inner_key_captures == 'vml_collection_0_root_0_0', inner_key_captures
}
