module parser

// Generated closures capture locals conservatively from the VML scope. Each
// captured local must be marked used, because `-prod` rejects unused variables.
fn test_vml_closures_mark_every_capture_used() {
	mut root := parse_vml_source('Screen(id: "root") {
    Absolute(id: "canvas") {
        Label(id: "title", text: "count \${app.count}", x: 8, y: 8, width: root.width - 32, height: 24)
        View(x: 8, y: 40, width: canvas.width - 16, height: title.height * 2)
        Repeater(model: app.rows, key: item.id) {
            Button(text: item.name, x: item.x, y: item.y + title.height, width: root.width / 4,
                height: 12, on_tap: app.select(item.id))
        }
    }
}')!
	vml_set_source(mut root, 'captures.vml')
	mut compiler := VmlCompiler{
		uses_app: true
	}
	generated := compiler.compile(root)
	mut closures := 0
	mut start := 0
	for {
		open := generated.index_after('fn [', start) or { break }
		close := generated.index_after(']', open) or { break }
		body := generated.index_after('{', close) or { break }
		line_end := generated.index_after('\n', body) or { generated.len }
		opening := generated[body + 1..line_end]
		start = body
		if generated[close..body].contains('vml_template_frame') {
			// The document wrapper always reads `app`.
			continue
		}
		captures := generated[open + 4..close].split(', ').filter(it.len > 0)
		for capture in captures {
			name := capture.trim_string_left('mut ')
			assert opening.contains('_ = ${name};'), 'closure capture `${name}` is not marked used: ${generated[open..line_end]}'
		}
		closures++
	}
	assert closures > 0
	// Captures that a closure body does not otherwise reference must still be marked used.
	assert generated.contains('vml_property_')
}
