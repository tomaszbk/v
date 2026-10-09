module parser

fn test_composite_visibility_uses_constructor_default_and_explicit_override() {
	for tag in ['Popup', 'ModalView'] {
		root := parse_vml_source('${tag}(open: app.open) { Label(text: "Body") }')!
		mut compiler := VmlCompiler{ uses_app: true }
		generated := compiler.compile(root)
		assert generated.contains('hidden: vml_widget_0.hidden')
		assert generated.contains('enabled: vml_widget_0.enabled')
		assert generated.contains('clickable: vml_widget_0.clickable')
		assert generated.contains('accessibility_role: vml_widget_0.accessibility_role')
		assert generated.contains('interaction_style: vml_widget_0.interaction_style')
		assert generated.contains('menu: vml_widget_0.menu')
		assert generated.contains('open:')
		assert generated.contains('.structure(')
		mut explicit_compiler := VmlCompiler{ uses_app: true }
		explicit := parse_vml_source('${tag}(open: app.open, hidden: app.hidden) { Label(text: "Body") }')!
		explicit_generated := explicit_compiler.compile(explicit)
		assert explicit_generated.contains('hidden: vml_property_0_hidden')
		assert !explicit_generated.contains('hidden: vml_widget_0.hidden')
	}
}

fn test_managed_screen_without_name_keeps_id_as_typed_name() {
	root := parse_vml_source('ScreenManager { Screen(id: "home") {} Screen(id: "detail", name: "details") {} }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains("compiled_metadata: &ui2.CompiledVmlMetadata{screen: ui2.ManagedScreen{name: 'home'}}")
	assert generated.contains('screen: ui2.ManagedScreen{name: vml_property_0_1_name}')
	assert generated.contains('kind: .screen')
}

fn test_direct_element_common_defaults_do_not_use_widget_fallbacks() {
	root := parse_vml_source('Label(text: "Visible")')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('hidden: false')
	assert generated.contains('enabled: true')
	assert !generated.contains('vml_widget_')
}

fn test_visual_scale_literals_reject_singular_values_but_preserve_reflection() {
	for source in ['View(scale_x: 0)', 'View(scale_y: -0)', 'View(scale_x: false ? 0 : 1)',
		'Popup(scale_y: true ? 1 : 0) {}'] {
		parse_vml_source(source) or {
			assert err.msg().contains('must be finite and nonzero'), err.msg()
			continue
		}
		assert false, 'singular scale was accepted: ${source}'
	}
	for source in ['View(scale_x: -1, scale_y: 2)', 'View(scale_x: 0.5)', 'Popup(scale_y: -2) {}'] {
		parse_vml_source(source)!
	}
}

fn test_dynamic_geometry_axis_preserves_other_authored_inputs() {
	root := parse_vml_source('Column(width: 100, height: 40) { View(height: 40) ProgressBar(width: app.width, height: 14) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('element.with_layout_frame(ui2.Rect{...(element.layout_input or { element.frame }), width:')
}

fn test_intrinsic_grid_retains_config_until_children_are_allocated() {
	root := parse_vml_source('Column { Grid(columns: 2, spacing: 10) { Label(text: "First") Label(text: "Second") } }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('ui2.grid_declaration(vml_config_0_0)')
	assert !generated.contains('ui2.grid(vml_config_0_0)')
	assert generated.contains('ui2.flex(vml_config_0)')
}
