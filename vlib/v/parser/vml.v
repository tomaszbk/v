module parser

import os
import strings
import v.flat
import vml

const vml_event_names = ['on_click', 'on_change', 'on_active', 'on_submit', 'on_scroll', 'on_open',
	'on_pointer_down', 'on_pointer_drag', 'on_pointer_up', 'on_long_press', 'on_swipe_left', 'on_link',
	'on_select', 'on_toggle', 'on_dismiss']

fn vml_is_event(name string) bool {
	return name in vml_event_names
}

// vml_parse_config supplies the widget-specific checks that run while the shared
// `vml` module parses a document.
fn vml_parse_config() vml.ParseConfig {
	return vml.ParseConfig{
		validate_style:    validate_vml_named_style
		validate_document: validate_compiled_vml_document
	}
}

fn validate_vml_named_style(owner &vml.Node, style &vml.Expr) ! {
	validate_vml_style_expr(owner, style, false, false)!
}

fn validate_compiled_vml_document(root &vml.Node, imported bool) ! {
	if root.tag in ['Menu', 'MenuBar'] { validate_compiled_vml_menu(root)! }
	validate_compiled_vml_visual(root, if imported {
		vml_unknown_component_parent
	} else {
		''
	})!
	validate_compiled_vml_node(root)!
}

fn parse_vml_source(source string) !&vml.Node {
	root := vml.parse_source(source, vml_parse_config())!
	validate_compiled_vml_visual(root, if root.tag == '__Component' {
		vml_unknown_component_parent
	} else {
		''
	})!
	validate_compiled_vml_node(root)!
	return root
}

// parse_compiled_vml_file parses a `$vml` document and its imports with the
// shared grammar; each document is validated after its imports are expanded.
fn parse_compiled_vml_file(path string) !&vml.Node {
	return vml.parse_file(path, vml_parse_config())
}

// parse_generic_vml_file parses a document for the generic lowering: only the
// language is validated here, widgets are checked by V against their props.
fn parse_generic_vml_file(path string) !&vml.Node {
	return vml.parse_file(path, validate_document: validate_generic_vml_document)
}

fn parse_vml_file_for(path string, generic bool) !&vml.Node {
	return if generic { parse_generic_vml_file(path)! } else { parse_compiled_vml_file(path)! }
}

fn validate_generic_vml_document(root &vml.Node, imported bool) ! {
	_ = imported
	validate_generic_vml_node(root)!
}

fn validate_generic_vml_node(node &vml.Node) ! {
	for property in node.properties {
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
		validate_generic_vml_node(child)!
	}
}

fn validate_compiled_vml_node(node &vml.Node) ! {
	if node.tag == '__Component' {
		for child in node.children { validate_compiled_vml_node(child)! }
		return
	}
	if node.tag in ['TextField', 'ScrollView'] {
		return error('${node.source}:${node.line}:${node.column}: removed widget `${node.tag}`; use TextInput or Scroll')
	}
	mut bindings := 0
	for property in node.properties {
		if property.name in ['hint_text', 'on_text_validate', 'editable', 'emit_change'] {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: removed widget property `${property.name}`')
		}
		if property.name.starts_with('on_') && !vml_is_event(property.name) {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported VML event `${property.name}`')
		}
		if property.name.starts_with('bind.') {
			bindings++
			bound_property := property.name.all_after('bind.')
			if bound_property !in ['text', 'checked', 'active', 'value', 'pressed'] {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: two-way binding is not supported for `${bound_property}`')
			}
			if property.expr.kind != .path {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: `${property.name}` must target a mutable top-level app field')
			}
		}
	}
	if bindings > 1 {
		return error('${node.source}:${node.line}:${node.column}: an element can only have one two-way binding')
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
		validate_compiled_vml_node(child)!
	}
}

// parse_vml_template_expr compiles `$vml('file.vml')` into a direct ui2.Element builder.
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
	generic := 'vml_generic' in p.prefs.user_defines
	root := parse_vml_file_for(path, generic) or {
		p.record_vml_diagnostic(path, os.read_file(path) or { '' }, err.msg(), call_start)
		return p.add_val_id(5, '')
	}
	source_file := p.a.source_files[p.cur_file_id] or { return p.add_val_id(5, '') }
	source := os.read_file(path) or { '' }
	target_os := p.prefs.normalized_target_os()
	custom := target_os in ['linux', 'android']
		|| (target_os in ['macos', 'windows'] && 'ui2_custom_rendering' in p.prefs.user_defines)
		|| 'ui2_headless' in p.prefs.user_defines
	if !generic && !custom {
		validate_vml_native_visual(root) or {
			p.record_vml_diagnostic(path, source, err.msg(), call_start)
			return p.add_val_id(5, '')
		}
	}
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
	generated := if generic { compiler.lower(root) } else { compiler.compile(root) }
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

struct VmlNamedValue {
	// geometry is the generic node whose reactive frame `id.x/y/width/height` reads.
	geometry     string
	frame        string
	frame_signal string
	frame_node   string
	control_id   string
	props        map[string]string
	prop_types   map[string]string
}

struct VmlScope {
mut:
	ids               map[string]VmlNamedValue
	special           map[string]string
	writable          map[string]string
	event_parameters  map[string][]vml.Parameter
	component_aliases []string
	component         string
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
	effect_mode           bool
	uses_unreachable      bool
	lowered_node          string
	lowered_props         string
	event_references      map[string]string
	emitted_child_effects map[string]bool
	slot_scopes           map[string]VmlScope
	out                   strings.Builder
	property_positions    map[string]vml.Property
	property_memos        map[string]string
	guards                []VmlGuard
	location              vml.Location
	locations             []vml.Location
}

