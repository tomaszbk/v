module parser

import os
import v.pref
import vml

// Every generated line maps to a VML location, so V reports errors in the
// lowered code at the document.
fn test_lowered_documents_map_every_generated_line() {
	mut root := parse_vml_source('Grid(
    columns: 2,
) {
    View(
        id: "local",
    ) {
        Button(on_click: app.record(app.count +(5)))
    }
    Label {
        Run(text: "mapped")
    }
    Repeater(model: app.rows, key: item.id) { Label(text: item.name, x: local.width) }
}')!
	vml.set_source(mut root, 'combined.vml')
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	assert generated.contains('.callback(fn [')
	assert compiler.locations.len == generated.count('\n')
	for location in compiler.locations {
		assert location.path == 'combined.vml'
	}
}

fn test_lowered_documents_are_valid_v_syntax() {
	root_path := os.join_path(os.vtmp_dir(), 'vml_lower_syntax_${os.getpid()}')
	os.mkdir_all(root_path)!
	defer { os.rmdir_all(root_path) or {} }
	for index, source in [
		'Label(
    style: [font_size(18), weight(700)],
) {
    Run(text: "Parent")
    Run(text: "Override", style: [font_size(12), weight(400)])
}',
		'Row(width: 200, height: app.height) { Label(text: "One", flex_grow: 1) }',
		'component Card(title string, content slot) { Column(id: "card") { Label(text: title) Slot {} } }',
		'Column { Repeater(model: app.rows, key: item.id) { Label(text: "\${index}: \${item.name}") } }',
	] {
		root := parse_vml_source(source)!
		mut compiler := VmlCompiler{ uses_app: true }
		path := os.join_path(root_path, '${index}.v')
		generated := compiler.lower(root)
		// Guards are declarations after the builder expression.
		builder := generated.all_before_last('})(ui2.vml_bounds())') + '})(ui2.vml_bounds())'
		os.write_file(path, 'fn main() {\n\tmut app := 0\n\t_ = app\n\t_ = ${builder}\n}\n' + generated.all_after_last('})(ui2.vml_bounds())'))!
		mut parser := Parser.new(pref.new_preferences())
		parser.parse_file(path)
		assert parser.diagnostics.len == 0, parser.diagnostics.str()
	}
}

fn test_vml_parser_diagnostic_points_to_vml_file_and_call_site() {
	root := os.join_path(os.vtmp_dir(), 'vml_lower_diagnostics_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(view, 'Column {\n    Repeater(model: app.rows) { Label() }\n}')!
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	mut parser := Parser.new(pref.new_preferences())
	parser.parse_file(source)
	assert parser.diagnostics.len == 1, parser.diagnostics.str()
	diagnostic := parser.diagnostics[0]
	assert os.real_path(diagnostic.file) == os.real_path(view)
	assert diagnostic.line == 2
	assert diagnostic.column == 5
	assert diagnostic.message.contains('Repeater requires a stable `key`')
	assert diagnostic.pos.id in parser.a.template_call_sites
}
