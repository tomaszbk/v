module main

import ui2

fn typography() ui2.Element {
	return $vml('typography.vml')
}

fn composition() ui2.Element {
	return $vml('scaled.vml')
}

fn styled(mut app VisualApp) ui2.Element {
	return $vml('styles.vml')
}

fn bound_input(mut app VisualApp) ui2.Element {
	return $vml('bound_input.vml')
}

fn flex_row() ui2.Element {
	return $vml('flex.vml')
}

fn grid_view() ui2.Element {
	return $vml('grid.vml')
}

fn wrapped() ui2.Element {
	return $vml('wrap.vml')
}

fn intrinsic() ui2.Element {
	return $vml('intrinsic.vml')
}

fn dynamic_typography(mut app VisualApp) ui2.Element {
	return $vml('dynamic.vml')
}

fn assert_equivalent_element(actual ui2.Element, expected ui2.Element) {
	assert actual.children.len == expected.children.len
	assert ui2.Element{ ...actual, children: []ui2.Element{} } == ui2.Element{ ...expected, children: []ui2.Element{} }
	for index, child in actual.children {
		assert_equivalent_element(child, expected.children[index])
	}
}

fn test_compiled_runs_match_runtime_styles_and_measured_wrapping() {
	actual := typography()
	expected := ui2.element_from_vml($embed_file('typography.vml').to_string(), ui2.Rect{})!
	assert_equivalent_element(actual, expected)
	assert actual.text == 'Árbol y niñez 123 comparten wrapping y baseline.'
	assert actual.text_runs.len == 3
	assert actual.text_runs[0].style.weight == 600
	assert actual.text_runs[0].style.size == 18
	override := actual.text_runs[1].style
	assert override.size == 12
	assert override.weight == 0
	assert !override.bold && !override.tabular_figures
	assert override.letter_spacing == 0 && override.line_height == 0
	assert override.line_height_factor == 1.5 && override.baseline_offset == 3
	for width in [90.0, 160.0, 240.0] {
		constraints := ui2.LayoutConstraints{ max_width: width }
		left := ui2.measure_layout_element(ui2.Element{ ...actual, frame: ui2.rect(0, 0, width, 0) },
			constraints, ui2.measure_layout_text)!
		right := ui2.measure_layout_element(ui2.Element{ ...expected, frame: ui2.rect(0, 0, width, 0) },
			constraints, ui2.measure_layout_text)!
		assert left == right
		assert left.height >= 24
	}
}

fn test_compiled_scaled_content_matches_runtime_geometry_and_inverse_coordinates() {
	root := composition()
	actual := root.children[0]
	expected := ui2.element_from_vml($embed_file('scaled.vml').to_string(), ui2.Rect{})!
	assert_equivalent_element(root, expected)
	assert actual.children[0].children[0].frame == ui2.rect(600, 300, 180, 40)
	assert actual.children[0].children[1].kind == .text_field
	assert actual.children[0].children[1].text == 'niñez, canción'
	transform := ui2.contain_content(actual.frame, actual.content_size.width, actual.content_size.height)!
	assert transform.scale == 0.5 && transform.x == 10 && transform.y == 70
	assert transform.project(actual.children[0].children[0].frame) == ui2.rect(310, 220, 90, 20)
	x, y := transform.inverse(310, 220)
	assert x == 600 && y == 300
}

fn test_compiled_sparse_styles_preserve_false_zero_black_and_typed_events() {
	mut app := &VisualApp{}
	el := styled(mut app)
	assert el.id == 'styled' && el.kind == .button
	assert el.box.border_pattern == .dashed
	assert el.box.border_left_color or { u32(1) } == 0
	assert el.box.dash_length == 5 && el.box.dash_gap == 3
	assert el.box.outline_width == 1 && el.box.outline_offset == 2
	patch := el.interaction_style
	assert el.box == ui2.BoxStyle{
		bg:                0xffffff
		transparent:       true
		radius:            8
		border_color:      0x123456
		border_left:       2
		border_top:        2
		border_right:      2
		border_bottom:     2
		border_left_color: u32(0)
		border_pattern:    .dashed
		dash_length:       5
		dash_gap:          3
		outline_color:     0x334155
		outline_width:     1
		outline_offset:    2
	}
	assert patch == ui2.InteractionStyle{
		hover:         ui2.BoxStylePatch{ bg: u32(0), transparent: false }
		hover_text:    ui2.TextStylePatch{ color: u32(0xffffff) }
		focus:         ui2.BoxStylePatch{ border_left: f64(0), outline_width: f64(3) }
		pressed:       ui2.BoxStylePatch{ bg: u32(0x22c55e) }
		disabled:      ui2.BoxStylePatch{ bg: u32(0xcccccc) }
		disabled_text: ui2.TextStylePatch{ color: u32(0) }
	}
	assert patch.hover.bg or { u32(1) } == 0
	assert !(patch.hover.transparent or { true })
	assert patch.hover.border_color == none
	assert patch.focus.border_left or { f64(1) } == 0
	assert patch.focus.outline_width or { f64(0) } == 3
	assert patch.disabled_text.color or { u32(1) } == 0
	el.on_event(ui2.ElementEvent{ kind: .tap, id: el.id })
	assert app.count == 1
	el.on_event(ui2.ElementEvent{ kind: .change, id: el.id })
	assert app.count == 1
	assert styled(mut app).id == el.id
}