fn (mut c VmlCompiler) compile(root &vml.Node) string {
	c.out = strings.new_builder(4096)
	c.location = vml.Location{ path: root.source, line: root.line, column: root.column }
	if root.tag in ['Menu', 'MenuBar'] {
		c.writeln('')
		return c.compile_menus(root)
	}
	c.location = vml.Location{ path: root.source, line: root.line, column: root.column }
	mut capture_names := c.callback_captures.clone()
	if c.uses_app { capture_names.insert(0, 'mut app') }

	capture := if capture_names.len > 0 { '[' + capture_names.join(', ') + '] ' } else { '' }
	c.writeln('\tvml_input_0 := vml_template_frame')
	mut scope := VmlScope{
		ids:     map[string]VmlNamedValue{}
		special: map[string]string{}
	}
	c.writeln("\tmut vml_root_component := ui2.new_vml_document('root', ui2.VmlDocumentConfig{}) or { panic(err) }")
	scope.component = 'vml_root_component'
	if root.tag != '__Component' { c.prepare_style_tokens(root, scope.component) }
	c.compile_node(root, '0', 'vml_input_0', scope, '', .normal)
	if !c.explicit_frame {
		bounds_root := if root.tag == '__Component' { root.children[0] } else { root }
		c.writeln('\tvml_element_0.compiled_node.follow_viewport(${vml.find_property(bounds_root, 'width') == none}, ${vml.find_property(bounds_root, 'height') == none})')
	}
	c.writeln('\tui2.validate_element_tree(vml_element_0) or { panic(' + vml_quote(root.source + ':' + root.line.str() + ': ') + ' + err.msg()) }')
	c.writeln('\tmut vml_layout_tree := ui2.LayoutTree{}')
	c.writeln('\tvml_layout_tree.replace(vml_element_0) or { panic(err) }')
	c.writeln('\treturn vml_layout_tree.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{}) or { panic(err) }')
	c.writeln('})(ui2.vml_bounds())')
	c.write_list_guards()
	body := c.out.str()
	body_locations := c.locations.clone()
	c.out = strings.new_builder(body.len + 4096)
	c.locations = []vml.Location{}
	c.location = vml.Location{ path: root.source, line: root.line, column: root.column }
	c.writeln('')
	c.writeln('(fn ${capture}(vml_template_frame ui2.Rect) ui2.Element {')
	c.out.write_string(body)
	c.locations << body_locations
	return c.out.str()
}

