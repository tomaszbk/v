module parser

import os
import strings
import v.flat
import vml

// parse_vml_file parses a `$vml` document and its imports with the shared
// grammar. Only the language is validated here: widgets are props types that
// V checks in the lowered code.
fn parse_vml_file(path string) !&vml.Node {
	return vml.parse_file(path, validate_document: validate_vml_document)
}

// parse_vml_source parses a document held in memory, as `parse_vml_file` does.
fn parse_vml_source(source string) !&vml.Node {
	root := vml.parse_source(source, vml.ParseConfig{})!
	validate_vml_node(root)!
	return root
}

fn validate_vml_document(root &vml.Node, imported bool) ! {
	_ = imported
	validate_vml_node(root)!
}

// validate_vml_node checks the language rules V cannot check in the lowered
// code: binding targets are paths, and a Repeater has a model and a key.
fn validate_vml_node(node &vml.Node) ! {
	for property in node.properties {
		// Event payloads keep V's `.name`; property values are typed by their field.
		if !property.name.starts_with('on_') {
			if dotted := vml_dotted_enum(property.expr) {
				return error('${property.expr.source}:${dotted.line}:${dotted.column}: VML enum values omit the dot: use `${dotted.value[1..]}`')
			}
		}
		if property.name.starts_with('bind.') && property.expr.kind != .path {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: `${property.name}` must target a writable path')
		}
	}
	if node.tag == 'Repeater' {
		for property in node.properties {
			if property.name !in ['model', 'key'] {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported `${property.name}` on Repeater')
			}
		}
		if vml.find_property(node, 'model') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires `model`')
		}
		if vml.find_property(node, 'key') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires a stable `key`')
		}
	}
	for child in node.children {
		validate_vml_node(child)!
	}
}

// vml_dotted_enum returns the first `.name` value in `expr`: VML enum values are
// bare names that their property types (`text_align(right)`).
fn vml_dotted_enum(expr &vml.Expr) ?&vml.Expr {
	if expr.kind == .path && expr.value.starts_with('.') {
		return expr
	}
	for child in [expr.left, expr.right, expr.third] {
		if !isnil(child) {
			if found := vml_dotted_enum(child) {
				return found
			}
		}
	}
	for arg in expr.args {
		if found := vml_dotted_enum(arg) {
			return found
		}
	}
	return none
}

// parse_vml_template_expr lowers `$vml('file.vml')` to a builder returning the
// document's `ui2.Element`.
fn (mut p Parser) parse_vml_template_expr(call_start int) flat.NodeId {
	p.next() // vml
	if p.tok != .lpar {
		p.record_diagnostic('expected `(` after `\$vml`', p.tok_pos)
		return p.add_val_id(5, '')
	}
	p.next()
	arg_id := p.expr(.lowest)
	arg := p.resolve_tmpl_path_arg(arg_id)
	mut explicit_frame := flat.empty_node
	if p.tok == .comma {
		p.next()
		explicit_frame = p.expr(.lowest)
	}
	for p.tok != .rpar && p.tok != .eof && p.tok != .semicolon {
		p.next()
	}
	if p.tok == .rpar {
		p.next()
	}
	if arg.len == 0 {
		p.record_diagnostic('`\$vml()` path must be a compile-time string', call_start)
		return p.add_val_id(5, '')
	}
	path := p.resolve_veb_template_path(false, arg)
	if !os.exists(path) {
		p.record_diagnostic('VML file `${path}` does not exist', call_start)
		return p.add_val_id(5, '')
	}
	root := parse_vml_file(path) or {
		p.record_vml_diagnostic(path, os.read_file(path) or { '' }, err.msg(), call_start)
		return p.add_val_id(5, '')
	}
	source_file := p.a.source_files[p.cur_file_id] or { return p.add_val_id(5, '') }
	mut callback_captures := []string{}
	for callback in vml_external_callbacks(root) {
		if p.is_local_binding(callback) { callback_captures << callback }
	}
	mut compiler := VmlCompiler{
		callback_captures: callback_captures
		explicit_frame:    int(explicit_frame) >= 0
		uses_app:          vml.node_uses_path(root, 'app')
		guard_prefix:      'vml_check_${source_file.name.hash()}_${call_start}'
	}
	generated := compiler.lower(root)
	first_node := p.a.nodes.len
	first_diagnostic := p.diagnostics.len
	template := flat.Node{
		value: path
		pos:   p.span_to(call_start)
	}
	mut source_lines := []TemplateSourceLine{}
	mut source_paths := map[string]bool{}
	for location in compiler.locations {
		if location.path !in source_paths {
			source_paths[location.path] = true
			source_lines << TemplateSourceLine{ path: location.path, line: 1 }
		}
	}
	saved_fn := p.cur_fn
	p.cur_fn = ''
	saved_vml_types := p.inside_vml_types
	p.inside_vml_types = true
	stmts := p.parse_stmts_from_source('_ = ${generated}', path, template.pos, source_lines)
	p.inside_vml_types = saved_vml_types
	p.cur_fn = saved_fn
	mut result := flat.empty_node
	if stmts.len > 0 {
		statement := p.a.node(stmts[0])
		if statement.kind == .assign && statement.children_count == 2 {
			result = p.a.child(statement, 1)
		}
		for declaration_id in stmts[1..] {
			// The guard belongs to the calling V module; its body retains VML locations.
			declaration := p.a.node(declaration_id)
			p.a.nodes[int(declaration_id)] = flat.Node{ ...declaration, pos: template.pos }
			p.vml_declarations << declaration_id
		}
	}
	if int(result) < 0 {
		p.record_diagnostic('could not lower VML file `${path}`', call_start)
		result = p.add_val_id(5, '')
	}
	// app denotes the caller's live application. Borrow its storage rather
	// than giving the generated IIFE a mutable closure-owned value copy.
	if compiler.uses_app && int(result) >= 0 && p.a.node(result).kind == .call {
		mut callee := p.a.child(p.a.node(result), 0)
		for p.a.node(callee).kind == .paren { callee = p.a.child(p.a.node(callee), 0) }
		literal := p.a.node(callee)
		if literal.kind == .fn_literal {
			for index in 0 .. literal.children_count {
				capture_id := p.a.child(literal, index)
				capture := p.a.node(capture_id)
				if capture.kind == .ident && capture.value == 'app' {
					p.a.nodes[int(capture_id)].op = .amp
				}
			}
		}
	}
	p.remap_vml_source(first_node, first_diagnostic, compiler.locations)
	if int(explicit_frame) >= 0 && int(result) >= 0 {
		call := p.a.node(result)
		if call.kind == .call && call.children_count >= 2 {
			p.a.children[call.children_start + call.children_count - 1] = explicit_frame
		}
	}
	return result
}

