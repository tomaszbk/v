module parser

import os

fn vml_lower_fixture(name string, files map[string]string) string {
	dir := os.join_path(os.vtmp_dir(), 'vml_lower_${name}_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	for file, source in files {
		os.write_file(os.join_path(dir, file), source) or { panic(err) }
	}
	return dir
}

fn vml_lower_document(dir string, uses_app bool) string {
	root := parse_vml_file(os.join_path(dir, 'main.vml')) or { panic(err) }
	mut compiler := VmlCompiler{
		uses_app:     uses_app
		guard_prefix: 'vml_check_lower'
	}
	return compiler.lower(root)
}

// The generic lowering names props types after tags and leaves widget knowledge
// to them: static properties are struct fields, reactive ones setters.
fn test_vml_lower_emits_props_nodes_setters_and_bindings() {
	dir := vml_lower_fixture('sample', {
		'main.vml': 'Column {
    Slider(id: "vol", bind.value: app.level, max: 10, on_change: app.changed())
    Label(text: "Level \${app.level}", style: [font_size(18)])
}'
	})
	defer { os.rmdir_all(dir) or {} }
	generated := vml_lower_document(dir, true)
	assert generated.contains('(fn [mut app] (vml_template_frame ui2.Rect) ui2.Element {'), generated
	assert generated.contains('mut vml_doc := ui2.vml_document(vml_template_frame, follow_viewport: true) or { panic(err) }')
	assert generated.contains("mut vml_node_0 := ui2.vml_root(mut vml_root_component, ui2.ColumnProps{}, path: '0', src: ui2.VmlSourceLocation{")
	assert generated.contains('if vml_check_lower_unreachable() { ui2.vml_guard_child[ui2.ColumnProps, ui2.SliderProps]() }')
	assert generated.contains('mut vml_node_0_0 := ui2.vml_child(mut vml_node_0, mut vml_root_component, ui2.SliderProps{\n')
	assert generated.contains('\t\tmax: 10\n')
	assert generated.contains('\t\ton_change: vml_root_component.callback(fn [mut app] (event ui2.ElementEvent) ! { _ = event')
	assert generated.contains("}, id: 'vol', path: '0.0', src: ")
	assert generated.contains("vml_node_0_0.prop('value', fn [mut app, mut vml_root_component] (mut vml_p ui2.SliderProps) ! { vml_root_component.watch_app()!; vml_p.value = app.level }) or { panic(err) }")
	assert generated.contains("vml_node_0_0.bind('value', fn [mut app] (vml_p ui2.SliderProps) ! { app.level = ui2.vml_assign(app.level, vml_p.value) }) or { panic(err) }")
	assert generated.contains('\t\tstyle: ui2.compose_styles([ui2.style_font_size(18)])\n')
	assert generated.contains("vml_node_0_1.prop('text', fn [mut app, mut vml_root_component] (mut vml_p ui2.LabelProps) ! { vml_root_component.watch_app()!; vml_p.text = 'Level \${app.level}' })")
	assert generated.contains('return vml_doc.finish() or { panic(err) }\n})(ui2.vml_bounds())')
	assert generated.contains('fn vml_check_lower_unreachable() bool { return false }')
	// `app.level` is read twice and guarded once.
	assert generated.count('fn vml_check_lower_field_') == 1, generated
	assert generated.count('if vml_check_lower_unreachable() { vml_check_lower_field_') == 1, generated
	// The compiler holds no widget table: no widget constructors or configs.
	for widget in ['ui2.slider(', 'SliderStyle', 'ui2.Element{', 'LayoutSize', 'set_child_layout'] {
		assert !generated.contains(widget), widget
	}
}