fn vml_clone_scope(scope VmlScope) VmlScope {
	return VmlScope{
		ids:               scope.ids.clone()
		special:           scope.special.clone()
		writable:          scope.writable.clone()
		event_parameters:  scope.event_parameters.clone()
		component_aliases: scope.component_aliases.clone()
		component:         scope.component
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

fn vml_numeric_cast(type_name string, expression string) string {
	if expression.starts_with('(') && expression.ends_with(')') {
		return type_name + expression
	}
	return '${type_name}(${expression})'
}

enum VmlExprUse {
	raw
	number
	string_
	text
	bool_
	color
}

fn vml_property_use(property vml.Property) VmlExprUse {
	if property.name == 'text' { return .text }
	if use := vml_overlay_property_use(property.name) { return use }
	if use := vml_visual_property_use(property.name) { return use }
	if use := vml_widget_property_use(property.name) { return use }
	if property.name in ['x', 'y', 'width', 'height', 'padding', 'spacing', 'corner_radius', 'radius',
		'rotation', 'opacity', 'translate_x', 'translate_y', 'scale_x', 'scale_y', 'origin_x',
		'origin_y', 'font_size', 'size', 'head_indent', 'first_line_indent', 'hyphenation_factor',
		'lines', 'dialog_width', 'dialog_height', 'border_width', 'border_left', 'border_top',
		'border_right', 'border_bottom', 'value', 'min', 'max', 'step', 'track_width', 'thumb_size',
		'keyboard'] {
		return .number
	}
	if property.name in ['background', 'color', 'background_color', 'border_color', 'value_track_color',
		'thumb_color', 'inactive_color', 'active_color', 'disabled_track_color', 'disabled_thumb_color'] {
		return .color
	}
	if property.name in ['checked', 'hidden', 'enabled', 'native', 'password', 'readonly',
		'disable_scroll', 'secure', 'clickable', 'draggable', 'long_press', 'swipe_left', 'persistent',
		'autocorrect', 'bold', 'italic', 'underline', 'strikethrough', 'shadow', 'outline',
		'value_track', 'active', 'text_autoupdate']
		|| property.name in ['bind.checked', 'bind.active'] {
		return .bool_
	}
	if property.name == 'bind.value' {
		return .number
	}
	if property.name in ['model', 'key', 'motion'] {
		return .raw
	}
	return .string_
}

fn vml_expr_is_string(expr &vml.Expr) bool {
	if expr.kind == .interpolation || (expr.kind == .literal && expr.quoted) {
		return true
	}
	if expr.kind == .conditional {
		return vml_expr_is_string(expr.right) || vml_expr_is_string(expr.third)
	}
	return false
}

fn (c &VmlCompiler) resolve_path(path string, scope VmlScope) (string, bool) {
	parts := path.split('.')
	if parts.len == 0 {
		return path, false
	}
	if replacement := scope.special[parts[0]] {
		return replacement + if parts.len > 1 { '.' + parts[1..].join('.') } else { '' }, true
	}
	if named := scope.ids[parts[0]] {
		if parts.len == 2 && parts[1] in ['x', 'y', 'width', 'height'] && named.geometry.len > 0 {
			return '(' + named.geometry + '.geometry() or { panic(err) }).' + parts[1], true
		}
		if parts.len == 2 && parts[1] in ['x', 'y', 'width', 'height'] && named.frame_node.len > 0 {
			return '(' + named.frame_node + '.frame() or { panic(err) }).' + parts[1], true
		}
		if parts.len == 2 && parts[1] in ['x', 'y', 'width', 'height'] && named.frame_signal.len > 0 {
			return '(' + named.frame_signal + '.get() or { panic(err) }).' + parts[1], true
		}
		if parts.len >= 2 {
			if prop := named.props[parts[1]] {
				return prop + if parts.len > 2 { '.' + parts[2..].join('.') } else { '' }, true
			}
		}
		if parts.len == 2 {
			if parts[1] in ['x', 'y', 'width', 'height'] {
				return '${named.frame}.${parts[1]}', true
			}
		}
	}
	return path, path.contains('.')
}

fn (c &VmlCompiler) expr(expr &vml.Expr, scope VmlScope, use VmlExprUse) string {
	if use == .text {
		if expr.kind == .conditional {
			condition := c.expr(expr.left, scope, .bool_)
			return '(if ${condition} { ${c.expr(expr.right, scope, .text)} } else { ${c.expr(expr.third, scope, .text)} })'
		}
		return 'ui2.vml_display_text(${c.expr(expr, scope, .raw)})'
	}
	match expr.kind {
		.literal {
			if expr.quoted {
				if use == .color {
					if expr.value.starts_with('#') && expr.value.len == 7 {
						return 'u32(0x${expr.value[1..]})'
					}
					return 'ui2.parse_hex_color(${vml_quote(expr.value)})'
				}
				return vml_quote(expr.value)
			}
			return match use {
				.string_ { expr.value }
				.number { 'f64(${expr.value})' }
				else { expr.value }
			}
		}
		.path {
			for pair in [['color', 'color_token'], ['spacing', 'spacing_token'],
				['radius', 'radius_token'], ['typography', 'font_size_token']] {
				if expr.value.starts_with(pair[0] + '.') {
					return '${scope.component}.${pair[1]}(' + vml_quote(expr.value.all_after(pair[0] + '.')) + ') or { panic(err) }'
				}
			}
			resolved, _ := c.resolve_path(expr.value, scope)
			if use == .color {
				if expr.value.starts_with('#') && expr.value.len == 7 {
					return 'u32(0x${expr.value[1..]})'
				}
				return 'ui2.TextStyle{color: ${resolved}}.color'
			}
			if use == .string_ {
				return resolved
			}
			if use == .number {
				return 'ui2.LayoutSize{width: ${resolved}}.width'
			}
			return resolved
		}
		.call {
			args := expr.args.map(c.expr(it, scope, .raw)).join(', ')
			resolved, _ := c.resolve_path(expr.value, scope)
			call := '${resolved}(${args})' + if expr.fallible { ' or { panic(err) }' } else { '' }
			return match use {
				.string_ { call }
				.number { 'ui2.LayoutSize{width: ${call}}.width' }
				.color { 'ui2.TextStyle{color: ${call}}.color' }
				else { call }
			}
		}
		.unary {
			operand_use := if use in [.raw, .string_, .color] {
				VmlExprUse.raw
			} else if expr.value == '!' {
				VmlExprUse.bool_
			} else {
				VmlExprUse.number
			}
			result := '(${expr.value}${c.expr(expr.left, scope, operand_use)})'
			return result
		}
		.binary {
			if use == .raw {
				return '(${c.expr(expr.left, scope, .raw)} ${expr.value} ${c.expr(expr.right, scope, .raw)})'
			}
			if expr.value in ['&&', '||'] {
				result := '(${c.expr(expr.left, scope, .bool_)} ${expr.value} ${c.expr(expr.right, scope, .bool_)})'
				return result
			}
			if expr.value in ['==', '!=', '<', '<=', '>', '>='] {
				operand_use := if vml_expr_is_string(expr.left) || vml_expr_is_string(expr.right) {
					VmlExprUse.string_
				} else {
					VmlExprUse.raw
				}
				result := '(${c.expr(expr.left, scope, operand_use)} ${expr.value} ${c.expr(expr.right, scope, operand_use)})'
				return result
			}
			if use in [.raw, .string_, .color] {
				return '(${c.expr(expr.left, scope, .raw)} ${expr.value} ${c.expr(expr.right, scope, .raw)})'
			}
			if expr.value == '%' {
				return 'f64(int(${c.expr(expr.left, scope, .number)}) % int(${c.expr(expr.right, scope, .number)}))'
			}
			return '(${c.expr(expr.left, scope, .number)} ${expr.value} ${c.expr(expr.right, scope, .number)})'
		}
		.conditional {
			condition_use := if use == .raw { VmlExprUse.raw } else { VmlExprUse.bool_ }
			return '(if ${c.expr(expr.left, scope, condition_use)} { ${c.expr(expr.right, scope, use)} } else { ${c.expr(expr.third, scope, use)} })'
		}
		.assignment { return c.expr(expr.right, scope, .raw) }
		.block { return expr.args.map(c.expr(it, scope, .raw)).join('\n') }
		.array { return '[' + expr.args.map(c.expr(it, scope, .raw)).join(', ') + ']' }
		.interpolation {
			mut value := "'"
			for part in expr.parts {
				if isnil(part.expr) {
					value += vml_interpolation_text(part.text)
				} else {
					value += r'$' + '{' + c.expr(part.expr, scope, .raw) + '}'
				}
			}
			return value + "'"
		}
	}
}

fn vml_prop(properties map[string]string, name string, default_ string) string {
	return properties[name] or { default_ }
}

fn vml_property_is_geometry(property vml.Property) bool {
	return property.name in ['x', 'y', 'width', 'height']
}

fn vml_order_properties_by_dependencies(properties []vml.Property, node_id string) []vml.Property {
	mut remaining := properties.clone()
	if node_id.len == 0 || remaining.len < 2 {
		return remaining
	}
	mut ordered := []vml.Property{cap: remaining.len}
	for remaining.len > 0 {
		mut deferred := []vml.Property{cap: remaining.len}
		for property in remaining {
			mut has_pending_dependency := false
			for candidate in remaining {
				if candidate.name != property.name
					&& vml.expr_uses_path(property.expr, '${node_id}.${candidate.name}') {
					has_pending_dependency = true
					break
				}
			}
			if has_pending_dependency {
				deferred << property
			} else {
				ordered << property
			}
		}
		if deferred.len == remaining.len {
			// Preserve source order for a dependency cycle; generated V will report
			// the invalid forward reference without making this pass loop forever.
			ordered << deferred
			break
		}
		remaining = deferred.clone()
	}
	return ordered
}

fn (mut c VmlCompiler) compile_node(node &vml.Node, path string, input string, incoming VmlScope, default_key string, placement VmlPlacement) VmlScope {
	if node.caller_content {
		mut lexical := vml_clone_scope(c.slot_scopes[incoming.component] or { incoming })
		owner := 'vml_slot_component_' + vml_var(path)
		c.writeln('mut ${owner} := ${lexical.component}.slot_child(mut ${incoming.component}, ' + vml_quote(path) + ') or { panic(err) }')
		lexical.component = owner
		value := &vml.Node{ ...node, caller_content: false }
		c.compile_node(value, path, input, lexical, default_key, placement)
		return incoming
	}
	if node.tag == '__Component' {
		return c.compile_component(node, path, input, incoming, default_key, placement)
	}
	return c.compile_node_body(node, path, input, incoming, default_key, placement)
}

fn (mut c VmlCompiler) compile_node_body(node &vml.Node, path string, input string, incoming VmlScope, default_key string, placement VmlPlacement) VmlScope {
	suffix := vml_var(path)
	measure_mode := placement in [.preferred, .width_preferred, .inherited_preferred]
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	c.writeln('\t_ = ${input}')
	mut scope := vml_clone_scope(incoming)
	if node.imported {
		scope.special['__import_parent'] = scope.special['__import'] or { '' }
		scope.special['__import'] = suffix
	}
	mut named_props := map[string]string{}
	mut named_types := map[string]string{}
	control_id := '${scope.component}.control_id(' + c.control_id(node, suffix, scope) + ')'
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: input, control_id: control_id, props: named_props.clone(), prop_types: named_types.clone() }
	}
	mut properties := map[string]string{}
	for property in vml_order_properties_by_dependencies(node.properties.filter(vml_property_is_geometry(it)), node.id) {
		name := c.write_property_initializer(node, property, suffix, scope)
		properties[property.name] = name
		named_props[property.name] = name
		named_types[property.name] = vml_builder_property_type(node, property)
		if node.id.len > 0 {
			scope.ids[node.id] = VmlNamedValue{ frame: input, control_id: control_id, props: named_props.clone(), prop_types: named_types.clone() }
		}
	}
	frame := 'vml_frame_${suffix}'
	if placement == .allocated {
		c.writeln('\t${frame} := ${input}')
	} else {
		preferred_mode := placement in [.preferred, .width_preferred]
		width := if placement == .width_preferred {
			input + '.width'
		} else {
			vml_prop(properties, 'width', if preferred_mode { 'f64(0)' } else { input + '.width' })
		}
		height := vml_prop(properties, 'height', if preferred_mode {
			'f64(0)'
		} else {
			input + '.height'
		})
		c.writeln('\t${frame} := ui2.rect(${vml_prop(properties, 'x', input + '.x')}, ${vml_prop(properties, 'y', input + '.y')}, ${width}, ${height})')
	}
	c.writeln('\t_ = ${frame}')
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: frame, control_id: control_id, props: named_props.clone(), prop_types: named_types.clone() }
	}
	if node.id.len > 0 {
		geometry := 'vml_geometry_${suffix}'
		c.writeln('\tmut ${geometry} := ${scope.component}.geometry(' + c.node_identity(node, suffix, scope) + ', ${frame}) or { panic(err) }')
		c.writeln('_ = ${geometry}')
		scope.ids[node.id] = VmlNamedValue{ frame: frame, frame_signal: geometry, control_id: control_id, props: named_props.clone(), prop_types: named_types.clone() }
	}
	for property in node.properties.filter(!vml_property_is_geometry(it)) {
		if property.name in ['id', 'ref'] || vml_is_event(property.name) { continue }
		properties[property.name] = c.write_property_initializer(node, property, suffix, scope)
	}
	c.write_action_type_checks(node, suffix, scope)
	if node.tag in ['Flex', 'Row', 'Column', 'Grid'] {
		result := c.compile_visual_layout(node, path, input, frame, properties, scope, placement, default_key)
		c.retain_element(node, suffix, result, placement)
		return vml_node_output_scope(node, incoming, result)
	}
	children := 'vml_children_${suffix}'
	container := node.tag in ['Screen', 'View', 'ScaledContent', 'Scroll', 'Button']
		|| node.tag !in ['Label', 'Image', 'Button', 'MessageBox', 'Checkbox', 'Dropdown', 'TextInput',
			'TextArea', 'ProgressBar', 'Slider', 'Switch', 'Spinner']
	visible_children := if container {
		node.children.filter(it.tag !in ['MenuItem', 'Option'])
	} else {
		[]&vml.Node{}
	}
	if container {
		c.writeln('\tmut ${children} := []ui2.Element{cap: ${visible_children.len}}')
	}
	cursor := ''
	child_placement := if node.tag == 'Scroll' {
		VmlPlacement.inherited_preferred
	} else if node.tag in ['Absolute', 'Stack'] {
		VmlPlacement.preferred
	} else if measure_mode {
		// Generic containers offer fixed axes; zero auto axes need measurement.
		VmlPlacement.inherited_preferred
	} else {
		VmlPlacement.normal
	}
	for child_index, child in node.children {
		child_path := '${path}.${child_index}'
		if child.tag == 'MenuItem' {
			c.write_action_type_checks(child, '${vml_var(child_path)}_menu_action', scope)
			continue
		}
		if child.tag == 'Run' { continue }
		if !container || child.tag == 'Option' {
			continue
		}
		if child.tag == 'Repeater' {
			continue
		}
		child_input := 'vml_input_${vml_var(child_path)}'
		c.writeln('\t${child_input} := ${vml_widget_child_input(node.tag, frame, properties, node.children.len) or { vml_child_input(node.tag, frame, properties, cursor) }}')
		child_scope := c.compile_node(child, child_path, child_input, scope, '', child_placement)
		for id, named in child_scope.ids {
			scope.ids[id] = named
		}
		c.writeln('\t${children} << vml_element_${vml_var(child_path)}')
	}
	c.prepare_menu_initializers(node, suffix, scope)
	if node.tag in ['Label', 'TextArea'] && node.children.any(it.tag == 'Run') {
		c.prepare_visual_runs(node, suffix, mut properties, scope)
	}
	c.compile_element(node, suffix, frame, children, properties, scope, default_key)
	c.retain_element(node, suffix, scope, placement)
	return vml_node_output_scope(node, incoming, scope)
}

