module parser

// Lowered size grows linearly with the document: each node is declared once,
// and named geometry reads do not copy descendants.
fn test_vml_nested_layout_source_has_a_bounded_number_of_leaf_copies() {
	for depth in [1, 2, 4, 8] {
		mut source := 'Label(width: 30, text: "unique_leaf_marker")'
		for _ in 0 .. depth { source = 'Row(align_items: start) { ${source} }' }
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		generated := compiler.lower(root)
		assert generated.count('unique_leaf_marker') == 1, generated
		assert generated.len <= 2000 * (depth + 1), generated.len.str()
	}
}

fn test_vml_named_self_references_do_not_accumulate_descendant_exports() {
	for depth in [1, 2, 4, 8, 16] {
		mut source := 'Label(width: 30, height: 20, text: "named_leaf_marker")'
		for index in 0 .. depth {
			source = 'Row(id: "level_${index}", width: 100, height: 20, align_items: start) {
                Absolute {
                    Label(text: level_${index}.width, width: level_${index}.width, height: 20)
                }
                ${source}
            }'
		}
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{}
		generated := compiler.lower(root)
		assert generated.count('named_leaf_marker') == 1
		assert generated.len <= 3000 * (depth + 1), generated.len.str()
		// Each geometry read captures only the node it reads.
		for line in generated.split_into_lines().filter(it.contains('.geometry()')) {
			assert line.all_after('fn [').all_before(']').split(', ').len == 1, line
		}
	}
}
