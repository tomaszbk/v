module parser

fn test_vml_component_signature_state_handlers_lifecycle_slots_and_refs_parse_together() {
	root := parse_vml_source('component Counter(title string = "Count", changed event(value int), bind text string = "", content slot) {
        state count := 0
        computed doubled := count * 2
        ref submit Button
        fn increment(step int) { count = count + step; changed(count) }
        mount { app.mounted() }
        unmount { app.unmounted() }
        cleanup { app.cleaned() }
        Column(id: "panel") {
            Label(text: doubled)
            Button(ref: submit, text: title, on_click: increment(1))
            TextInput(bind.text: text)
            Slot {}
        }
    }')!
	assert root.component_name == 'Counter'
	assert root.inputs.map(it.name) == ['title', 'changed', 'text', 'content']
	assert root.inputs[0].default_value.value == 'Count'
	assert root.inputs[1].typ == 'event'
	assert root.inputs[1].parameters[0].name == 'value'
	assert root.inputs[1].parameters[0].typ == 'int'
	assert root.inputs[2].bindable
	assert root.inputs[2].typ == 'string'
	assert root.inputs[3].typ == 'slot'
	assert root.data.map(it.name) == ['count', 'doubled']
	assert !root.data[0].computed
	assert root.data[0].expr.kind == .literal
	assert root.data[1].computed
	assert root.data[1].expr.kind == .binary
	assert root.refs[0].name == 'submit'
	assert root.refs[0].typ == 'Button'
	assert root.functions[0].name == 'increment'
	assert root.functions[0].parameters[0].name == 'step'
	assert root.functions[0].parameters[0].typ == 'int'
	assert root.functions[0].body[0].kind == .assignment
	assert root.functions[0].body[1].kind == .call
	assert root.mount.len == 1
	assert root.unmount.len == 1
	assert root.cleanup.len == 1
	assert root.children.len == 1
	assert root.children[0].children.len == 4
}

fn test_vml_component_namespace_rejects_shadowing_across_declarations_ids_and_parameters() {
	for entry in [
		['component Bad(app string) { View }', 'duplicate/reserved component member `app`'],
		['component Bad(count int) { state count := 0 View }',
			'duplicate/reserved component member `count`'],
		['component Bad() { state reset := 0 fn reset() {} View }',
			'duplicate/reserved component member `reset`'],
		['component Bad(title string) { computed title := "same" View }',
			'duplicate/reserved component member `title`'],
		['component Bad(title string) { View(id: "title") }', 'element id `title` collides'],
		['component Bad() { View { Label(id: "same") Button(id: "same") } }',
			'element id `same` collides'],
		['component Bad(submit string) { ref submit Button View }', 'ref name collides'],
		['component Bad() { state count := 0 fn reset(count int) {} View }',
			'local function parameter `count` collides'],
		['component Bad() { fn reset(panel int) {} View(id: "panel") }',
			'local function parameter `panel` collides'],
	] {
		parse_vml_source(entry[0]) or {
			assert err.msg().contains(entry[1]), err.msg()
			continue
		}
		assert false, 'accepted shadowing: ${entry[0]}'
	}
}

fn test_vml_component_rejects_impure_computed_and_invalid_slot_event_declarations() {
	for entry in [
		[
			'component Bad(changed event(value int)) { computed result := changed(1) View }',
			'cannot emit events',
		],
		[
			'component Bad() { fn reset() {} computed result := reset() View }',
			'cannot call a handler',
		],
		[
			'component Bad(bind changed event(value int)) { View }',
			'events cannot be bindable',
		],
		[
			'component Bad(changed event(value int) = 1) { View }',
			'events cannot be bindable or have default values',
		],
		[
			'component Bad(bind content slot) { View }',
			'slots cannot be bindable',
		],
		[
			'component Bad(content slot = "body") { View }',
			'slots cannot be bindable or have default values',
		],
		[
			'component Bad() { View Label }',
			'requires exactly one root element',
		],
	] {
		parse_vml_source(entry[0]) or {
			assert err.msg().contains(entry[1]), err.msg()
			continue
		}
		assert false, 'accepted invalid component: ${entry[0]}'
	}
}

