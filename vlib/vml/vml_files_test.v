// File-level tests for the shared VML parser: imports, injected file IO,
// document validation hooks and representative ui2 documents in testdata.
import os
import vml

const testdata = os.join_path(os.dir(@FILE), 'testdata')

fn write_files(name string, files map[string]string) !string {
	dir := os.join_path(os.vtmp_dir(), 'vml_files_test_${os.getpid()}_${name}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	for path, content in files {
		os.write_file(os.join_path(dir, path), content)!
	}
	return os.real_path(dir)
}

fn file_error(path string) string {
	vml.parse_file(path) or { return err.msg() }
	return ''
}

struct Recorder {
mut:
	items []string
}

fn test_imports_resolve_next_to_the_importing_file() {
	dir := write_files('resolve', {
		'main.vml':      'import Card\nimport TodoItem\nColumn {\n    Card(title: "x") { Label(text: app.name) }\n    TodoItem\n}'
		'Card.vml':      'component Card(title string, content slot) { View { Slot {} } }'
		'todo_item.vml': 'component TodoItem() { Label(text: "t") }'
	})!
	defer { os.rmdir_all(dir) or {} }
	main := os.join_path(dir, 'main.vml')
	card := os.join_path(dir, 'Card.vml')
	mut recorder := &Recorder{}
	root := vml.parse_file(main,
		validate_document: fn [mut recorder] (root &vml.Node, imported bool) ! {
			name := if root.tag == vml.component_tag { root.component_name } else { root.tag }
			recorder.items << '${name} ${imported} ${os.file_name(root.source)}'
		}
	)!
	// Imported documents are validated first, each once.
	assert recorder.items == ['Card true Card.vml', 'TodoItem true todo_item.vml',
		'Column false main.vml']
	assert root.tag == 'Column'
	assert root.source == main
	invocation := root.children[0]
	assert invocation.tag == vml.component_tag
	assert invocation.imported
	assert invocation.component_name == 'Card'
	// An expanded invocation is positioned at its definition; the caller's
	// arguments and slot content keep their own locations.
	assert invocation.source == card
	assert invocation.line == 1 && invocation.column == 1
	assert invocation.properties[0].line == 4 && invocation.properties[0].column == 10
	assert invocation.properties[0].expr.source == main
	view := invocation.children[0]
	assert view.source == card
	assert view.line == 1 && view.column == 46
	slot_content := view.children[0]
	assert slot_content.caller_content
	assert slot_content.source == main
	assert slot_content.properties[0].expr.source == main
	assert slot_content.line == 4
	assert root.children[1].component_name == 'TodoItem'
	assert vml.import_candidates('import Card\nimport TodoItem\nLabel', dir)! == [
		[os.join_path(dir, 'Card.vml'), os.join_path(dir, 'card.vml')],
		[os.join_path(dir, 'TodoItem.vml'), os.join_path(dir, 'todo_item.vml')],
	]
}

