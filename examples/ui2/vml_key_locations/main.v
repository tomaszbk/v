module main

import os
import ui2

@[heap]
pub struct KeyModel {
pub mut:
	rows []string = ['first', 'second']
}

fn build(mut app KeyModel) ui2.Element {
	return $vml('rows.vml')
}

fn main() {
	mut app := &KeyModel{}
	if '--duplicate-key' in os.args {
		app.rows = ['same', 'same']
	} else if '--empty-key' in os.args {
		app.rows = ['']
	} else if '--duplicate-sibling' in os.args {
		_ = $vml('siblings.vml')
		return
	}
	root := build(mut app)
	assert root.children.len == 2
	assert root.children.map(it.text) == ['first', 'second']
	if '--duplicate-update' in os.args {
		app.rows = ['same', 'same']
		root.compiled_node.component.invalidate_app() or { panic(err) }
		return
	}
	app.rows.reverse_in_place()
	root.compiled_node.component.invalidate_app() or { panic(err) }
	updated := root.compiled_node.element()
	assert updated.children.map(it.text) == ['second', 'first']
	assert updated.children[1].compiled_node == root.children[0].compiled_node
	println('Valid keyed VML reorder preserves nodes')
}