fn vml_node_output_scope(node &vml.Node, incoming VmlScope, scope VmlScope) VmlScope {
	if !node.imported { return scope }
	mut exported := vml_clone_scope(incoming)
	if node.id.len > 0 { exported.ids[node.id] = scope.ids[node.id] }
	return exported
}

fn vml_child_input(tag string, frame string, properties map[string]string, cursor string) string {
	_ = cursor
	if tag == 'Scroll' { return 'ui2.rect(0, 0, 0, 0)' }
	if tag == 'ScaledContent' {
		return 'ui2.rect(0, 0, ' + vml_prop(properties, 'content_width', 'f64(0)') + ', ' + vml_prop(properties, 'content_height', 'f64(0)') + ')'
	}
	return 'ui2.rect(f64(0), f64(0), ${frame}.width, ${frame}.height)'
}

fn vml_value(properties map[string]string, name string, alternative string, default_ string) string {
	if value := properties[name] {
		return value
	}
	if alternative.len > 0 {
		if value := properties[alternative] {
			return value
		}
	}
	return default_
}

fn vml_binding_for_event(node &vml.Node, event_name string) ?vml.Property {
	for property in node.properties {
		if !property.name.starts_with('bind.') { continue }
		selected := if property.name == 'bind.active' && vml.find_property(node, 'on_active') != none {
			'on_active'
		} else {
			'on_change'
		}
		if event_name == selected { return property }
	}
	return none
}

