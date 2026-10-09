module parser

import os
import v.pref

fn test_vml_nested_layout_source_has_a_bounded_number_of_leaf_builders() {
	mut sizes := []int{}
	mut copies := []int{}
	for depth in [1, 2, 4, 8] {
		mut source := 'Label { width: 30 text: "unique_leaf_marker" }'
		for _ in 0 .. depth { source = 'Row { align_items: .start ${source} }' }
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		generated := compiler.compile(root)
		sizes << generated.len
		copies << generated.count('unique_leaf_marker')
		println('depth=${depth} nodes=${depth + 1} generated_bytes=${generated.len} leaf_copies=${copies.last()}')
		if os.getenv('VML_BOUNDS_KEEP_FIXTURES') == '1' {
			os.write_file(os.join_path(os.vtmp_dir(), 'growth_${depth}.generated.v'), generated)!
			os.write_file(os.join_path(os.vtmp_dir(), 'growth_${depth}.vml'), source)!
		}
	}
	for index, depth in [1, 2, 4, 8] {
		assert copies[index] <= 5, copies.str()
		assert sizes[index] <= 40000 * (depth + 1), sizes.str()
	}
}

fn test_vml_renderer_profile_matches_target_qualified_custom_flag() {
	root := os.join_path(os.vtmp_dir(), 'vml_renderer_profile_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(view, 'Label {\n  weight: 600\n  text: "Example"\n}')!
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	// Target preferences exercise classification only; they do not select,
	// compile or execute a Linux/Windows backend on this host.
	for entry in [
		['ios', '', 'native'],
		['ios', 'ui2_custom_rendering', 'native'],
		['macos', '', 'native'],
		['macos', 'ui2_custom_rendering', 'custom'],
		['android', '', 'custom'],
		['android', 'ui2_custom_rendering', 'custom'],
		['linux', '', 'custom'],
		['windows', '', 'native'],
		['windows', 'ui2_custom_rendering', 'custom'],
	] {
		mut prefs := pref.new_preferences()
		prefs.target = pref.target_from(entry[0], 'arm64')!
		if entry[1].len > 0 { prefs.user_defines << entry[1] }
		mut parser := Parser.new(prefs)
		parser.parse_file(source)
		if entry[2] == 'custom' {
			assert parser.diagnostics.len == 0, parser.diagnostics.str()
		} else {
			assert parser.diagnostics.len == 1, '${entry}: ${parser.diagnostics}'
			diagnostic := parser.diagnostics[0]
			assert os.real_path(diagnostic.file) == os.real_path(view)
			assert diagnostic.line == 2 && diagnostic.column == 3
			assert diagnostic.message == '`weight` requires the custom renderer'
			assert diagnostic.pos.id in parser.a.template_call_sites
		}
	}
}

fn test_vml_named_self_references_do_not_accumulate_descendant_exports() {
	for depth in [1, 2, 4, 8, 16] {
		mut source := 'Label { width: 30 height: 20 text: "named_leaf_marker" }'
		for index in 0 .. depth {
			source = 'Row {
                id: level_${index}
                computed f64 offered: level_${index}.width
                width: level_${index}.offered / 2
                height: 20 align_items: .start
                ${source}
            }'
		}
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		generated := compiler.compile(root)
		println('named_depth=${depth} nodes=${depth + 1} generated_bytes=${generated.len} leaf_copies=${generated.count('named_leaf_marker')}')
		assert generated.count('named_leaf_marker') <= 5
		assert generated.len <= 40000 * (depth + 1)
		assert generated.count(' := fn [') <= 5 * (depth + 1)
		if os.getenv('VML_BOUNDS_KEEP_FIXTURES') == '1' {
			os.write_file(os.join_path(os.vtmp_dir(), 'named_growth_${depth}.generated.v'), generated)!
			os.write_file(os.join_path(os.vtmp_dir(), 'named_growth_${depth}.vml'), source)!
		}
	}
}
