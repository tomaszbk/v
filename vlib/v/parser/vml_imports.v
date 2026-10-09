module parser

import os

// File imports are tree reuse, not component instances with private state.
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
	mut module_name := ''
	mut imports := []VmlToken{}
	for parser.at().text in ['module', 'import'] {
		directive := parser.take(.name)!
		name := parser.take(.name)!
		if directive.text == 'module' {
			if module_name.len > 0 {
				return error('${file}:${directive.line}:${directive.column}: duplicate module declaration')
			}
			module_name = name.text
		} else {
			if imports.any(it.text == name.text) {
				return error('${file}:${name.line}:${name.column}: duplicate VML import `${name.text}`')
			}
			imports << name
		}
	}
	if expected_module.len > 0 && module_name != expected_module {
		return error('${file}:1:1: VML import `${expected_module}` requires `module ${expected_module}`')
	}
	mut root := parser.parse_node() or { return error('${file}: ${err}') }
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
	validate_compiled_vml_node(root)!
	return root
}

fn compiled_vml_import_path(directory string, name string) !string {
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
	for candidate in [os.join_path(directory, '${name}.vml'), os.join_path(directory, '${snake}.vml')] {
		if os.is_file(candidate) { return candidate }
	}
	return error('could not find VML import `${name}`')
}

fn vml_set_source(mut node VmlNode, path string) {
	node.source = path
	for property in node.properties { vml_set_expr_source(mut property.expr, path) }
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

fn expand_compiled_vml_import(node &VmlNode, modules map[string]&VmlNode) !&VmlNode {
	mut result := vml_clone_node(node)
	if imported := modules[node.tag] {
		result = vml_clone_node(imported)
		result.imported = true
		for override in node.properties {
			result.properties = result.properties.filter(it.name != override.name)
			result.properties << override
		}
		if node.id.len > 0 {
			result.id = node.id
			result.import_id = true
		}
		// Imported descendants were resolved in their defining document. Only
		// invocation children belong to the caller's module scope.
		for child in node.children {
			result.children << expand_compiled_vml_import(child, modules)!
		}
		return result
	}
	mut children := []&VmlNode{}
	for child in result.children { children << expand_compiled_vml_import(child, modules)! }
	result.children = children
	return result
}