fn vml_stringify(expression string) string {
	return "'" + r'$' + '{' + expression + "}'"
}

fn (c &VmlCompiler) box_style(properties map[string]string) string {
	return c.visual_box_style(properties, '', false)
}

fn (c &VmlCompiler) text_style(properties map[string]string) string {
	mut fields := []string{}
	for name in vml_text_properties {
		if value := properties[name] {
			field := match name {
				'font_size', 'size' { 'size' }
				else { name }
			}
			if name == 'size' && 'font_size' in properties { continue }
			fields << '${field}: ${if name in ['weight', 'lines'] {
				'int(' + value + ')'
			} else {
				value
			}}'
		}
	}
	base := 'ui2.TextStyle{${fields.join(', ')}}'
	if style := properties['style'] {
		return 'ui2.apply_text_style(${base}, ${style}) or { panic(err) }'
	}
	return base
}

// Retained root nodes capture constructor defaults before their style effect.
// Rich runs and owned widget parts still compose their authored text styles.
fn (c &VmlCompiler) root_text_style(properties map[string]string) string {
	mut unstyled := properties.clone()
	unstyled.delete('style')
	return c.text_style(unstyled)
}

fn (c &VmlCompiler) menu_value(node &vml.Node, suffix string, scope VmlScope) string {
	menu_items := node.children.filter(it.tag == 'MenuItem')
	if menu_items.len > 0 {
		mut entries := []string{cap: menu_items.len}
		for index, item in menu_items {
			id := c.event_callback(item, 'on_click', scope)
			text := if property := vml.find_property(item, 'text') {
				c.property_effect_value(item, property, vml_content_suffix(suffix, item), scope)
			} else {
				"''"
			}
			entries << 'ui2.MenuEntry{id: ${c.control_id(item, '${suffix}_menu_${index}', scope)}, on_select: ${id}, title: ${text}}'
		}
		return vml_array_literal('ui2.MenuEntry', entries)
	}
	if node.tag in ['Dropdown', 'Spinner'] {
		mut entries := []string{}
		for option in node.children {
			if option.tag != 'Option' {
				continue
			}
			text := if property := vml.find_property(option, 'text') {
				c.property_effect_value(option, property, vml_content_suffix(suffix, option), scope)
			} else {
				"''"
			}
			entries << 'ui2.MenuEntry{id: ${text}, title: ${text}}'
		}
		return vml_array_literal('ui2.MenuEntry', entries)
	}
	return '[]ui2.MenuEntry{}'
}

