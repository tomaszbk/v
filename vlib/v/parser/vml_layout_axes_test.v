module parser

fn test_vml_retained_nodes_record_dimension_presence_including_zero() {
	for source, flags in {
		'Label(text: "auto")':                                      'authored_width: false, authored_height: false'
		'Label(width: 0)':                                          'authored_width: true, authored_height: false'
		'Label(height: 0)':                                         'authored_width: false, authored_height: true'
		'Grid(width: 0, height: app.height, columns: 2) { Label }': 'authored_width: true, authored_height: true'
	} {
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{ uses_app: true }
		generated := compiler.compile(root)
		assert generated.contains(flags), generated
	}
}

fn test_vml_generic_content_marks_omitted_inherited_axes_separately_from_layout_allocation() {
	root := parse_vml_source('Row { View { View(width: 0) { Label } } }')!
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	lines := generated.split_into_lines().filter(it.contains('.element(vml_declaration_'))
	assert lines.len == 4, generated
	assert lines[0].contains('authored_width: false, authored_height: false, inherit_width: true, inherit_height: true'), lines[0]
	assert lines[1].contains('authored_width: true, authored_height: false, inherit_width: false, inherit_height: true'), lines[1]
	assert lines[2].contains('authored_width: false, authored_height: false, inherit_width: false, inherit_height: false'), lines[2]
}
