module parser

import os

// Imports resolve explicit component signatures in their defining lexical scope.
fn parse_compiled_vml_file(path string, expected_module string, stack []string) !&VmlNode {
	file := os.real_path(path)
	mut next_stack := stack.clone()
	next_stack << file
	if file in stack {
		return error('${file}:1:1: cyclic VML import: ${next_stack.join(' -> ')}')
	}
	source := os.read_file(file) or { return error('${file}:1:1: ${err}') }
	tokens := tokenize_vml(source) or { return error('${file}: ${err}') }
	mut parser := VmlSourceParser{ tokens: tokens, file: file }
	_, imports := parser.parse_vml_directives()!
	mut root := parser.parse_vml_document()!
	if expected_module.len > 0 && root.component_name != expected_module {
		return error('${file}:1:1: VML import `${expected_module}` requires `component ${expected_module}(...)`')
	}
	parser.take(.eof) or { return error('${file}: ${err}') }
	vml_set_source(mut root, file)
	mut modules := map[string]&VmlNode{}
	for name in imports {
		import_path := compiled_vml_import_path(os.dir(file), name.text) or {
			return error('${file}:${name.line}:${name.column}: ${err}')
		}
		modules[name.text] = parse_compiled_vml_file(import_path, name.text, next_stack)!
	}
	root = expand_compiled_vml_import(root, modules)!
	if root.tag in ['Menu', 'MenuBar'] { validate_compiled_vml_menu(root)! }
	validate_compiled_vml_visual(root, '')!
	validate_compiled_vml_node(root)!
	return root
}

fn (mut parser VmlSourceParser) parse_vml_directives() !(string, []VmlToken) {
	mut module_name := ''
	mut imports := []VmlToken{}
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
	return module_name, imports
}

fn compiled_vml_import_path(directory string, name string) !string {
	for candidate in vml_import_resolution_candidates(directory, name)! {
		if os.is_file(candidate) { return candidate }
	}
	return error('could not find VML import `${name}`')
}

// compiled_vml_import_candidates returns each import's ordered lookup paths for
// cache dependency tracking, using the same directives and resolver as lowering.
pub fn compiled_vml_import_candidates(source string, directory string) ![][]string {
	mut parser := VmlSourceParser{ tokens: tokenize_vml(source)! }
	_, imports := parser.parse_vml_directives()!
	mut result := [][]string{}
	for name in imports { result << vml_import_resolution_candidates(directory, name.text)! }
	return result
}

fn vml_import_resolution_candidates(directory string, name string) ![]string {
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

fn vml_set_source(mut node VmlNode, path string) {
	node.source = path
	for property in node.properties { vml_set_expr_source(mut property.expr, path) }
	for data in node.data { vml_set_expr_source(mut data.expr, path) }
	for input in node.inputs {
		if !isnil(input.default_value) { vml_set_expr_source(mut input.default_value, path) }
	}
	for mut function in node.functions {
		for mut statement in function.body { vml_set_expr_source(mut statement, path) }
	}
	for mut statement in node.mount { vml_set_expr_source(mut statement, path) }
	for mut statement in node.unmount { vml_set_expr_source(mut statement, path) }
	for mut statement in node.cleanup { vml_set_expr_source(mut statement, path) }
	for mut child in node.children { vml_set_source(mut child, path) }
}

fn vml_set_expr_source(mut expr VmlExpr, path string) {
	expr.source = path
	if !isnil(expr.left) { vml_set_expr_source(mut expr.left, path) }
	if !isnil(expr.right) { vml_set_expr_source(mut expr.right, path) }
	if !isnil(expr.third) { vml_set_expr_source(mut expr.third, path) }
	for mut arg in expr.args { vml_set_expr_source(mut arg, path) }
	for part in expr.parts {
		if !isnil(part.expr) { vml_set_expr_source(mut part.expr, path) }
	}
}

fn vml_clone_node(node &VmlNode) &VmlNode {
	return &VmlNode{ ...node, properties: node.properties.clone(), children: node.children.map(vml_clone_node(it)) }
}

// Remap only the reused definition, before caller overrides/children are added.
// Expression copies keep separate invocations independent and retain locations.
fn expand_compiled_vml_import(node &VmlNode, modules map[string]&VmlNode) !&VmlNode {
	mut result := vml_clone_node(node)
	if imported := modules[node.tag] {
		result = vml_clone_node(imported)
		result.imported = true
		result.properties = node.properties.clone()
		result.id = node.id
		mut content := map[string][]&VmlNode{}
		for input in result.inputs { if input.typ == 'slot' { content[input.name] = []&VmlNode{} } }
		if node.children.len > 0 && content.len == 0 {
			return error('component `${node.tag}` does not declare a content slot')
		}
		if node.children.any(it.tag == 'Slot') {
			for child in node.children {
				if child.tag != 'Slot' {
					return error('named slot content requires Slot(name: "name") blocks')
				}
				name := if property := vml_find_property(child, 'name') {
					property.expr.value
				} else {
					'content'
				}
				if name !in content { return error('unknown component slot `${name}`') }
				mut values := content[name] or { []&VmlNode{} }
				for value in child.children {
					values << expand_compiled_vml_import(value, modules)!
				}
				content[name] = values
			}
		} else if node.children.len > 0 {
			if 'content' !in content {
				return error('implicit content requires a slot named `content`')
			}
			mut values := content['content'] or { []&VmlNode{} }
			for child in node.children { values << expand_compiled_vml_import(child, modules)! }
			content['content'] = values
		}
		result.children[0] = expand_vml_slots(result.children[0], content)!
		return result
	}
	mut children := []&VmlNode{}
	for child in result.children { children << expand_compiled_vml_import(child, modules)! }
	result.children = children
	return result
}
