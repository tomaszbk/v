module parser

import vml

fn test_input_default_factory_keeps_the_declared_input_position() {
	mut root := parse_vml_source('component Typed(valid bool = app.count) { Label(text: "value") }')!
	vml.set_source(mut root, 'defaults.vml')
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	lines := generated.split_into_lines()
	for index, line in lines {
		if line.contains(".state_factory('valid'") {
			assert compiler.locations[index].path == 'defaults.vml'
			assert compiler.locations[index].line == 1
			assert compiler.locations[index].column == 17
			return
		}
	}
	assert false, generated
}

// A reactive property evaluates its expression in one setter; static ones
// are fields of the props literal and never reevaluate.
fn test_reactive_properties_are_setters_and_static_properties_fields() {
	root := parse_vml_source('Absolute { View(id: "box", width: app.width, height: box.width * 2, x: 4) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.lower(root)
	assert generated.contains('\t\tx: 4\n'), generated
	assert generated.count('= app.width') == 1, generated
	assert generated.contains("vml_node_0_0.prop('width', fn [mut app, mut vml_root_component] (mut vml_p ui2.ViewProps) ! { vml_root_component.watch_app()!; vml_p.width = app.width })"), generated
	assert generated.contains("vml_node_0_0.prop('height', fn [vml_node_0_0] (mut vml_p ui2.ViewProps) ! { vml_p.height = ((vml_node_0_0.geometry() or { panic(err) }).width * 2) })"), generated
}
