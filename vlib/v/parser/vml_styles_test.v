module parser

import os
import v.pref

fn test_vml_named_styles_inline_styles_and_component_local_styles() {
	for source in [
		'style card = [background(color.surface), padding(12), radius(8)]
View(style: [card, background(color.accent)]) { Label(text: "Contenido") }',
		'View(style: [background(color.surface), padding(12), radius(8)]) { Label(text: "Contenido") }',
		'component Card(title string = "Contenido") {
    style surface = [background(color.surface), padding(12), radius(8)]
    View(style: [surface]) { Label(text: title) }
}
Column(spacing: 16) { Card(title: "Jugadores") Card(title: "Partidas") Card(title: "Configuración") }',
		'style forward = [later, radius(8)]
style later = [padding(12)]
View(style: [forward])',
		'component Card() { View(style: [later]) }
style later = [padding(12)]
Column { Card() }',
	] {
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		generated := compiler.compile(root)
		assert generated.contains('ui2.compose_styles('), generated
		assert generated.contains('.style(fn ['), generated
		assert generated.contains('ui2.style_padding('), generated
		assert !generated.contains('unknown component'), generated
	}
}

fn test_vml_style_errors_are_precise_and_check_inactive_variants() {
	for pair in [
		['style card = [card]\nView(style: [card])', 'cyclic style'],
		['style first = [second]\nstyle second = [first]\nView()', 'cyclic style'],
		['style card = []\nstyle card = []\nView()', 'duplicate style'],
		['component Card(title string) { style title = [] View() }',
			'duplicate/reserved component member'],
		['component Bad(color string) { View() }', 'duplicate/reserved component member'],
		['View(id: "radius")', 'collides with a component member or id'],
		['style spacing = []\nView()', 'nonreserved local name'],
		['View(background: "#000000")', 'presentation argument `background` was replaced'],
		['TextInput(pad_left: 4)', 'presentation argument `pad_left` was replaced'],
		['View(align: right)', 'presentation argument `align` was replaced'],
		['View(style: [bg("#000000")])', 'unknown style helper `bg`'],
		['View(style: [padding("12")])', '`padding` requires a number'],
		['Label(style: [text_align("right")])', 'requires an enum value'],
		['Label(style: [text_align(.right)])', 'VML enum values omit the dot'],
		['View(style: true ? [radius(8)] : [radius(false)])', '`radius` requires a number'],
		['View(style: [hover([padding(4)])])',
			'interaction styles support box properties and foreground'],
		['Label { Run(text: "text", style: [background("#000000")]) }',
			'Run styles support text properties'],
	] {
		parse_vml_source(pair[0]) or {
			assert err.msg().contains(pair[1]), err.msg()
			continue
		}
		assert false, 'unexpectedly accepted ${pair[0]}'
	}
}

fn test_vml_styles_lower_typed_helpers_tokens_and_reactive_variants() {
	root := parse_vml_source('component Card(primary bool = true) {
    style strong = [background(color.accent), padding(spacing.medium)]
    style subtle = [background(color.surface), radius(radius.large)]
    View(style: [primary ? strong : subtle, hover([foreground(color.accent)])]) {
        Label(text: "Content", style: [font_size(typography.body), text_align(right)])
    }
}')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('.color_token('), generated
	assert generated.contains('.spacing_token('), generated
	assert generated.contains('.radius_token('), generated
	assert generated.contains('.font_size_token('), generated
	assert generated.contains('ui2.style_text_align(ui2.TextStyle{align: .right}.align)'), generated
	assert generated.contains('ui2.style_hover('), generated
	assert generated.contains('@property:'), generated
}

fn test_vml_style_lowering_has_valid_v_syntax_and_source_mapping() {
	mut root := parse_vml_source('style card = [background(color.surface), padding(12), radius(8)]
View(style: [card, background(color.accent), hover([foreground(color.accent)])]) {
    Label(style: [font_size(typography.body), text_align(center)]) {
        Run(text: "Inherited")
        Run(text: "Local", style: [font_size(20)])
    }
}')!
	vml_set_source(mut root, 'styles.vml')
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	path := os.join_path(os.vtmp_dir(), 'vml_style_syntax_${os.getpid()}.v')
	defer { os.rm(path) or {} }
	os.write_file(path, 'fn main() { _ = ${generated} }')!
	mut parser := Parser.new(pref.new_preferences())
	parser.parse_file(path)
	assert parser.diagnostics.len == 0, parser.diagnostics.str()
	assert compiler.locations.len == generated.count('\n')
	for location in compiler.locations {
		assert location.path == 'styles.vml'
	}
}

fn test_vml_native_styles_validate_custom_helpers_even_in_inactive_arms() {
	for source in ['View(style: [hover([background(color.accent)])])',
		'Label(style: [weight(false ? 400 : 600)])', 'Label(style: false ? [] : [font_family("Inter")])'] {
		root := parse_vml_source(source)!
		validate_vml_native_visual(root) or {
			assert err.msg().contains('custom renderer'), err.msg()
			continue
		}
		assert false, source
	}
	root := parse_vml_source('View(style: [background(color.surface), padding(spacing.medium)])')!
	validate_vml_native_visual(root)!
}

fn test_vml_typed_style_component_inputs_and_qualified_style_factories() {
	root := parse_vml_source('style surface = [background(color.surface)]
component Card(appearance ui2.StylePatch = [fallback]) {
    style fallback = [padding(12)]
    View(style: [appearance])
}
Column { Card(appearance: [surface]) Card() View(style: [app.card()]) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains("vml_root_component.prepare_theme_tokens(['color:surface'])"), generated
	assert generated.contains("ui2.style_background(ui2.TextStyle{color: vml_root_component.color_token('surface')"), generated
	assert generated.contains('ui2.compose_styles([app.card()])'), generated
	assert generated.contains('ui2.style_padding('), generated
}