// Values are typed by their props field: bare names are enum values, `#hex` a
// color, theme roots tokens and style calls `ui2.style_*` helpers.
fn test_vml_lower_values_tokens_and_styles() {
	dir := vml_lower_fixture('values', {
		'main.vml': 'Absolute(width: 300) {
    View(id: "box", x: 4, align_items: stretch, style: [background(#112233), radius(radius.md), border_color("#aabbcc"), hover([background(color.surface)])])
    Label(x: box.width, text: "w", tooltip: true ? "a" : "b", style: app.ready ? [font_size(12)] : [font_size(14)])
    widgets.Gauge(value: 3)
    View(style: [app.card, theme.accent()])
}'
	})
	defer { os.rmdir_all(dir) or {} }
	generated := vml_lower_document(dir, true)
	// The runtime decides from the authored root size whether to follow the viewport.
	assert generated.contains('follow_viewport: true'), generated
	assert generated.contains('ui2.AbsoluteProps{\n\t\twidth: 300\n')
	assert generated.contains("vml_root_component.prepare_theme_tokens(['radius:md', 'color:surface']) or { panic(err) }")
	assert generated.contains('\t\talign_items: .stretch\n')
	// Theme tokens are reactive: the theme can change after the build.
	assert generated.contains("vml_node_0_0.prop('style', fn [mut vml_root_component] (mut vml_p ui2.ViewProps) ! { vml_p.style = ui2.compose_styles([ui2.style_background(u32(0x112233)), ui2.style_radius(vml_root_component.radius_token('md') or { panic(err) }), ui2.style_border_color(u32(0xaabbcc))")
	assert generated.contains("ui2.style_hover([ui2.style_background(vml_root_component.color_token('surface') or { panic(err) })]) or { panic(err) }")
	assert generated.contains('if vml_check_lower_unreachable() { ui2.vml_guard_positioned[ui2.AbsoluteProps]() }')
	assert !generated.contains('ui2.vml_guard_positioned[ui2.VmlDocument]')
	// Element geometry is reactive: it reads the retained node.
	assert generated.contains("vml_node_0_1.prop('x', fn [vml_node_0_0] (mut vml_p ui2.LabelProps) ! { vml_p.x = (vml_node_0_0.geometry() or { panic(err) }).width })")
	assert generated.contains("\t\ttooltip: (if true { 'a' } else { 'b' })\n")
	assert generated.contains('vml_p.style = (if app.ready { ui2.compose_styles([ui2.style_font_size(12)]) } else { ui2.compose_styles([ui2.style_font_size(14)]) })')
	// Dotted tags name a props type of the caller's module imports.
	assert generated.contains('widgets.GaugeProps{')
	// V does not check the elements of an array literal argument: a style value
	// that is no helper call is cast, so a wrong type is reported at the entry.
	assert generated.contains('vml_p.style = ui2.compose_styles([ui2.StylePatch(app.card), ui2.StylePatch(theme.accent())])')
}

// The document is the root's parent: authored x/y on the root are guarded
// against it, so ui2 reports that they need an Absolute parent.
fn test_vml_lower_guards_root_positions_against_the_document() {
	dir := vml_lower_fixture('root_position', {
		'main.vml': 'View(x: 4, width: 10)'
	})
	defer { os.rmdir_all(dir) or {} }
	generated := vml_lower_document(dir, false)
	assert generated.contains('if vml_check_lower_unreachable() { ui2.vml_guard_positioned[ui2.VmlDocument]() }'), generated
	assert generated.contains('fn vml_check_lower_unreachable() bool { return false }'), generated
}

// Enum values are bare names typed by their property; `.right` is an error,
// except in event payloads, which keep V's syntax.
fn test_vml_lower_rejects_dotted_enum_values_in_properties() {
	dir := vml_lower_fixture('dotted', {
		'main.vml':  'Label(style: [text_align(.right)])'
		'event.vml': 'Button(on_click: app.align(.right))'
	})
	defer { os.rmdir_all(dir) or {} }
	if _ := parse_vml_file(os.join_path(dir, 'main.vml')) {
		assert false, 'a dotted enum value was accepted'
	} else {
		assert err.msg().ends_with('main.vml:1:26: VML enum values omit the dot: use `right`'), err.msg()
	}
	parse_vml_file(os.join_path(dir, 'event.vml')) or { assert false, err.msg() }
}

// Repeaters lower to `ui2.vml_repeat` with typed model, key and item builder
// closures; key paths are checked against public fields like model paths.
fn test_vml_lower_repeaters_and_components() {
	dir := vml_lower_fixture('repeat', {
		'task_row.vml': 'component TaskRow(title string, removed event()) {
    state open := false
    Row(spacing: 2) {
        Label(text: title)
        Button(text: "x", on_click: removed())
    }
}'
		'main.vml':     'import TaskRow
Column {
    Repeater(model: app.tasks, key: item.id) {
        TaskRow(title: item.title, on_removed: app.remove(item.id), key: item.id, padding: 4)
    }
}'
	})
	defer { os.rmdir_all(dir) or {} }
	generated := vml_lower_document(dir, true)
	assert generated.contains("ui2.vml_repeat(mut vml_node_0, '0_0', fn [mut app, mut vml_root_component] () ![]typeof(vml_collection_0_0[0]) { vml_root_component.watch_app()!; return app.tasks }, fn [vml_collection_0_0] (vml_item_0_0 typeof(vml_collection_0_0[0])) string { _ = vml_collection_0_0; return '\${vml_item_0_0.id}' }, fn [mut app, vml_collection_0_0] (mut vml_item_component_0_0 ui2.CompiledVmlComponent, mut vml_segment_0_0 ui2.VmlSegment, vml_item_signal_0_0_input &ui2.Signal[typeof(vml_collection_0_0[0])]) ! {"), generated
	// The key path `item.id` is guarded on the collection's element type.
	assert generated.contains('vml_check_lower_field_'), generated
	assert generated.contains('(vml_collection_0_0[0])') || generated.contains('vml_collection_0_0[0].id')
	// The component's undeclared `padding` configures its root; its key moves there.
	assert generated.contains("mut vml_component_0_0_0 := vml_item_component_0_0.child('0.0.0') or { panic(err) }")
	assert generated.contains('mut vml_node_0_0_0_root := ui2.vml_child(mut vml_segment_0_0, mut vml_component_0_0_0, ui2.RowProps{')
	assert generated.contains('\t\tpadding: 4\n')
	assert generated.contains("}, path: '0.0.0.root', key: '\${vml_item_signal_0_0.get() or { panic(err) }.id}', src: ")
	assert generated.contains("mut vml_state_0_0_0_open := vml_component_0_0_0.state_factory[typeof(false)]('open'")
	assert generated.contains('vml_input_0_0_0_title_memo')
	assert generated.contains('if vml_check_lower_unreachable() { ui2.vml_guard_child[ui2.ColumnProps, ui2.RowProps]() }')
}
