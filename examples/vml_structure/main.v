module main

import ui2
import os

struct Row {
pub:
	id   int
	name string
}

// RowContract exposes the row schema used by an interface array.
pub interface RowContract {
	id   int
	name string
}

struct Group {
pub:
	id   string
	rows []Row
}

struct App {
mut:
	menus_installed bool
pub mut:
	interface_rows []RowContract
	pointer_rows   []&Row
	rows           []Row
	groups         []Group
	selected       int
	count          int
	message        string = 'Español: niño, café'
	enabled        bool
	checked_copy   bool
	level          f64
	last_level     f64
	quantity       int
	last_quantity  int
	copied         string
}

// select records the selected row.
pub fn (mut app App) select(id int) { app.selected = id }

fn build(mut app App) ui2.Element { return $vml('structure.vml') }

fn parity(mut app App) ui2.Element { return $vml('parity.vml') }

fn menus(mut app App) []ui2.Menu { return $vml('menus.vml') }

fn nested(mut app App) ui2.Element { return $vml('nested.vml') }

// reorder reverses rows while keeping their business keys.
pub fn (mut app App) reorder() { app.rows.reverse_in_place() }

fn window_build(mut app App) ui2.Element {
	if !app.menus_installed {
		app.menus_installed = true
		ui2.set_menu_bar(menus(mut app))
	}
	return $vml('window.vml')
}

fn schemas(mut app App) ui2.Element { return $vml('schemas.vml') }

fn bindings(mut app App) ui2.Element { return $vml('bindings.vml') }

fn named_binding(mut app App) ui2.Element { return $vml('named.vml') }

fn named_change(event ui2.ElementEvent) {
	assert event.text == 'niño'
}

// select_text records the value observed after a binding write.
pub fn (mut app App) select_text(value string) { app.copied = value }

fn invalid_siblings() ui2.Element { return $vml('invalid_siblings.vml') }

fn main() {
	mut app := &App{ rows: [Row{1, 'First'}, Row{2, 'Second'}] }
	if '--duplicate-key' in os.args {
		app.rows = [Row{1, 'first'}, Row{1, 'duplicate'}]
		_ = build(mut app)
		return
	}
	if '--empty-key' in os.args {
		app.groups = [Group{'', [Row{1, 'empty'}]}]
		_ = nested(mut app)
		return
	}
	if '--duplicate-sibling' in os.args {
		_ = invalid_siblings()
		return
	}
	root := build(mut app)
	root.children[4].on_event(ui2.ElementEvent{ kind: .change, text: 'Mañana' })
	root.children[5].on_event(ui2.ElementEvent{ kind: .click })
	assert app.message == 'Mañana' && app.copied == 'Mañana' && app.count == 1
	declarations := menus(mut app)
	declarations[0].items[0].on_select(ui2.ElementEvent{ kind: .click, id: 'create' })
	assert app.count == 2
	if '--window' in os.args {
		ui2.run_compiled_vml(
			model:  app
			build:  window_build
			title:  'Compiled VML structure'
			width:  620
			height: 480
		)!
	}
	println('compiled VML: nested imports, keyed rows, typed callbacks, assignments and menus')
}
