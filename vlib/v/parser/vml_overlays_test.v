module parser

import os
import v.pref

fn test_overlay_builtins_lower_to_retained_view_surfaces_with_typed_config() {
	for tag, kind in {
		'Dialog':      'dialog'
		'Popover':     'popover'
		'MenuOverlay': 'menu'
		'ContextMenu': 'context_menu'
		'Tooltip':     'tooltip'
	} {
		root := parse_vml_source('${tag}(open: app.open, anchor: "trigger", placement: top_end, gap: 4, tooltip_delay: app.delay, on_open: app.show(), on_dismiss: app.close()) { Label(text: "Body") }')!
		mut compiler := VmlCompiler{ uses_app: true }
		generated := compiler.compile(root)
		assert generated.contains('vml_overlay_base_0 := ui2.Element{'), generated
		assert generated.contains('kind: .view'), generated
		assert generated.contains("id: '__vml_control_0'"), generated
		assert generated.contains('ui2.with_overlay(vml_overlay_base_0, ui2.OverlayConfig{kind: .${kind}'), generated
		assert generated.contains('ui2.OverlayConfig{placement: .top_end}.placement'), generated
		assert generated.contains('on_dismiss: vml_callback_0_on_dismiss'), generated
		assert generated.contains('on_open: vml_callback_0_on_open'), generated
		assert generated.contains('tooltip_delay: vml_property_0_tooltip_delay_memo.get()'), generated
		assert generated.contains(".effect('@overlay'"), generated
		assert !generated.contains('.structure('), generated
	}
}