fn test_vml_bare_enum_arguments_are_typed_by_their_field() {
	root := parse_vml_source('Column(align_items: start) { Label(text: "Count", style: [text_align(right)]) TextInput(password: true) TextArea(disable_scroll: true) { Run(text: "rich") } }')!
	assert root.properties[0].expr.value == 'start'
	assert root.children[2].tag == 'TextArea'
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains('ui2.ColumnProps{\n\t\talign_items: .start\n')
	assert generated.contains('ui2.style_text_align(.right)')
	assert generated.contains('ui2.TextInputProps{\n\t\tpassword: true\n')
	assert generated.contains('ui2.TextAreaProps{\n\t\tdisable_scroll: true\n')
	assert generated.contains('ui2.vml_child(mut vml_node_0_2, mut vml_root_component, ui2.RunProps{')
}

fn test_vml_local_actions_and_unhandled_events_validate_declared_arity() {
	for source in [
		'component Bad(changed event(value int)) { Button(on_click: changed()) }',
		'component Bad(changed event(value int)) { Button(on_click: changed(1, 2)) }',
		'component Bad() { fn reset() {} Button(on_click: reset(1)) }',
		'component Bad() { fn reset(step int) {} mount { reset() } View }',
	] {
		parse_vml_source(source) or {
			assert err.msg().contains('requires'), err.msg()
			continue
		}
		assert false, 'accepted invalid action arity: ${source}'
	}
}

fn test_vml_callbacks_reject_literals_and_event_payloads_remain_typed_without_listeners() {
	for source in [
		'Button(on_click: "save")',
		'Button(on_click: true)',
		'Button(on_click: 1)',
		'Button(on_click: [1, 2])',
		'Counter(on_changed: "changed")',
	] {
		parse_vml_source(source) or {
			assert err.msg().contains('requires a typed function reference or an action'), err.msg()
			continue
		}
		assert false, 'accepted invalid callback: ${source}'
	}
	root := parse_vml_source('component Counter(changed event(value int)) { Button(on_click: changed(true)) }')!
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains('vml_payload_0 := true')
	assert generated.contains('$if vml_payload_0 !is int')
	assert generated.contains('vml_event_0_changed(vml_payload_0)')
	enum_root := parse_vml_source('component Counter(changed event(value ui2.Align)) { Button(on_click: changed(.right)) }')!
	enum_generated := compiler.lower(enum_root)
	assert enum_generated.contains('vml_payload_0 := ui2.Align.right')
	assert enum_generated.contains('$if vml_payload_0 !is ui2.Align')
	bare_root := parse_vml_source('component Counter(changed event(value ui2.Align)) { Button(on_click: changed(right)) }')!
	assert compiler.lower(bare_root).contains('vml_payload_0 := ui2.Align.right')
	conditional := parse_vml_source('Button(on_click: changed(true ? .right : .left))')!
	assert compiler.event_payload_value(conditional.properties[0].expr.args[0], 'ui2.Align', VmlScope{}).contains('ui2.Align.left')
}

fn test_vml_direct_nested_repeaters_declare_their_items_in_segments() {
	root := parse_vml_source('Column { Label(text: "start") Repeater(model: app.groups, key: item.id) { Label(text: item.name) Repeater(model: item.rows, key: item.id) { Button(text: item.name) } Label(text: "end group") } Label(text: "end") }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	assert generated.count('ui2.vml_repeat(') == 2
	assert generated.contains("ui2.vml_repeat(mut vml_node_0, '0_1',")
	assert generated.contains("ui2.vml_repeat(mut vml_segment_0_1, '0_1_1',")
	assert generated.contains('ui2.vml_child(mut vml_segment_0_1_1, mut vml_item_component_0_1_1, ui2.ButtonProps{}')
	assert generated.contains("ui2.vml_child(mut vml_node_0, mut vml_root_component, ui2.LabelProps{\n\t\ttext: 'end'\n\t}, path: '0.2'")
}