fn test_compiled_flex_matches_api_and_independent_bounded_growth_geometry() {
	actual := flex_row()
	style := ui2.TextStyle{}
	expected := ui2.flex(ui2.FlexConfig{
		id:       'row'
		frame:    ui2.rect(0, 0, 300, 120)
		padding:  ui2.LayoutPadding{ left: 10, top: 10, right: 10, bottom: 10 }
		gap:      10
		align:    .center
		children: [
			ui2.FlexChild{ element: ui2.label('first', 'One', ui2.rect(0, 0, 40, 20), style), grow: 1, maximum_width: 60 },
			ui2.FlexChild{ element: ui2.label('second', 'Two', ui2.rect(0, 0, 40, 20), style), grow: 2, minimum_width: 80 },
		]
	})!
	assert_equivalent_element(actual, expected)
	assert actual.children[0].frame == ui2.rect(10, 50, 60, 20)
	assert actual.children[1].frame == ui2.rect(80, 50, 210, 20)
}

fn test_compiled_grid_matches_runtime_and_independent_span_geometry() {
	actual := grid_view()
	expected := ui2.element_from_vml($embed_file('grid.vml').to_string(), ui2.Rect{})!
	assert_equivalent_element(actual, expected)
	assert actual.children.len == 3
	assert actual.children[0].frame == ui2.rect(10, 10, 196.66666666666666, 60)
	assert actual.children[1].frame.x > 216.6666666666666
	assert actual.children[1].frame.y == 10
	assert actual.children[2].frame == ui2.rect(10, 90, 93.33333333333333, 60)
}

fn test_compiled_wrapping_uses_shared_flex_line_geometry() {
	el := wrapped()
	assert el.children.map(it.frame) == [ui2.rect(0, 0, 80, 20), ui2.rect(90, 0, 80, 20),
		ui2.rect(0, 35, 80, 20)]
}

fn test_compiled_intrinsic_nested_layouts_remeasure_at_the_allocated_width() {
	actual := intrinsic()
	// Compare nested measurement with the current runtime using identical static declarations.
	source := $embed_file('intrinsic.vml').to_string()
	expected := ui2.element_from_vml(source, ui2.Rect{})!
	assert actual.children.len == expected.children.len
	for index, child in actual.children {
		assert child.frame == expected.children[index].frame
		assert child.children.map(it.frame) == expected.children[index].children.map(it.frame)
	}
}

fn test_compiled_input_bindings_and_submit_preserve_identity_and_unicode() {
	mut app := &VisualApp{}
	root := build(mut app)
	input := root.children[0].children[0].children[0].children[1].children[1]
	assert input.id == 'name'
	assert input.text == 'niñez'
	input.on_event(ui2.ElementEvent{ kind: .change, id: input.id, text: 'canción, año' })
	assert app.name == 'canción, año'
	assert app.count == 0
	input.on_event(ui2.ElementEvent{ kind: .submit, id: input.id, text: app.name })
	assert app.count == 10
	fresh := build(mut app).children[0].children[0].children[0].children[1].children[1]
	assert fresh.id == input.id && fresh.key == input.key
	assert fresh.text == app.name
}

fn test_compiled_bound_input_delegates_secure_mode_and_keeps_automatic_identity() {
	mut app := &VisualApp{}
	input := bound_input(mut app)
	assert input.id.len > 0
	assert input.secure && input.keyboard == 1
	assert input.kind == .text_field
	input.on_event(ui2.ElementEvent{ kind: .change, id: input.id, text: 'canción' })
	assert app.name == 'canción'
	fresh := bound_input(mut app)
	assert fresh.id == input.id && fresh.text == app.name
}

fn test_compiled_positioned_layouts_keep_absolute_origins_and_run_alias_overrides() {
	mut app := &VisualApp{}
	composition := build(mut app).children[0].children[0].children[0]
	assert composition.children[0].frame == ui2.rect(24, 20, 660, 65)
	assert composition.children[0].text_runs[2].style.size == 18
	assert composition.children[1].frame == ui2.rect(24, 105, 660, 70)
	assert composition.children[2].frame == ui2.rect(24, 210, 660, 240)
}

fn test_compiled_dynamic_numeric_styles_keep_v_types_and_explicit_text_interpolation() {
	mut app := &VisualApp{ count: 19 }
	el := dynamic_typography(mut app)
	assert el.frame == ui2.rect(0, 0, 119, 40)
	assert el.text_style.size == 19 && el.text_style.weight == 190
	assert el.text_style.color == u32(20)
	assert el.text_runs[0].style == el.text_style
	assert el.text_runs[1].style.size == 9.5
	assert el.text_runs[1].style.letter_spacing == 1
	assert el.text == 'Dynamic niñez'
}