fn (c &VmlCompiler) option_values(node &vml.Node, suffix string, scope VmlScope) string {
	mut values := []string{}
	for option in node.children {
		if option.tag != 'Option' {
			continue
		}
		value := if property := vml.find_property(option, 'text') {
			c.property_effect_value(option, property, vml_content_suffix(suffix, option), scope)
		} else {
			"''"
		}
		values << value
	}
	return vml_array_literal('string', values)
}

fn vml_array_literal(elem_type string, values []string) string {
	return if values.len == 0 { '[]${elem_type}{}' } else { '[${values.join(', ')}]' }
}

fn (mut c VmlCompiler) compile_element(node &vml.Node, suffix string, frame string, children string, properties map[string]string, incoming_scope VmlScope, default_key string) {
	mut scope := vml_clone_scope(incoming_scope)
	scope.special['__node_suffix'] = suffix
	id := c.control_id(node, suffix, scope)
	key := vml_prop(properties, 'key', if default_key.len > 0 { default_key } else { "''" })
	action := c.write_element_callback(node, suffix, scope)
	if c.compile_widget(node, suffix, frame, children, properties, scope, key, action) { return }
	if node.tag in ['TextInput', 'TextArea'] {
		c.compile_text_input(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'MessageBox' {
		c.compile_message_box(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'ProgressBar' {
		c.compile_progress_bar(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Slider' {
		c.compile_slider(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Switch' {
		c.compile_switch(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Spinner' {
		c.compile_spinner(node, suffix, frame, properties, scope, key, action)
		return
	}
	kind := match node.tag {
		'Screen' { 'screen' }
		'Label' { 'label' }
		'Image' { 'image' }
		'Button' { 'button' }
		'Checkbox' { 'checkbox' }
		'Dropdown' { 'dropdown' }
		'TextInput' { 'text_field' }
		'TextArea' { 'text_area' }
		'Scroll' { 'scroll' }
		else { 'view' }
	}
	declaration := if vml_has_overlay(node) {
		'vml_overlay_base_' + suffix
	} else {
		'vml_declaration_' + suffix
	}
	c.writeln('\t${declaration} := ui2.Element{')
	c.writeln('\t\tkind: .${kind}')
	c.writeln('\t\tid: ${id}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput', 'TextArea'] {
		c.writeln('\t\ttext: ${if node.tag in ['Label', 'TextArea'] && node.children.any(it.tag == 'Run') {
			vml_prop(properties, '@run_text', "''")
		} else {
			vml_value(properties, 'text', 'bind.text', "''")
		}}')
	}
	if node.tag == 'Checkbox' {
		c.writeln('\t\tchecked: ${vml_value(properties, 'checked', 'bind.checked', 'false')}')
	}
	if node.tag == 'Image' {
		c.writeln('\t\timage_path: ${vml_value(properties, 'source', 'path', "''")}')
	}
	if node.tag == 'Screen' {
		c.writeln('\t\tbox: ${c.box_style(properties)}')
		c.writeln('\t\tcompiled_metadata: &ui2.CompiledVmlMetadata{screen: ui2.ManagedScreen{name: ${vml_prop(properties, 'name', id)}}}')
	} else if node.tag == 'Scroll' {
		c.writeln('\t\tbox: ${c.box_style(properties)}')
		c.writeln('\t\tpersistent_scrollbars: ${vml_prop(properties, 'persistent', 'false')}')
		c.writeln('\t\tscroll_mode: ${vml_prop(properties, 'scroll_mode', 'ui2.ScrollMode.vertical_only')}')
	} else if node.tag == 'Checkbox' {
		c.writeln('\t\tbox: ui2.BoxStyle{transparent: true}')
	} else if node.tag in ['View', 'ScaledContent', 'Button', 'Dropdown', 'Label'] || kind == 'view' {
		c.writeln('\t\tbox: ${c.box_style(properties)}')
	}
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput', 'TextArea'] {
		c.writeln('\t\ttext_style: ${c.root_text_style(properties)}')
	}
	if node.tag in ['Label', 'TextArea'] && node.children.any(it.tag == 'Run') {
		c.writeln('\t\ttext_runs: ${vml_prop(properties, '@runs', '[]ui2.TextRun{}')}')
	}
	if node.tag == 'ScaledContent' {
		c.writeln('\t\tcontent_size: ui2.LayoutSize{width: ${vml_prop(properties, 'content_width', 'f64(0)')}, height: ${vml_prop(properties, 'content_height', 'f64(0)')}}')
	}
	if node.tag in ['Screen', 'View', 'ScaledContent', 'Scroll', 'Button'] || kind == 'view' {
		c.writeln('\t\tchildren: ${children}')
	}
	role_default := if node.tag == 'Checkbox' { "'checkbox'" } else { "''" }
	label_default := if node.tag == 'Checkbox' {
		vml_value(properties, 'text', 'bind.text', "''")
	} else {
		"''"
	}
	value_default := if node.tag == 'Checkbox' {
		"if ${vml_value(properties, 'checked', 'bind.checked', 'false')} { 'checked' } else { 'unchecked' }"
	} else {
		"''"
	}
	c.write_common_fields(node, suffix, properties, scope, role_default, label_default, value_default)
	c.writeln('\t}')
	if vml_has_overlay(node) {
		c.writeln('\tvml_declaration_${suffix} := ui2.with_overlay(${declaration}, ${c.overlay_config(node, suffix, properties)}) or { panic(err) }')
	}
}

fn (mut c VmlCompiler) compile_text_input(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	method := if node.tag == 'TextArea' { 'text_area' } else { 'text_input' }
	config := if node.tag == 'TextArea' { 'TextAreaConfig' } else { 'TextInputConfig' }
	c.writeln('\tvml_text_input_${suffix} := ui2.${method}(ui2.${config}{')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}, frame: ${frame}, on_event: ${action}')
	c.writeln('\t\ttext: ${vml_prop(properties, '@run_text', vml_value(properties, 'text', 'bind.text', "''"))}, placeholder: ${vml_prop(properties, 'placeholder', "''")}')
	for name in ['password', 'readonly', 'disable_scroll', 'enabled', 'autocorrect', 'padding_left'] {
		if value := properties[name] { c.writeln('\t\t${name}: ${value}') }
	}
	if value := properties['keyboard'] { c.writeln('\t\tkeyboard: int(${value})') }
	c.writeln('\t\tbox: ${c.box_style(properties)}, text_style: ${c.root_text_style(properties)}')
	c.writeln('\t}) or { panic(' + vml_quote('${node.source}:${node.line}:${node.column}: ') + ' + err.msg()) }')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{ ...vml_text_input_${suffix}, key: ${key}')
	if '@runs' in properties { c.writeln('text_runs: ' + properties['@runs']) }
	mut common := properties.clone()
	if 'secure' !in common { common['secure'] = 'vml_text_input_${suffix}.secure' }
	c.write_common_fields(node, suffix, common, scope, "''", "''", "''")
	c.writeln('\t}')
}

fn (mut c VmlCompiler) write_common_fields(node &vml.Node, suffix string, properties map[string]string, scope VmlScope, role_default string, label_default string, value_default string) {
	c.writeln('\t\tinteraction_style: ${vml_prop(properties, '@interaction_style', c.interaction_style(properties))}')
	c.writeln('\t\tbutton_behavior: ${vml_prop(properties, 'button_behavior', 'false')}')
	c.writeln('\t\tmenu: ${vml_prop(properties, '@menu', c.menu_value(node, suffix, scope))}')
	c.writeln('\t\tsecure: ${vml_prop(properties, 'secure', 'false')}' + if node.tag == 'TextInput' {
		' || ${vml_prop(properties, 'password', 'false')}'
	} else {
		''
	})
	c.writeln('\t\tclickable: ${vml_prop(properties, 'clickable', 'false')}')
	c.writeln('\t\tdraggable: ${vml_prop(properties, 'draggable', 'false')}')
	c.writeln('\t\tlong_press: ${vml_prop(properties, 'long_press', 'false')}')
	c.writeln('\t\tswipe_left: ${vml_prop(properties, 'swipe_left', 'false')}')
	c.writeln('\t\trotation: ${vml_prop(properties, 'rotation', 'f64(0)')}')
	c.writeln('\t\topacity: ${vml_prop(properties, 'opacity', 'f64(1)')}')
	if value := properties['motion'] { c.writeln('\t\tmotion: ${value}') }
	for field in ['translate_x', 'translate_y', 'scale_x', 'scale_y', 'origin_x', 'origin_y'] {
		c.writeln('\t\t${field}: ${vml_prop(properties, field, if field.starts_with('scale') {
			'f64(1)'
		} else {
			'f64(0)'
		})}')
	}
	c.writeln('\t\tcursor: ${vml_prop(properties, 'cursor', "''")}')
	c.writeln('\t\ttooltip: ${vml_prop(properties, 'tooltip', "''")}')
	c.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.writeln('\t\tenabled: ${vml_prop(properties, 'enabled', 'true')}')
	c.writeln('\t\taccessibility_role: ${vml_prop(properties, 'accessibility_role', role_default)}')
	c.writeln('\t\taccessibility_label: ${vml_prop(properties, 'accessibility_label', label_default)}')
	c.writeln('\t\taccessibility_value: ${vml_prop(properties, 'accessibility_value', value_default)}')
	c.writeln('\t\tnative_style: ${vml_prop(properties, 'native', 'false')}')
	c.writeln('\t\tautocorrect: ${vml_prop(properties, 'autocorrect', 'true')}')
	c.writeln('\t\tpadding_left: ${vml_prop(properties, '@padding_left', 'f64(12)')}')
}

fn (mut c VmlCompiler) compile_progress_bar(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_progress_${suffix}'
	c.writeln('\t${base}_config := ui2.ProgressBarConfig{')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tvalue: ${vml_prop(properties, 'value', 'f64(0)')}')
	c.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.writeln('\t\tbackground: ${vml_prop(properties, 'background', 'u32(0xe2e8f0)')}')
	c.writeln('\t\tcolor: ${vml_prop(properties, 'color', 'u32(0x3b82f6)')}')
	c.writeln('\t\tradius: ${vml_value(properties, 'corner_radius', 'radius', 'f64(4)')}')
	c.writeln('\t}')
	config := if style := properties['style'] {
		'ui2.style_progress_bar(${base}_config, ${style}) or { panic(err) }'
	} else {
		'${base}_config'
	}
	c.writeln('\t${base} := ui2.progress_bar(${config})')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_slider(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_slider_${suffix}'
	style := '${base}_style'
	orientation_value := '${base}_orientation'
	orientation := vml_prop(properties, 'orientation', 'ui2.Orientation.horizontal')
	c.writeln('\t${style} := ui2.SliderStyle{')
	c.writeln('\t\ttrack_color: ${vml_prop(properties, 'background', 'u32(0xcbd5e1)')}')
	c.writeln('\t\tvalue_track_color: ${vml_value(properties, 'value_track_color', 'color', 'u32(0x93c5fd)')}')
	c.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0x2563eb)')}')
	c.writeln('\t\ttrack_width: ${vml_prop(properties, 'track_width', 'f64(4)')}')
	c.writeln('\t\tthumb_size: ${vml_prop(properties, 'thumb_size', 'f64(20)')}')
	c.writeln('\t}')
	c.writeln('\t${orientation_value} := ${orientation}')
	c.writeln('\t${base} := ui2.slider(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tmin: ${vml_prop(properties, 'min', 'f64(0)')}')
	c.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.writeln('\t\tvalue: ${vml_value(properties, 'value', 'bind.value', 'f64(0)')}')
	c.writeln('\t\tstep: ${vml_prop(properties, 'step', 'f64(0)')}')
	c.writeln('\t\torientation: ${orientation_value}')
	c.writeln('\t\tpadding: ${vml_prop(properties, 'track_inset', 'f64(16)')}')
	c.writeln('\t\tvalue_track: ${vml_prop(properties, 'value_track', 'false')}')
	c.writeln('\t\tstyle: ${style}')
	c.writeln('\t)')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_switch(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_switch_${suffix}'
	style := '${base}_style'
	c.writeln('\t${style} := ui2.SwitchStyle{')
	c.writeln('\t\tinactive_track_color: ${vml_prop(properties, 'inactive_color', 'u32(0xcbd5e1)')}')
	c.writeln('\t\tactive_track_color: ${vml_value(properties, 'active_color', 'color', 'u32(0x22c55e)')}')
	c.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0xffffff)')}')
	c.writeln('\t\tdisabled_track_color: ${vml_prop(properties, 'disabled_track_color', 'u32(0xe2e8f0)')}')
	c.writeln('\t\tdisabled_thumb_color: ${vml_prop(properties, 'disabled_thumb_color', 'u32(0xf8fafc)')}')
	c.writeln('\t}')
	c.writeln('\t${base} := ui2.switch_control(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tactive: ${vml_value(properties, 'active', 'bind.active', 'false')}')
	c.writeln('\t\tstyle: ${style}')
	c.writeln('\t)')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_spinner(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_spinner_${suffix}'
	box := '${base}_box'
	text_style := '${base}_text_style'
	c.writeln('\t${box} := ${c.box_style(properties)}')
	c.writeln('\t${text_style} := ${c.root_text_style(properties)}')
	c.writeln('\t${base} := ui2.spinner(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ttext: ${vml_value(properties, 'text', 'bind.text', "''")}')
	c.writeln('\t\tvalues: ${c.option_values(node, suffix, scope)}')
	c.writeln('\t\ttext_autoupdate: ${vml_prop(properties, 'text_autoupdate', 'false')}')
	c.writeln('\t\tbox: ${box}')
	c.writeln('\t\ttext_style: ${text_style}')
	c.writeln('\t)')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_message_box(node &vml.Node, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	mut actions := []string{}
	for child_index, child in node.children {
		if child.tag != 'Button' {
			continue
		}
		c.write_action_type_checks(child, '${suffix}_message_action_${child_index}', scope)
		event_key := (scope.special['__node_suffix'] or { suffix }) + ':message_action:' + child_index.str()
		child_action := if c.effect_mode {
			c.event_references[event_key] or { 'unsafe { nil }' }
		} else {
			reference := 'vml_message_action_${suffix}_${child_index}'
			c.writeln('${reference} := ' + c.event_callback(child, 'on_click', scope))
			c.event_references[event_key] = reference
			reference
		}
		text := if property := vml.find_property(child, 'text') {
			c.expr(property.expr, scope, .text)
		} else {
			"''"
		}
		actions << 'ui2.MessageBoxAction{id: ${c.control_id(child, suffix + '_' + child_index.str(), scope)}, on_event: ${child_action}, title: ${text}}'
	}
	c.writeln('\tvml_message_box_${suffix} := ui2.custom_message_box(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ttitle: ${vml_prop(properties, 'title', "''")}')
	c.writeln('\t\ttext: ${vml_prop(properties, 'text', "''")}')
	c.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.writeln('\t\twidth: ${vml_prop(properties, 'dialog_width', 'f64(300)')}')
	c.writeln('\t\theight: ${vml_prop(properties, 'dialog_height', 'f64(150)')}')
	c.writeln('\t\tactions: ${vml_array_literal('ui2.MessageBoxAction', actions)}')
	c.writeln('\t)')
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{')
	c.writeln('\t\t...vml_message_box_${suffix}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, "''", "''", "''")
	c.writeln('\t}')
}
