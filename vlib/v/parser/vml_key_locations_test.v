module parser

import vml

fn test_keyed_repeaters_keep_the_repeater_location() {
	mut root := parse_vml_source('Column {\n    Repeater(model: app.rows, key: item) { Label(text: item) }\n}')!
	vml.set_source(mut root, 'rows.vml')
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	assert generated.contains("}, source: 'rows.vml', line: 2, column: 5) or { panic(err) }"), generated
}

fn test_declared_nodes_keep_their_own_location() {
	mut root := parse_vml_source('View { Button(key: "same") Button(key: "same") }')!
	vml.set_source(mut root, 'siblings.vml')
	mut compiler := VmlCompiler{}
	generated := compiler.lower(root)
	assert generated.contains("path: '0', src: ui2.VmlSourceLocation{source: 'siblings.vml', line: 1, column: 1}"), generated
	assert generated.contains("path: '0.0', key: 'same', src: ui2.VmlSourceLocation{source: 'siblings.vml', line: 1, column: 8}"), generated
	assert generated.contains("path: '0.1', key: 'same', src: ui2.VmlSourceLocation{source: 'siblings.vml', line: 1, column: 28}"), generated
}
