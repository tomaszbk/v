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
	module_name, imports := parser.parse_vml_directives()!
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

fn (mut parser VmlSourceParser) parse_vml_directives() !(string, []VmlToken) {
	mut module_name := ''
	mut imports := []VmlToken{}
	for parser.at().text in ['module', 'import'] {
		directive := parser.take(.name)!
		name := parser.take(.name)!
		if directive.text == 'module' {
			if module_name.len > 0 {
				return error('${parser.file}:${directive.line}:${directive.column}: duplicate module declaration')
			}
			module_name = name.text
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
fn vml_remap_import_root(node &VmlNode, old_id string, new_id string) &VmlNode {
	mut properties := []VmlProperty{cap: node.properties.len}
	for property in node.properties {
		properties << VmlProperty{ ...property, expr: vml_remap_root_expr(property.expr, old_id, new_id) }
	}
	mut children := []&VmlNode{cap: node.children.len}
	for child in node.children {
		// A nested import exporting the same id owns that name in its subtree.
		children << if child.imported && child.id == old_id {
			vml_clone_node(child)
		} else {
			vml_remap_import_root(child, old_id, new_id)
		}
	}
	return &VmlNode{ ...node, properties: properties, children: children }
}

fn vml_remap_root_expr(expr &VmlExpr, old_id string, new_id string) &VmlExpr {
	if isnil(expr) { return expr }
	value := if expr.kind in [.path, .call] && (expr.value == old_id || expr.value.starts_with(old_id + '.')) {
		new_id + expr.value[old_id.len..]
	} else {
		expr.value
	}
	mut parts := []VmlInterpolationPart{cap: expr.parts.len}
	for part in expr.parts {
		parts << VmlInterpolationPart{ ...part, expr: vml_remap_root_expr(part.expr, old_id, new_id) }
	}
	return &VmlExpr{
		...expr
		value: value
		left:  vml_remap_root_expr(expr.left, old_id, new_id)
		right: vml_remap_root_expr(expr.right, old_id, new_id)
		third: vml_remap_root_expr(expr.third, old_id, new_id)
		args:  expr.args.map(vml_remap_root_expr(it, old_id, new_id))
		parts: parts
	}
}

fn expand_compiled_vml_import(node &VmlNode, modules map[string]&VmlNode) !&VmlNode {
	mut result := vml_clone_node(node)
	if imported := modules[node.tag] {
		result = vml_clone_node(imported)
		result.imported = true
		if node.id.len > 0 && result.id.len > 0 && node.id != result.id {
			result = vml_remap_import_root(result, result.id, node.id)
		}
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
