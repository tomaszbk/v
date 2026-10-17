module vml

import os

// parse_file parses the document at `path` and, recursively, the documents it
// imports. `import Name` resolves to `Name.vml` or its snake_case form
// (`TodoItem` to `todo_item.vml`) next to the importing file; an imported file
// must end with `component Name(...)`. Import cycles, missing files and mismatched names are
// errors positioned in the importing file. `Node.source` is set to the real path
// of each document, and `config.validate_document` runs for every document.
pub fn parse_file(path string, config ParseConfig) !&Node {
	return parse_file_in(path, '', [], config)
}

// Imports resolve explicit component signatures in their defining lexical scope.
fn parse_file_in(path string, expected_module string, stack []string, config ParseConfig) !&Node {
	file := os.real_path(path)
	mut next_stack := stack.clone()
	next_stack << file
	if file in stack {
		return error('${file}:1:1: cyclic VML import: ${next_stack.join(' -> ')}')
	}
	source := read_source(file, config) or { return error('${file}:1:1: ${err}') }
	tokens := tokenize(source) or { return error('${file}: ${err}') }
	mut parser := Parser{ tokens: tokens, file: file, config: config }
	imports := parser.parse_directives()!
	mut root := parser.parse_document()!
	if expected_module != '' && root.component_name != expected_module {
		return error('${file}:1:1: VML import `${expected_module}` requires `component ${expected_module}(...)`')
	}
	parser.take(.eof) or { return error('${file}: ${err}') }
	set_source(mut root, file)
	mut modules := map[string]&Node{}
	for name in imports {
		import_path := resolve_import(os.dir(file), name.text, config) or {
			return error('${file}:${name.line}:${name.column}: ${err}')
		}
		modules[name.text] = parse_file_in(import_path, name.text, next_stack, config)!
	}
	root = expand_imports(root, modules)!
	if validate := config.validate_document { validate(root, expected_module != '')! }
	return root
}

// parse_directives parses the leading `import Name` directives and returns the
// imported name tokens. `module` directives are rejected.
pub fn (mut parser Parser) parse_directives() ![]Token {
	mut imports := []Token{}
	for parser.at().text in ['module', 'import'] {
		directive := parser.take(.name)!
		name := parser.take(.name)!
		if directive.text == 'module' {
			return error('${parser.file}:${directive.line}:${directive.column}: module declarations were replaced by component signatures')
		} else {
			if imports.any(it.text == name.text) {
				return error('${parser.file}:${name.line}:${name.column}: duplicate VML import `${name.text}`')
			}
			imports << name
		}
	}
	return imports
}

fn resolve_import(directory string, name string, config ParseConfig) !string {
	for candidate in import_resolution_candidates(directory, name)! {
		if source_exists(candidate, config) { return candidate }
	}
	return error('could not find VML import `${name}`')
}

fn read_source(path string, config ParseConfig) !string {
	if read := config.read_file {
		return read(path)
	}
	return os.read_file(path)
}

fn source_exists(path string, config ParseConfig) bool {
	if is_file := config.is_file {
		return is_file(path)
	}
	return os.is_file(path)
}

// import_candidates returns each import's ordered lookup paths for
// cache dependency tracking, using the same directives and resolver as lowering.
pub fn import_candidates(source string, directory string) ![][]string {
	mut parser := Parser{ tokens: tokenize(source)! }
	imports := parser.parse_directives()!
	mut result := [][]string{}
	for name in imports { result << import_resolution_candidates(directory, name.text)! }
	return result
}

fn import_resolution_candidates(directory string, name string) ![]string {
	// Import names cannot escape the importing document's directory.
	if name.split('.').any(it.len == 0) || name.contains('#') {
		return error('invalid VML import `${name}`')
	}
	mut snake := ''
	for index, ch in name {
		if ch >= `A` && ch <= `Z` {
			if index > 0 { snake += '_' }
			snake += [ch].bytestr().to_lower()
		} else if ch == `.` {
			snake += os.path_separator
		} else {
			snake += [ch].bytestr()
		}
	}
	return [os.join_path(directory, '${name}.vml'), os.join_path(directory, '${snake}.vml')]
}

// Remap only the reused definition, before caller overrides/children are added.
// Expression copies keep separate invocations independent and retain locations.
fn expand_imports(node &Node, modules map[string]&Node) !&Node {
	mut result := clone_node(node)
	if imported := modules[node.tag] {
		result = clone_node(imported)
		result.imported = true
		result.properties = node.properties.clone()
		result.id = node.id
		mut content := map[string][]&Node{}
		for input in result.inputs { if input.typ == 'slot' { content[input.name] = []&Node{} } }
		if node.children.len > 0 && content.len == 0 {
			return error('component `${node.tag}` does not declare a content slot')
		}
		if node.children.any(it.tag == 'Slot') {
			for child in node.children {
				if child.tag != 'Slot' {
					return error('named slot content requires Slot(name: "name") blocks')
				}
				name := if property := find_property(child, 'name') {
					property.expr.value
				} else {
					'content'
				}
				if name !in content { return error('unknown component slot `${name}`') }
				mut values := content[name] or { []&Node{} }
				for value in child.children {
					values << expand_imports(value, modules)!
				}
				content[name] = values
			}
		} else if node.children.len > 0 {
			if 'content' !in content {
				return error('implicit content requires a slot named `content`')
			}
			mut values := content['content'] or { []&Node{} }
			for child in node.children { values << expand_imports(child, modules)! }
			content['content'] = values
		}
		result.children[0] = expand_slots(result.children[0], content)!
		return result
	}
	mut children := []&Node{}
	for child in result.children { children << expand_imports(child, modules)! }
	result.children = children
	return result
}

fn expand_slots(node &Node, content map[string][]&Node) !&Node {
	mut result := clone_node(node)
	mut children := []&Node{}
	for child in result.children {
		if child.tag == 'Slot' {
			name := if property := find_property(child, 'name') {
				property.expr.value
			} else {
				'content'
			}
			supplied := content[name] or { return error('unknown slot `${name}`') }
			for value in supplied {
				children << &Node{ ...clone_node(value), caller_content: true }
			}
		} else if child.tag == component_tag {
			children << child
		} else {
			children << expand_slots(child, content)!
		}
	}
	result.children = children
	return result
}