fn test_import_errors_point_at_the_importing_file() {
	dir := write_files('errors', {
		'absent.vml':     'import Missing\nLabel'
		'mismatch.vml':   'import Other\nLabel'
		'Other.vml':      'component Different() { Label }'
		'cycle.vml':      'import A\nA'
		'A.vml':          'import B\ncomponent A() { B }'
		'B.vml':          'import A\ncomponent B() { A }'
		'module.vml':     'module screens\nLabel'
		'duplicate.vml':  'import Other\nimport Other\nLabel'
		'invalid.vml':    'import a..b\nLabel'
		'syntax.vml':     'Column {\n    Label(text: )\n}'
		'lexer.vml':      'Column {\n    Label(text: "open)\n}'
		'trailing.vml':   'Label Label'
		'slotless.vml':   'import Plain\nPlain { Label }'
		'Plain.vml':      'component Plain() { Label }'
		'components.vml': 'component A() { B }\ncomponent B() { A }\nA'
	})!
	defer { os.rmdir_all(dir) or {} }
	p := fn [dir] (name string) string {
		return os.join_path(dir, name)
	}
	assert file_error(p('absent.vml')) == '${p('absent.vml')}:1:8: could not find VML import `Missing`'
	assert file_error(p('mismatch.vml')) == '${p('Other.vml')}:1:1: VML import `Other` requires `component Other(...)`'
	assert file_error(p('cycle.vml')) == '${p('A.vml')}:1:1: cyclic VML import: ${p('cycle.vml')} -> ${p('A.vml')} -> ${p('B.vml')} -> ${p('A.vml')}'
	assert file_error(p('module.vml')) == '${p('module.vml')}:1:1: module declarations were replaced by component signatures'
	assert file_error(p('duplicate.vml')) == '${p('duplicate.vml')}:2:8: duplicate VML import `Other`'
	assert file_error(p('invalid.vml')) == '${p('invalid.vml')}:1:8: invalid VML import `a..b`'
	assert file_error(p('syntax.vml')) == 'expected expression, got rpar (`)`) at line 2'
	assert file_error(p('lexer.vml')) == '${p('lexer.vml')}: unterminated string at line 2'
	assert file_error(p('trailing.vml')) == '${p('trailing.vml')}: ${p('trailing.vml')}:1:7: expected eof, got name (`Label`)'
	assert file_error(p('slotless.vml')) == 'component `Plain` does not declare a content slot'
	assert file_error(p('components.vml')) == 'cyclic VML component: A -> B -> A'
	missing := os.join_path(dir, 'does_not_exist.vml')
	assert file_error(missing).starts_with('${missing}:1:1: ')
}

fn test_validate_document_errors_stop_parsing() {
	dir := write_files('validate', {
		'main.vml': 'import Card\nCard'
		'card.vml': 'component Card() { TextField }'
	})!
	defer { os.rmdir_all(dir) or {} }
	vml.parse_file(os.join_path(dir, 'main.vml'),
		validate_document: fn (root &vml.Node, imported bool) ! {
			if imported {
				return vml.node_error(root.children[0], 'removed widget `${root.children[0].tag}`')
			}
		}
	) or {
		assert err.msg() == '${os.join_path(dir, 'card.vml')}:1:20: removed widget `TextField`'
		return
	}
	assert false
}

fn test_file_io_can_be_injected() {
	files := {
		'/virtual/screens/main.vml':      'import TodoItem\nstyle s = [padding(1)]\nTodoItem(style: [s])'
		'/virtual/screens/todo_item.vml': 'component TodoItem(style ui2.StylePatch = []) { Label(text: "t") }'
	}
	mut recorder := &Recorder{}
	config := vml.ParseConfig{
		read_file: fn [files, mut recorder] (path string) !string {
			recorder.items << 'read ${path}'
			return files[path] or { error('no such file') }
		}
		is_file:   fn [files, mut recorder] (path string) bool {
			recorder.items << 'probe ${path}'
			return path in files
		}
	}
	root := vml.parse_file('/virtual/screens/main.vml', config)!
	assert recorder.items == ['read /virtual/screens/main.vml', 'probe /virtual/screens/TodoItem.vml',
		'probe /virtual/screens/todo_item.vml', 'read /virtual/screens/todo_item.vml']
	assert root.component_name == 'TodoItem'
	assert root.source == '/virtual/screens/todo_item.vml'
	assert root.properties[0].expr.source == '/virtual/screens/main.vml'
	assert vml.expr_text(root.properties[0].expr) == '[[padding(1)]]'
	vml.parse_file('/virtual/screens/other.vml', config) or {
		assert err.msg() == '/virtual/screens/other.vml:1:1: no such file'
		return
	}
	assert false
}

fn test_ui2_documents_parse() {
	mut recorder := &Recorder{}
	config := vml.ParseConfig{
		validate_document: fn [mut recorder] (root &vml.Node, imported bool) ! {
			recorder.items << '${os.file_name(root.source)} ${imported}'
		}
	}
	for name in os.ls(testdata)!.sorted() {
		vml.parse_file(os.join_path(testdata, name), config) or { assert false, '${name}: ${err}' }
	}
	assert recorder.items.len == 15
	assert 'counter.vml true' in recorder.items
	assert 'counter_app.vml false' in recorder.items
}