fn test_overlay_open_and_authored_hidden_share_one_property_effect() {
	root := parse_vml_source('Dialog(id: "dialog", open: app.open, hidden: app.hidden, accessibility_role: app.role) { TextInput(id: "draft", text: "Local edit") }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('hidden: vml_property_0_hidden_memo.get()'), generated
	assert generated.contains('open: vml_property_0_open_memo.get()'), generated
	assert generated.contains('focus_scope: vml_overlay_base_0.focus_scope'), generated
	assert generated.contains('focus_policy: vml_overlay_base_0.focus_policy'), generated
	assert generated.contains('tab_index: vml_overlay_base_0.tab_index'), generated
	assert !generated.contains(".effect('open'"), generated
	assert !generated.contains(".effect('hidden'"), generated
	assert !generated.contains(".effect('accessibility_role'"), generated
}

fn test_typed_overlay_property_checks_its_config_and_patches_without_rebuilding() {
	root := parse_vml_source('View(overlay: app.config, hidden: app.hidden, on_dismiss: app.close()) { Label(text: "Body") }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('ui2.OverlayConfig{...app.config}'), generated
	assert generated.contains('ui2.OverlayConfig{...vml_property_0_overlay_memo.get()'), generated
	assert generated.contains(".effect('@overlay'"), generated
	assert generated.contains('on_dismiss: vml_callback_0_on_dismiss'), generated
	assert !generated.contains('.structure('), generated
}

fn test_overlay_point_backdrop_and_strings_have_explicit_typed_values() {
	root := parse_vml_source('ContextMenu(open: true, owner: "editor", point: app.point, backdrop: app.backdrop, initial_focus: "first") {}')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('ui2.OverlayConfig{point: app.point}.point'), generated
	assert generated.contains('.computed[ui2.OverlayConfig]('), generated
	assert generated.contains('vml_property_0_point_memo.get() or { panic(err) }.point'), generated
	assert !generated.contains('!typeof(ui2.OverlayConfig{point:'), generated
	assert generated.contains('ui2.BoxStyle{...app.backdrop}'), generated
	assert generated.contains("ui2.Element{text: vml_root_component.control_id('editor')}.text"), generated
	assert generated.contains("ui2.Element{text: vml_root_component.control_id('first')}.text"), generated
}

fn test_overlay_literal_local_ids_resolve_once_and_dynamic_ids_stay_typed() {
	root := parse_vml_source('component Host() { state open := false View(id: "owner") { Button(id: "trigger") Popover(open: open, owner: "owner", anchor: "trigger", initial_focus: "first") { Button(id: "first") } Tooltip(anchor: app.anchor) {} Tooltip(anchor: open ? "trigger" : "owner") {} } }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains("ui2.Element{text: vml_component_0.control_id('trigger')}.text"), generated
	assert generated.contains("ui2.Element{text: vml_component_0.control_id('owner')}.text"), generated
	assert generated.contains("ui2.Element{text: vml_component_0.control_id('first')}.text"), generated
	assert generated.contains('anchor: vml_property_0_root_1_anchor'), generated
	assert generated.contains('owner: vml_property_0_root_1_owner'), generated
	assert generated.contains('initial_focus: vml_property_0_root_1_initial_focus'), generated
	assert generated.contains('ui2.Element{text: app.anchor}.text'), generated
	assert !generated.contains('control_id(app.anchor)'), generated
	initializer := generated.split_into_lines().filter(it.contains('mut vml_property_0_root_3_anchor_memo :='))[0]
	assert initializer.contains('mut vml_component_0'), initializer
}

fn test_overlay_literals_reject_wrong_types_and_out_of_bounds_values() {
	for source in ['Dialog(open: 1)', 'Dialog(owner: 1)', 'Popover(anchor: true)', 'Dialog(gap: -1)',
		'Dialog(margin: -0.5)', 'Dialog(backdrop_opacity: 1.1)', 'Dialog(backdrop_opacity: -0.1)',
		'Dialog(dismiss_on_escape: "yes")', 'Dialog(tooltip_delay: -1)', 'Dialog(tooltip_delay: "slow")',
		'Dialog(placement: "top")', 'Dialog(placement: .top)'] {
		parse_vml_source(source) or { continue }
		assert false, 'invalid overlay argument was accepted: ${source}'
	}
}

fn test_overlays_require_custom_profile_and_popup_widgets_are_removed() {
	for source in ['Dialog {}', 'View(overlay: app.config)',
		'Column { Tooltip(anchor: "label") { Label(text: "Help") } }'] {
		root := parse_vml_source(source)!
		validate_vml_native_visual(root) or {
			assert err.msg().contains('requires the custom renderer'), err.msg()
			continue
		}
		assert false, source
	}
	for tag in ['Popup', 'ModalView'] {
		parse_vml_source('${tag} {}') or {
			assert err.msg().contains('removed widget `${tag}`; use Dialog'), err.msg()
			continue
		}
		assert false, tag
	}
	parse_vml_source('Label(overlay: app.config)') or { return }
	assert false, 'overlay must be attached to a View'
}

fn test_scroll_modes_lower_to_typed_constructor_fields_and_property_effects() {
	for mode in ['vertical_only', 'horizontal_only', 'both'] {
		root := parse_vml_source('Scroll(scroll_mode: ${mode}) { Label(text: "Content") }')!
		mut compiler := VmlCompiler{}
		generated := compiler.compile(root)
		assert generated.contains('ui2.Element{scroll_mode: .${mode}}.scroll_mode'), generated
		assert generated.contains('scroll_mode: vml_property_0_scroll_mode'), generated
		assert generated.contains('vml_input_0_0 := ui2.rect(0, 0, 0, 0)'), generated
		assert generated.contains('inherit_width: true, inherit_height: true'), generated
	}
	root := parse_vml_source('Scroll(scroll_mode: app.mode) {}')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains(".effect('scroll_mode'"), generated
	assert generated.contains('scroll_mode: vml_property_0_scroll_mode_memo.get()'), generated
	for source in ['Scroll(scroll_mode: "horizontal")', 'Scroll(scroll_mode: .horizontal)',
		'Scroll(scroll_mode: 1)'] {
		parse_vml_source(source) or { continue }
		assert false, source
	}
}

fn test_scroll_repeated_children_inherit_only_the_runtime_non_scrolling_axes() {
	root := parse_vml_source('Scroll(scroll_mode: app.mode) { Repeater(model: app.items, key: item.id) { Label(text: item.name) } }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('vml_input_0_0_0 := ui2.rect(0, 0, 0, 0)'), generated
	assert generated.contains('inherit_width: true, inherit_height: true'), generated
}

fn test_overlay_builtin_refs_use_the_typed_view_marker() {
	root := parse_vml_source('component Host() { ref panel View Dialog(ref: panel) {} }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	assert generated.contains('.ref[ui2.VmlView]('), generated
	assert generated.contains('vml_ref_0_panel.bind(vml_node_0_root)'), generated
	assert !generated.contains('$compile_error('), generated
}

fn test_overlay_diagnostics_keep_the_vml_property_and_call_site() {
	root := os.join_path(os.vtmp_dir(), 'vml_overlay_diagnostics_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(view, 'Dialog(\n    open: true,\n    gap: -1,\n) {}')!
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	mut prefs := pref.new_preferences()
	prefs.user_defines << 'ui2_custom_rendering'
	mut parser := Parser.new(prefs)
	parser.parse_file(source)
	assert parser.diagnostics.len == 1, parser.diagnostics.str()
	diagnostic := parser.diagnostics[0]
	assert os.real_path(diagnostic.file) == os.real_path(view)
	assert diagnostic.line == 3
	assert diagnostic.column == 5
	assert diagnostic.message.contains('nonnegative')
	assert diagnostic.pos.id in parser.a.template_call_sites

	os.write_file(view, 'View(\n    overlay: app.config,\n) {}')!
	mut native := Parser.new(pref.new_preferences())
	native.parse_file(source)
	assert native.diagnostics.len == 1, native.diagnostics.str()
	assert native.diagnostics[0].line == 2
	assert native.diagnostics[0].column == 5
	assert native.diagnostics[0].message.contains('requires the custom renderer')
	assert native.diagnostics[0].pos.id in native.a.template_call_sites
}

fn test_overlay_component_aliases_require_declaration_before_literal_references() ! {
	root := os.join_path(os.vtmp_dir(), 'vml_overlay_aliases_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	card := os.join_path(root, 'card.vml')
	os.write_file(card, 'component Card() { View(id: "private") {} }')!
	for property in ['anchor', 'owner', 'initial_focus'] {
		for value in ['"card"', 'app.choose ? "button" : "card"'] {
			arguments := if property == 'anchor' {
				'anchor: ${value}'
			} else {
				'anchor: "button", ${property}: ${value}'
			}
			os.write_file(view, 'import Card\nView {\n    Popover(${arguments}) {}\n    Card(id: "card")\n    Button(id: "button")\n}')!
			parse_compiled_vml_file(view, '', []) or {
				assert err.msg().contains('component alias `card` before its declaration'), err.msg()
				assert err.msg().contains('${view}:3:'), err.msg()
				continue
			}
			assert false, 'forward ${property} component alias was accepted'
		}
	}
	os.write_file(view, 'import Card\nView { Card(id: "card") Popover(anchor: "card") {} }')!
	valid := parse_compiled_vml_file(view, '', [])!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(valid)
	assert generated.contains('ui2.Element{text: vml_node_0_0.element().id}.text'), generated
	os.write_file(view, 'View { Popover(anchor: "button", initial_focus: "first") { Button(id: "first") } Button(id: "button") }')!
	parse_compiled_vml_file(view, '', [])!
	os.write_file(view, 'import Card\nView { Repeater(model: app.items, key: item.id) { Popover(anchor: "card") {} Card(id: "card") } }')!
	parse_compiled_vml_file(view, '', []) or {
		assert err.msg().contains('component alias `card` before its declaration'), err.msg()
		return
	}
	assert false, 'forward component alias in a repeater was accepted'
}

fn test_forward_overlay_component_alias_diagnostic_points_to_vml_property() ! {
	root := os.join_path(os.vtmp_dir(), 'vml_overlay_alias_diagnostic_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(os.join_path(root, 'card.vml'), 'component Card() { View(id: "private") {} }')!
	os.write_file(view, 'import Card\nView {\n    Popover(\n        anchor: "card",\n    ) {}\n    Card(id: "card")\n}')!
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	mut prefs := pref.new_preferences()
	prefs.user_defines << 'ui2_custom_rendering'
	mut parser := Parser.new(prefs)
	parser.parse_file(source)
	assert parser.diagnostics.len == 1, parser.diagnostics.str()
	diagnostic := parser.diagnostics[0]
	assert os.real_path(diagnostic.file) == os.real_path(view)
	assert diagnostic.line == 4
	assert diagnostic.column == 9
	assert diagnostic.message.contains('component alias `card` before its declaration')
	assert diagnostic.pos.id in parser.a.template_call_sites
}
