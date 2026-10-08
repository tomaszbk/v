module parser

import os
import v.pref

fn test_selected_auto_grid_measurement_keeps_shared_nested_child_source() {
	root := parse_vml_source('Absolute {
        width: 300 height: 300
        Grid { auto_columns_min_width: 100
            View { View { Label { width: app.leaf_width() height: 20 text: "selected_grid_leaf" } } }
            View { View { Label { width: app.leaf_width() height: 20 text: "selected_grid_leaf" } } }
            View { View { Label { width: app.leaf_width() height: 20 text: "selected_grid_leaf" } } }
            View { View { Label { width: app.leaf_width() height: 20 text: "selected_grid_leaf" } } }
            View { View { Label { width: app.leaf_width() height: 20 text: "selected_grid_leaf" } } }
        }
    }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	// Each of the five leaves is shared across at most five placement phases.
	assert generated.count('selected_grid_leaf') <= 25
	assert generated.count('app.leaf_width()') <= 25
	assert generated.len <= 40000 * 17
	println('selected_grid generated_bytes=${generated.len} leaf_copies=${generated.count('selected_grid_leaf')} expression_copies=${generated.count('app.leaf_width()')}')
	if os.getenv('VML_SIBLING_KEEP_FIXTURES') == '1' {
		os.write_file(os.join_path(os.vtmp_dir(), 'selected_grid.generated.v'), generated)!
	}
}

fn test_vml_visual_errors_include_the_property_location_and_check_inactive_arms() {
	for entry in [
		['Label {\n  tracking: 2\n}', 'unsupported property `tracking` on Label', '2', '3'],
		['Label {\n  weight: true ? 400 : "heavy"\n}', '`weight` requires a number', '2', '3'],
		['Label {\n  tabular_figures: false ? true : 1\n}', 'requires bool', '2', '3'],
		['Label {\n  align: .diagonal\n}', 'unsupported align value', '2', '3'],
		['Label {\n  align: "right"\n}', 'requires a V enum value', '2', '3'],
		['Label {\n  text: 123\n}', '`text` requires a string', '2', '3'],
		['View {\n  units: "logical"\n}', 'unsupported property `units`', '2', '3'],
		['Run { text: "orphan" }', 'Run must be a child of Label', '1', '1'],
		['TextField {}', 'unsupported VML element `TextField`', '1', '1'],
		['Rectangle {}', 'unsupported VML element `Rectangle`', '1', '1'],
		['Label {\n  computed Matrix value: 1\n}', 'unsupported computed type `Matrix`', '2', '19'],
	] {
		parse_vml_source(entry[0]) or {
			assert err.msg().contains(entry[1]), err.msg()
			assert err.msg().contains('line ${entry[2]}, column ${entry[3]}'), err.msg()
			continue
		}
		assert false, 'unexpectedly accepted ${entry[0]}'
	}
}

fn test_vml_visual_lowering_produces_valid_v_syntax() {
	root_path := os.join_path(os.vtmp_dir(), 'vml_visual_syntax_${os.getpid()}')
	os.mkdir_all(root_path)!
	defer { os.rmdir_all(root_path) or {} }
	for index, source in [
		'Label { font_size: 18 bold: true Run { text: "Parent" } Run { text: "Override" size: 12 bold: false } }',
		'Flex { width: 200 height: 80 Label { text: "One" } }',
		'Row { width: 200 height: 80 Label { text: "One" } }',
		'Column { width: 200 height: 80 Label { text: "One" } }',
		'Grid { columns: 2 width: 200 height: 80 Label { text: "One" } }',
	] {
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		path := os.join_path(root_path, '${index}.v')
		os.write_file(path, 'fn main() { _ = ${compiler.compile(root)} }')!
		mut parser := Parser.new(pref.new_preferences())
		parser.parse_file(path)
		assert parser.diagnostics.len == 0, parser.diagnostics.str()
	}
}

fn test_vml_visual_native_profile_checks_the_entire_tree() {
	for source in ['View { ScaledContent { content_width: 200 content_height: 100 } }',
		'Label { Run { text: "Rich" } }', 'Button { hover_background: "#000000" }',
		'Label { weight: false ? 0 : 700 }'] {
		root := parse_vml_source(source)!
		validate_vml_native_visual(root) or {
			assert err.msg().contains('requires the custom renderer'), err.msg()
			assert err.msg().contains('column'), err.msg()
			continue
		}
		assert false, source
	}
}

fn test_vml_visual_parser_diagnostic_points_to_vml_file_and_call_site() {
	root := os.join_path(os.vtmp_dir(), 'vml_visual_diagnostics_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(view, 'Label {\n  font_size: "large"\n}')!
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	mut prefs := pref.new_preferences()
	prefs.user_defines << 'ui2_custom_rendering'
	mut parser := Parser.new(prefs)
	parser.parse_file(source)
	assert parser.diagnostics.len == 1, parser.diagnostics.str()
	diagnostic := parser.diagnostics[0]
	assert os.real_path(diagnostic.file) == os.real_path(view)
	assert diagnostic.line == 2
	assert diagnostic.column == 3
	assert diagnostic.message.contains('requires a number')
	assert diagnostic.pos.id in parser.a.template_call_sites
}
