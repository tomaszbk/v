module parser

fn test_reactive_property_constructor_and_effect_read_the_same_memo() {
	root := parse_vml_source('Label(text: app.next_count())')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	effect := generated.all_after(".effect('text'")
	assert generated.contains("('@property:0:text'"), generated
	assert effect.contains('vml_property_0_text_memo.get()'), effect
	assert !effect.contains('app.next_count()'), effect
}

fn test_input_default_factory_keeps_the_declared_input_position() {
	mut root := parse_vml_source('component Typed(valid bool = app.count) { Label(text: "value") }')!
	vml_set_source(mut root, 'defaults.vml')
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	lines := generated.split_into_lines()
	for index, line in lines {
		if line.contains(".state_factory('valid'") {
			assert compiler.locations[index].path == 'defaults.vml'
			assert compiler.locations[index].line == 1
			assert compiler.locations[index].column == 17
			return
		}
	}
	assert false, generated
}

fn test_own_geometry_initializers_keep_the_live_frame_dependency_in_effects() {
	root := parse_vml_source('Absolute { View(id: "box", width: app.width, height: box.width * 2) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('mut vml_property_0_0_width_memo :='), generated
	assert !generated.contains('mut vml_property_0_0_height_memo :='), generated
	height_effect := generated.all_after(".effect('height'").all_before(".effect('")
	assert height_effect.contains('vml_geometry_0_0.get()'), height_effect
}

fn test_content_and_child_rules_share_their_prepared_property_memos() {
	root := parse_vml_source('Row { Label(flex_basis: app.next_width()) { Run(text: app.next_count()) } Dropdown { Option(text: app.next_count()) } }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	runs_effect := generated.all_after(".effect('@runs'")
	assert runs_effect.contains('vml_property_0_0_run_0_text_memo.get()'), runs_effect
	assert generated.contains('set_child_layout(ui2.VmlChildLayout{flex: ui2.FlexChild{element: ui2.Element{}, basis: vml_property_0_0_flex_basis_memo.get()'), generated
}

fn test_layout_content_effects_keep_the_visible_child_scope() {
	root := parse_vml_source('Row { Label(id: "item", width: 20, height: 20) MenuItem(text: "Width \${item.width}") }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	menu_effect := generated.all_after(".effect('@menu'")
	assert !menu_effect.contains('item.width'), menu_effect
	assert generated.contains('vml_geometry_0_0.get()'), generated
}
