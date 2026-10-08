module main

import ui2

@[heap]
struct VisualApp {
pub mut:
	count int
	name  string = 'niñez'
}

// tap increments the example's counter.
pub fn (mut app VisualApp) tap() {
	app.count++
}

// submit records submission without changing the input's identity.
pub fn (mut app VisualApp) submit() {
	app.count += 10
}

fn build(mut app VisualApp) ui2.Element {
	return $vml('showcase.vml')
}

fn main() {
	ui2.run_compiled_vml(ui2.CompiledVmlRunConfig[VisualApp]{
		model:  VisualApp{}
		build:  build
		title:  'Compiled VML visual primitives'
		width:  760
		height: 540
	}) or { panic(err) }
}
