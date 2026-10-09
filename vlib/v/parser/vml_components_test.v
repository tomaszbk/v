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
            Button(ref: submit, text: title, on_tap: increment(1))
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

fn test_vml_bare_enum_arguments_and_separate_text_editors() {
	root := parse_vml_source('Column(align_items: start) { Label(text: "Count", align: right) TextInput(password: true) TextArea(disable_scroll: true) { Run(text: "rich") } }')!
	assert root.properties[0].expr.value == 'start'
	assert root.children[2].tag == 'TextArea'
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('ui2.FlexConfig{align: .start}')
	assert generated.contains('ui2.TextStyle{align: .right}')
	assert generated.contains('ui2.text_input(ui2.TextInputConfig{')
	assert generated.contains('ui2.text_area(ui2.TextAreaConfig{')
	for entry in [
		['Label(align: .right)', 'omit the dot'],
		['TextInput(multiline: false)', 'unsupported property `multiline`'],
		['TextInput(disable_scroll: true)', 'unsupported property `disable_scroll`'],
		['TextInput { Run(text: "rich") }', 'single-line'],
		['TextArea(multiline: true)', 'unsupported property `multiline`'],
		['TextArea(password: true)', 'unsupported property `password`'],
		['TextArea(on_submit: app.save)', 'unsupported property `on_submit`'],
	] {
		parse_vml_source(entry[0]) or {
			assert err.msg().contains(entry[1]), err.msg()
			continue
		}
		assert false, 'accepted replaced syntax: ${entry[0]}'
	}
}

fn test_vml_local_actions_and_unhandled_events_validate_declared_arity() {
	for source in [
		'component Bad(changed event(value int)) { Button(on_tap: changed()) }',
		'component Bad(changed event(value int)) { Button(on_tap: changed(1, 2)) }',
		'component Bad() { fn reset() {} Button(on_tap: reset(1)) }',
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
		'Button(on_tap: "save")',
		'Button(on_tap: true)',
		'Button(on_tap: 1)',
		'Button(on_tap: [1, 2])',
		'Counter(on_changed: "changed")',
	] {
		parse_vml_source(source) or {
			assert err.msg().contains('requires a typed function reference or an action'), err.msg()
			continue
		}
		assert false, 'accepted invalid callback: ${source}'
	}
	root := parse_vml_source('component Counter(changed event(value int)) { Button(on_tap: changed(true)) }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('vml_payload_0 := true')
	assert generated.contains('$if vml_payload_0 !is int')
	assert generated.contains('vml_event_0_changed(vml_payload_0)')
	enum_root := parse_vml_source('component Counter(changed event(value ui2.Align)) { Button(on_tap: changed(.right)) }')!
	enum_generated := compiler.compile(enum_root)
	assert enum_generated.contains('vml_payload_0 := ui2.Align.right')
	assert enum_generated.contains('$if vml_payload_0 !is ui2.Align')
	conditional := parse_vml_source('Button(on_tap: changed(true ? .right : .left))')!
	assert compiler.event_payload_value(conditional.properties[0].expr.args[0], 'ui2.Align', VmlScope{}).contains('ui2.Align.left')
}

fn test_vml_direct_nested_repeaters_lower_to_nonvisual_keyed_fragments() {
	root := parse_vml_source('Column { Label(text: "start") Repeater(model: app.groups, key: item.id) { Label(text: item.name) Repeater(model: item.rows, key: item.id) { Button(text: item.name) } Label(text: "end group") } Label(text: "end") }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('.fragment(')
	assert generated.count('ui2.new_vml_keyed_list[') == 2
	assert generated.contains('vml_fragment_0_1.set_segment(')
	assert generated.contains('return [vml_fragment_0_1]')
	assert !generated.contains('vml_fragment_0_1.frame()')
}

fn test_vml_screen_retains_the_frame_used_to_seed_named_geometry_before_children() {
	root := parse_vml_source('Screen(id: "root") { Absolute { Label(font_size: root.height / 10, text: "size") } }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains(".geometry('root', vml_frame_0)")
	assert generated.contains("kind: .screen\n\t\tid: 'root'\n\t\tframe: vml_frame_0")
	geometry := generated.index(".geometry('root', vml_frame_0)") or { -1 }
	child_property := generated.index('vml_property_0_0_0_font_size') or { -1 }
	assert child_property >= 0
	assert geometry < child_property
}
