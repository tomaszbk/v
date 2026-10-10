module parser

fn test_compiled_keyed_list_updates_keep_the_repeater_location() {
	mut root := parse_vml_source('Column {\n    Repeater(model: app.rows, key: item) { Label(text: item) }\n}')!
	vml_set_source(mut root, 'rows.vml')
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains("}) or { panic('rows.vml:2:5: ' + err.msg()) }"), generated
	bound := generated.split_into_lines().filter(it.contains('.bind(fn '))[0]
	assert bound.ends_with("source: 'rows.vml', line: 2, column: 5) or { panic(err) }"), bound
}

fn test_compiled_static_children_keep_the_container_location() {
	mut root := parse_vml_source('View { Button(key: "same") Button(key: "same") }')!
	vml_set_source(mut root, 'siblings.vml')
	mut compiler := VmlCompiler{}
	generated := compiler.compile(root)
	created := generated.split_into_lines().filter(it.contains('vml_root_component.element(vml_declaration_0,'))[0]
	assert created.ends_with("or { panic('siblings.vml:1:1: ' + err.msg()) }"), created
	parent := generated.split_into_lines().filter(it.contains('vml_node_0.set_element_children'))[0]
	assert parent.ends_with("or { panic('siblings.vml:1:1: ' + err.msg()) }"), parent
}