// VmlScope is what a VML expression can name: specials (inputs, state,
// computed values, functions, events, refs, `item`, `index`), element ids
// (the node variable whose geometry `id.width` reads) and writable targets.
struct VmlScope {
mut:
	ids              map[string]string
	special          map[string]string
	writable         map[string]string
	event_parameters map[string][]vml.Parameter
	component        string
}

struct VmlGuard {
	field_name string
	model_path string
	name       string
	array      bool
	location   vml.Location
}

struct VmlCompiler {
	guard_prefix      string
	uses_app          bool
	callback_captures []string
	explicit_frame    bool
mut:
	uses_unreachable bool
	emitted_checks   map[string]bool
	lowered_node     string
	slot_scopes      map[string]VmlScope
	out              strings.Builder
	guards           []VmlGuard
	location         vml.Location
	locations        []vml.Location
}

fn vml_clone_scope(scope VmlScope) VmlScope {
	return VmlScope{
		ids:              scope.ids.clone()
		special:          scope.special.clone()
		writable:         scope.writable.clone()
		event_parameters: scope.event_parameters.clone()
		component:        scope.component
	}
}

fn vml_var(path string) string {
	return path.replace('.', '_').replace('-', '_')
}

fn vml_quote(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$') + "'"
}

fn vml_interpolation_text(value string) string {
	return value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$')
}

fn vml_stringify(expression string) string {
	return "'" + r'$' + '{' + expression + "}'"
}

fn vml_array_literal(elem_type string, values []string) string {
	return if values.len == 0 { '[]${elem_type}{}' } else { '[${values.join(', ')}]' }
}

// resolve_path maps a VML path to V: specials to their getters and
// `id.x/y/width/height` to the node's reactive geometry. It reports whether
// the path was bound; an unbound dotted path is kept for V to resolve.
fn (c &VmlCompiler) resolve_path(path string, scope VmlScope) (string, bool) {
	parts := path.split('.')
	if replacement := scope.special[parts[0]] {
		return replacement + if parts.len > 1 { '.' + parts[1..].join('.') } else { '' }, true
	}
	if node := scope.ids[parts[0]] {
		if parts.len == 2 && parts[1] in ['x', 'y', 'width', 'height'] {
			return '(' + node + '.geometry() or { panic(err) }).' + parts[1], true
		}
	}
	return path, path.contains('.')
}

// vml_node_output_scope is the scope following siblings see: an imported
// document's ids stay private, except the id of its root.
fn vml_node_output_scope(node &vml.Node, incoming VmlScope, scope VmlScope) VmlScope {
	if !node.imported { return scope }
	mut exported := vml_clone_scope(incoming)
	if node.id.len > 0 {
		if variable := scope.ids[node.id] { exported.ids[node.id] = variable }
	}
	return exported
}

// vml_external_callbacks lists the bare callback names a document's events
// refer to: V locals of the calling function become closure captures.
fn vml_external_callbacks(node &vml.Node) []string {
	mut result := []string{}
	for property in node.properties {
		if property.name.starts_with('on_') && property.expr.kind == .path && !property.expr.value.contains('.') && property.expr.value !in result {
			result << property.expr.value
		}
	}
	// Component function names are lexical locals, not enclosing V bindings.
	if node.tag == vml.component_tag { return result }
	for child in node.children {
		for name in vml_external_callbacks(child) { if name !in result { result << name } }
	}
	return result
}