fn test_counter_example() {
	root := vml.parse_file(os.join_path(testdata, 'counter_app.vml'))!
	assert root.tag == 'Screen' && root.id == 'root'
	row := root.children[0].children[0]
	assert row.children.map(it.id) == ['first', 'second']
	first := row.children[0]
	assert first.component_name == 'Counter' && first.imported
	assert first.properties.map(it.name) == ['id', 'title', 'on_changed']
	assert first.inputs.map('${it.name} ${it.typ}') == ['title string', 'changed event']
	assert first.inputs[1].parameters.map('${it.name} ${it.typ}') == ['value int']
	assert first.data.map(it.name) == ['count', 'doubled']
	assert first.functions.map(it.name) == ['increment']
	assert first.mount.len == 1 && first.cleanup.len == 1 && first.unmount.len == 1
	assert first.styles.map(it.name) == ['surface']
	panel := first.children[0]
	assert panel.id == 'panel'
	style := vml.find_property(panel, 'style') or { panic('panel style') }
	assert vml.expr_text(style.expr) == '[[background(#FFFFFF), padding(12), radius(10)]]'
	reset := panel.children[3].children[1]
	assert vml.expr_text(reset.properties[2].expr) == '{count = 0; changed(count)}'
	caption := root.children[0].children[1].properties[0].expr
	assert caption.kind == .interpolation
	assert caption.parts.filter(!isnil(it.expr)).map(it.expr.value) == ['app.events', 'app.last_value']
}

fn test_bindings_refs_and_slots_example() {
	root := vml.parse_file(os.join_path(testdata, 'contract.vml'))!
	first := root.children[0].children[0]
	assert first.component_name == 'Editor'
	assert first.properties.map(it.name) == ['id', 'bind.name', 'on_changed']
	assert first.inputs.map(it.bindable) == [true, false, false]
	assert first.refs.map('${it.name} ${it.typ}') == ['field TextInput']
	column := first.children[0]
	assert column.children.map(it.tag) == ['TextInput', 'Button', 'Label']
	assert column.children[2].caller_content && column.children[2].id == 'slot'
	keyed := vml.parse_file(os.join_path(testdata, 'keyed.vml'))!
	repeater := keyed.children[0].children[1]
	assert repeater.tag == 'Repeater'
	assert repeater.properties.map(vml.expr_text(it.expr)) == ['app.rows', 'item.id']
	row := repeater.children[0]
	assert row.component_name == 'RowItem'
	assert row.data.map(vml.expr_text(it.expr)) == ['app.new_counter()']
	assert row.children[0].children[2].caller_content
	named := vml.parse_file(os.join_path(testdata, 'named_slots.vml'))!
	assert named.component_name == 'Card'
	assert named.children[0].children.map(vml.expr_text(it.properties[0].expr)) == [
		'title',
		'app.name',
		'app.suffix',
	]
}

fn test_styles_and_menus_examples() {
	styles := vml.parse_file(os.join_path(testdata, 'styles.vml'))!
	assert styles.styles.map(it.name) == ['card', 'emphasized']
	variant := styles.children[2]
	assert variant.id == 'variant'
	assert vml.expr_text(variant.properties[3].expr) == '[app.emphasized ? [[background(color.surface), padding(spacing.medium), radius(radius.medium)], background(color.accent), radius(0)] : [background(color.surface), padding(spacing.medium), radius(radius.medium)], app.patch]'
	button := variant.children[0]
	assert vml.expr_text(button.properties[3].expr) == '[hover([background(color.accent), foreground(#000000)]), pressed([radius(0)])]'
	local := vml.parse_file(os.join_path(testdata, 'styles_local.vml'))!
	assert local.children.map(it.component_name) == ['StyledCard', 'StyledCard']
	assert local.children[0].styles.map(it.name) == ['surface', 'accent']
	view_style := local.children[0].children[0].properties[2].expr
	assert vml.expr_text(view_style) == '[[background(color.surface), padding(spacing.medium), radius(radius.medium)], emphasized ? [background(color.accent), radius(0)] : []]'
	menus := vml.parse_file(os.join_path(testdata, 'menus.vml'))!
	assert menus.tag == 'MenuBar'
	assert menus.children.map(it.properties[0].expr.value) == ['File', 'View']
	assert menus.children[0].children.map(it.tag) == ['MenuItem', 'MenuItem', 'MenuSeparator',
		'MenuItem', 'Menu']
}
