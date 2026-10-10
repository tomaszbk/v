// vtest build: ui2_tests?
// Requires the ui2 module; opt in with -d ui2_tests.
module main

import ui2

pub struct AliasRow {
pub:
	id    string
	width f64
}

@[heap]
pub struct AliasApp {
pub mut:
	level f64
	rows  []AliasRow
	refs  map[string]&ui2.VmlRef[ui2.VmlView]
}

// remember stores each keyed component's root ref for identity checks after reconciliation.
pub fn (mut app AliasApp) remember(name string, reference &ui2.VmlRef[ui2.VmlView]) {
	app.refs[name] = reference
}

fn alias_tree(mut app AliasApp) ui2.Element { return $vml('aliases.vml') }

fn keyed_alias_tree(mut app AliasApp) ui2.Element { return $vml('keyed.vml') }

fn test_invocation_ids_alias_real_private_anonymous_and_nested_roots() ! {
	mut app := &AliasApp{ rows: [AliasRow{'a', 10}] }
	initial := alias_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	children := root.element().children
	assert children[0].id == root.component.namespace + ':' + 'card'.bytes().hex()
	assert children[0].frame.width == 77
	for index, width in [f64(100), 200, 77] {
		child := children[index + 1]
		assert child.kind == .view
		assert child.frame.width == width && child.frame.height == width + 1
		assert child.key == ['first-key', 'second-key', 'third-key'][index]
	}
	assert children[1].frame.x == 12 && children[1].frame.y == 13
	assert children[1].id == children[1].compiled_node.component.namespace + ':' + 'card'.bytes().hex()
	assert children[2].id == ''
	assert children[3].id == children[3].compiled_node.component.namespace + ':' + 'card'.bytes().hex()
	assert children[1].id != children[3].id
	assert children[1].children[0].text == 'root=${f64(100)}'
	assert children[3].children[0].text == 'root=${f64(77)}'
	assert children[4].frame.width == 100 && children[4].frame.height == 201
	assert children[4].frame.x == 77
	assert children[6].text == f64(100).str()
	children[1].children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.level == 100
	assert root.element().children[1].children[2].text == '1'
	assert root.element().children[3].children[2].text == '0'
	children[5].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.level == 301
	mut owner := root.component
	mut named := owner.ref[ui2.VmlView]('named')!
	mut anonymous := owner.ref[ui2.VmlView]('anonymous')!
	mut nested := owner.ref[ui2.VmlView]('nested')!
	assert named.element()!.compiled_node == children[1].compiled_node
	assert anonymous.element()!.compiled_node == children[2].compiled_node
	assert nested.element()!.compiled_node == children[3].compiled_node
	assert named.id()! == children[1].id
	assert anonymous.id()! == ''
	mut actual := children[1].compiled_node
	actual.set_frame(ui2.rect(0, 0, 150, 151))!
	assert root.element().children[1].compiled_node == actual
	assert root.element().children[4].frame.width == 150
	assert root.element().children[6].text == f64(150).str()
	root.element().children[5].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.level == 351
	root.dispose_document()!
	assert !named.is_available() && !anonymous.is_available() && !nested.is_available()
}

fn test_invocation_keys_reconcile_actual_roots_and_preserve_private_state() ! {
	mut app := &AliasApp{ rows: [AliasRow{'a', 100}, AliasRow{'b', 200}] }
	initial := keyed_alias_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	first := root.element().children[0]
	second := root.element().children[1]
	a_ref := app.refs['a'] or { panic('missing a ref') }
	b_ref := app.refs['b'] or { panic('missing b ref') }
	assert first.key == 'a' && second.key == 'b'
	assert a_ref.element()!.compiled_node == first.compiled_node
	assert b_ref.element()!.compiled_node == second.compiled_node
	first.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	first.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	second.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	app.rows = [AliasRow{'b', 250}, AliasRow{'a', 150}]
	root.component.invalidate_app()!
	reordered := root.element().children
	assert reordered[0].compiled_node == second.compiled_node
	assert reordered[1].compiled_node == first.compiled_node
	assert reordered[0].key == 'b' && reordered[1].key == 'a'
	assert a_ref.element()!.compiled_node == reordered[1].compiled_node
	assert b_ref.element()!.compiled_node == reordered[0].compiled_node
	assert reordered[0].children[2].text == '1' && reordered[1].children[2].text == '2'
	assert reordered[0].frame.width == 250 && reordered[1].frame.width == 150
	app.rows = app.rows[..1]
	root.component.invalidate_app()!
	assert first.compiled_node.component.is_disposed()
	assert !a_ref.is_available() && b_ref.is_available()
	assert root.element().children[0].compiled_node == second.compiled_node
	root.dispose_document()!
	assert !b_ref.is_available()
}
