module parser

import math

// These names describe the existing ui2 API, not a second style/layout engine.
const vml_text_properties = ['color', 'background_color', 'font_size', 'size', 'font_family', 'weight',
	'letter_spacing', 'line_height', 'line_height_factor', 'baseline_offset', 'tabular_figures',
	'bold', 'italic', 'underline', 'strikethrough', 'shadow', 'outline', 'vertical_align', 'link',
	'align', 'valign', 'head_indent', 'first_line_indent', 'hyphenation_factor', 'lines']

const vml_box_properties = ['background', 'radius', 'corner_radius', 'transparent', 'border_color',
	'border_width', 'border_left', 'border_top', 'border_right', 'border_bottom', 'border_left_color',
	'border_top_color', 'border_right_color', 'border_bottom_color', 'border_pattern', 'dash_length',
	'dash_gap', 'outline_color', 'outline_width', 'outline_offset']

const vml_flex_child_properties = ['flex_basis', 'flex_grow', 'flex_shrink', 'min_width', 'min_height',
	'max_width', 'max_height', 'align_self']

enum VmlPlacement {
	normal
	preferred
	width_preferred
	inherited_preferred
	allocated
}

fn vml_measured_axis(placement VmlPlacement, offered string, measured string) string {
	return if placement == .inherited_preferred {
		'if ${offered} > 0 { ${offered} } else { ${measured} }'
	} else {
		measured
	}
}

// Select the same dimension for measurement allocation and the returned frame.
// A width pass is allocated even at zero; explicit properties also keep zero.
fn vml_layout_measured_axis(placement VmlPlacement, properties map[string]string, input string, declared_frame string, axis string, measured string) string {
	if placement == .width_preferred && axis == 'width' { return input + '.width' }
	return vml_prop(properties, axis, vml_measured_axis(placement, declared_frame + '.' + axis, measured))
}

fn vml_visual_base_property(name string) string {
	for prefix in ['hover_', 'focus_', 'pressed_', 'disabled_'] {
		if name.starts_with(prefix) {
			base := name[prefix.len..]
			if base in vml_box_properties || base == 'color' { return base }
		}
	}
	return name
}

fn vml_visual_property_use(name string) ?VmlExprUse {
	base := vml_visual_base_property(name)
	if base in ['weight', 'letter_spacing', 'line_height', 'line_height_factor', 'baseline_offset',
		'dash_length', 'dash_gap', 'outline_width', 'outline_offset', 'content_width', 'content_height',
		'gap', 'line_gap', 'translate_x', 'translate_y', 'scale_x', 'scale_y', 'origin_x', 'origin_y',
		'padding_left', 'padding_top', 'padding_right', 'padding_bottom', 'flex_basis', 'flex_grow',
		'flex_shrink', 'min_width', 'min_height', 'max_width', 'max_height', 'columns', 'cols',
		'rows', 'max_columns', 'auto_columns_min_width', 'column_span', 'row_span', 'spacing_x',
		'spacing_y', 'col_default_width', 'row_default_height', 'border_width', 'border_left',
		'border_top', 'border_right', 'border_bottom', 'radius', 'corner_radius'] {
		return .number
	}
	if base in ['transparent', 'tabular_figures', 'wrap', 'col_force_default', 'row_force_default',
		'password', 'readonly', 'disable_scroll', 'button_behavior'] {
		return .bool_
	}
	if base in ['background', 'color', 'border_color', 'outline_color', 'border_left_color',
		'border_top_color', 'border_right_color', 'border_bottom_color'] {
		return .color
	}
	if base in ['align', 'valign', 'align_items', 'align_self', 'justify', 'orientation',
		'border_pattern'] {
		return .raw
	}
	return none
}

fn vml_visual_integer_property(property VmlProperty) bool {
	return vml_visual_base_property(property.name) in ['weight', 'lines', 'columns', 'cols', 'rows',
		'max_columns', 'column_span', 'row_span', 'keyboard']
}

fn vml_typed_visual_value(node &VmlNode, property VmlProperty, value string) string {
	base := vml_visual_base_property(property.name)
	if typed := vml_widget_typed_value(node, property.name, value) { return typed }
	if vml_visual_integer_property(property) {
		return match base {
			'lines', 'weight' { 'ui2.TextStyle{${base}: ${value}}.${base}' }
			'columns', 'rows', 'max_columns' { 'ui2.GridConfig{${base}: ${value}}.${base}' }
			'cols' { 'ui2.GridConfig{columns: ${value}}.columns' }
			'column_span', 'row_span' { 'ui2.GridSpan{${base}: ${value}}.${base}' }
			'keyboard' { 'ui2.TextInputConfig{keyboard: ${value}}.keyboard' }
			else { 'ui2.TextStyle{weight: ${value}}.weight' }
		}
	}
	if vml_property_use(property) == .number {
		return 'ui2.LayoutSize{width: ${value}}.width'
	}
	if vml_property_use(property) == .color {
		return 'ui2.TextStyle{color: ${value}}.color'
	}
	if vml_property_use(property) in [.string_, .text] {
		return 'ui2.Element{text: ${value}}.text'
	}
	if vml_property_use(property) == .bool_ {
		return 'ui2.Element{hidden: ${value}}.hidden'
	}
	// Struct fields give shorthand enum values their expected type without
	// coercing an incorrectly typed dynamic value into an enum.
	return match base {
		'align', 'valign' { 'ui2.TextStyle{${base}: ${value}}.${base}' }
		'align_items' { 'ui2.FlexConfig{align: ${value}}.align' }
		'align_self' { 'ui2.FlexChild{align_self: ${value}}.align_self' }
		'justify' { 'ui2.FlexConfig{justify: ${value}}.justify' }
		'border_pattern' { 'ui2.BoxStyle{border_pattern: ${value}}.border_pattern' }
		'orientation' {
			typ := if node.tag == 'Grid' {
				'GridConfig'
			} else if node.tag == 'Slider' {
				'SliderConfig'
			} else {
				'FlexConfig'
			}
			'ui2.${typ}{orientation: ${value}}.orientation'
		}
		else { value }
	}
}

// Each conditional arm has its own expected type. The checker must validate
// inactive arms too, while runtime evaluates only the selected arm.
fn (c &VmlCompiler) visual_property_value(node &VmlNode, property VmlProperty, expr &VmlExpr, scope VmlScope) string {
	if property.name == 'key' {
		return vml_stringify(c.expr(expr, scope, .raw))
	}
	if expr.kind == .conditional {
		condition := c.expr(expr.left, scope, .bool_)
		then_value := c.visual_property_value(node, property, expr.right, scope)
		else_value := c.visual_property_value(node, property, expr.third, scope)
		return '(if ${condition} { ${then_value} } else { ${else_value} })'
	}
	if property.name == 'keyboard' && expr.kind == .path && expr.value in ['default', 'decimal'] {
		return 'ui2.keyboard_' + expr.value
	}
	if expr.kind == .path && expr.value in vml_visual_enum_values(node, property.name) {
		return vml_typed_visual_value(node, property, '.' + expr.value)
	}
	value := if vml_visual_integer_property(property) {
		c.expr(expr, scope, .raw)
	} else {
		c.expr(expr, scope, vml_property_use(property))
	}
	return vml_typed_visual_value(node, property, value)
}

fn vml_visual_enum_values(node &VmlNode, name string) []string {
	return match vml_visual_base_property(name) {
		'align' { ['left', 'center', 'right'] }
		'valign' { ['top', 'middle', 'bottom'] }
		'align_items' { ['start', 'center', 'end', 'stretch'] }
		'align_x', 'align_y' { ['start', 'center', 'end', 'stretch'] }
		'align_self_x', 'align_self_y' { ['auto', 'start', 'center', 'end', 'stretch'] }
		'tab_pos' {
			['top_left', 'top_mid', 'top_right', 'bottom_left', 'bottom_mid', 'bottom_right', 'left_top',
				'left_mid', 'left_bottom', 'right_top', 'right_mid', 'right_bottom']
		}
		'direction' {
			if node.tag == 'Carousel' { ['right', 'left', 'top', 'bottom'] } else { []string{} }
		}
		'align_self' { ['auto', 'start', 'center', 'end', 'stretch'] }
		'justify' { ['start', 'center', 'end', 'space_between', 'space_around', 'space_evenly'] }
		'border_pattern' { ['solid', 'dashed'] }
		'keyboard' { ['default', 'decimal'] }
		'orientation' {
			if node.tag == 'Grid' {
				['left_to_right_top_to_bottom', 'top_to_bottom_left_to_right',
					'right_to_left_top_to_bottom', 'top_to_bottom_right_to_left',
					'left_to_right_bottom_to_top', 'bottom_to_top_left_to_right',
					'right_to_left_bottom_to_top', 'bottom_to_top_right_to_left']
			} else {
				['horizontal', 'vertical']
			}
		}
		else { []string{} }
	}
}

fn vml_visual_property_allowed(node &VmlNode, name string, parent string) bool {
	if node.tag == 'Run' { return name == 'text' || name in vml_text_properties }
	if vml_widget_property_allowed(node, name, parent) { return true }
	if vml_is_event(name) { return name != 'on_submit' || node.tag == 'TextInput' }
	if name in ['id', 'ref', 'key', 'x', 'y', 'width', 'height', 'hidden', 'enabled', 'native',
		'clickable', 'draggable', 'long_press', 'swipe_left', 'button_behavior', 'rotation',
		'translate_x', 'translate_y', 'scale_x', 'scale_y', 'origin_x', 'origin_y', 'cursor', 'tooltip',
		'secure', 'autocorrect', 'pad_left', 'accessibility_role', 'accessibility_label',
		'accessibility_value', 'on_tap', 'on_change', 'on_active', 'on_submit'] {
		return true
	}
	if name in vml_box_properties {
		if node.tag in ['Screen', 'View', 'Absolute', 'Flex', 'Row', 'Column', 'Grid', 'Scroll',
			'ScaledContent', 'Label', 'Button', 'Dropdown', 'TextInput', 'TextArea', 'Spinner'] {
			return true
		}
		return (node.tag == 'ProgressBar' && name in ['background', 'radius', 'corner_radius'])
			|| (node.tag == 'Slider' && name == 'background')
	}
	base := vml_visual_base_property(name)
	if base != name { return base in vml_box_properties || base == 'color' }
	if name in vml_text_properties {
		return node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput', 'TextArea',
			'Spinner']
			|| (name == 'color' && node.tag in ['ProgressBar', 'Slider', 'Switch'])
	}
	if name in vml_flex_child_properties { return parent in ['Flex', 'Row', 'Column'] }
	if name in ['column_span', 'row_span'] { return parent == 'Grid' }
	return match node.tag {
		'Flex', 'Row', 'Column' {
			name in ['orientation', 'padding', 'padding_left', 'padding_top', 'padding_right',
				'padding_bottom', 'gap', 'spacing', 'line_gap', 'wrap', 'justify', 'align_items']
		}
		'Grid' {
			name in ['columns', 'cols', 'rows', 'orientation', 'padding', 'padding_left', 'padding_top',
				'padding_right', 'padding_bottom', 'spacing', 'spacing_x', 'spacing_y',
				'auto_columns_min_width', 'max_columns', 'col_default_width', 'row_default_height',
				'col_force_default', 'row_force_default']
		}
		'ScaledContent' { name in ['content_width', 'content_height'] }
		'Label', 'Button', 'Checkbox', 'MenuItem', 'Option' {
			name in ['text', 'checked', 'bind.checked']
		}
		'TextInput' {
			name in ['text', 'bind.text', 'placeholder', 'password', 'readonly', 'keyboard',
				'padding_left']
		}
		'TextArea' {
			name in ['text', 'bind.text', 'placeholder', 'readonly', 'disable_scroll', 'keyboard',
				'padding_left']
		}
		'Image' { name in ['source', 'path'] }
		'Scroll' { name == 'persistent' }
		'Repeater' { name == 'model' }
		'Dropdown' { name in ['text', 'bind.text'] }
		'Spinner' { name in ['text', 'bind.text', 'text_autoupdate'] }
		'Slider' {
			name in ['value', 'bind.value', 'min', 'max', 'step', 'orientation', 'padding',
				'value_track', 'value_track_color', 'thumb_color', 'track_width', 'thumb_size']
		}
		'Switch' {
			name in ['active', 'bind.active', 'inactive_color', 'active_color', 'thumb_color',
				'disabled_track_color', 'disabled_thumb_color']
		}
		'ProgressBar' { name in ['value', 'max'] }
		'MessageBox' { name in ['title', 'text', 'dialog_width', 'dialog_height'] }
		else { false }
	}
}

fn vml_visual_error(property VmlProperty, message string) IError {
	return if property.expr.source.len > 0 {
		error('${property.expr.source}:${property.line}:${property.column}: ${message}')
	} else {
		error('${message} at line ${property.line}, column ${property.column}')
	}
}

fn vml_visual_number(expr &VmlExpr) ?f64 {
	if expr.kind == .literal && !expr.quoted && expr.value !in ['true', 'false'] {
		return expr.value.f64()
	}
	if expr.kind == .unary && expr.value == '-' {
		value := vml_visual_number(expr.left) or { return none }
		return -value
	}
	return none
}

// Literal checks recurse through both conditional arms, even when the condition
// is false. Dynamic values are checked by V in the generated typed assignment.
fn validate_vml_visual_value(node &VmlNode, property VmlProperty, expr &VmlExpr, check_bounds bool, in_repeater bool) ! {
	if expr.kind == .conditional {
		validate_vml_visual_bool(property, expr.left)!
		validate_vml_visual_value(node, property, expr.right, check_bounds, in_repeater)!
		validate_vml_visual_value(node, property, expr.third, check_bounds, in_repeater)!
		return
	}
	use := vml_property_use(property)
	if use == .number && check_bounds {
		if value := vml_visual_number(expr) {
			base := vml_visual_base_property(property.name)
			if base in ['scale_x', 'scale_y'] && (!math.is_finite(value) || value == 0) {
				return vml_visual_error(property, '`${property.name}` must be finite and nonzero')
			}
			if base == 'weight' && (value != int(value) || (value != 0 && (value < 100 || value > 900))) {
				return vml_visual_error(property, 'weight must be zero or an integer from 100 to 900')
			}
			if base in ['content_width', 'content_height', 'font_size', 'size', 'column_span',
				'row_span'] && value <= 0 {
				return vml_visual_error(property, '`${property.name}` must be positive')
			}
			if base in ['line_height', 'line_height_factor'] && value < 0 {
				return vml_visual_error(property, '`${property.name}` cannot be negative')
			}
		}
	}
	values := vml_visual_enum_values(node, property.name)
	if values.len > 0 {
		if property.name == 'keyboard' && vml_visual_number(expr) != none { return }
		if expr.kind == .path && expr.value.starts_with('.') {
			return vml_visual_error(property, 'VML enum values omit the dot; use `${expr.value[1..]}`')
		}
		if expr.kind == .literal {
			return vml_visual_error(property, '`${property.name}` requires an enum value (${values[0]})')
		}
		return
	}

	if use == .bool_ { validate_vml_visual_bool(property, expr)! }
	if expr.kind == .literal {
		if use == .text && !expr.quoted && expr.value in ['true', 'false'] {
			return vml_visual_error(property, '`text` requires a string or number')
		}
		if use == .number && (expr.quoted || expr.value in ['true', 'false']) {
			return vml_visual_error(property, '`${property.name}` requires a number')
		}
		if use == .string_ && !expr.quoted {
			return vml_visual_error(property, '`${property.name}` requires a string')
		}
	}
	if use == .color && expr.kind in [.literal, .path] && (expr.quoted || expr.value.starts_with('#')) {
		if expr.value.len != 7 || !expr.value.starts_with('#') || !expr.value[1..].bytes().all(it.is_hex_digit()) {
			return vml_visual_error(property, '`${property.name}` requires a #RRGGBB color or a typed integer')
		}
	}
	if use == .color && expr.kind == .literal && !expr.quoted
		&& (expr.value in ['true', 'false'] || expr.value.contains('.')) {
		return vml_visual_error(property, '`${property.name}` requires a #RRGGBB color or a typed integer')
	}

	if (expr.kind == .binary && expr.value in ['+', '-', '*', '/', '%']) || (expr.kind == .unary && expr.value == '-') {
		if !isnil(expr.left) {
			validate_vml_visual_value(node, property, expr.left, false, in_repeater)!
		}
		if !isnil(expr.right) {
			validate_vml_visual_value(node, property, expr.right, false, in_repeater)!
		}
	}
}

fn validate_vml_visual_bool(property VmlProperty, expr &VmlExpr) ! {
	if expr.kind == .literal && (expr.quoted || expr.value !in ['true', 'false']) {
		return vml_visual_error(property, '`${property.name}` requires bool conditions/values')
	}
}

fn validate_compiled_vml_visual(node &VmlNode, parent string) ! {
	validate_compiled_vml_visual_scope(node, parent, false)!
	validate_vml_geometry_scope(node, parent, VmlScope{}, VmlScope{})!
}

// Layout inputs cannot depend on allocated element geometry except in Absolute.
// Model/member paths and viewport predicates used outside layout remain ordinary
// expressions. Track ids in the same lexical scope as lowering, including slots.
fn vml_layout_dimension_property(name string) bool {
	return name in ['x', 'y', 'width', 'height', 'min_width', 'min_height', 'max_width', 'max_height',
		'flex_basis', 'gap', 'spacing', 'line_gap', 'padding', 'padding_left', 'padding_top',
		'padding_right', 'padding_bottom', 'spacing_x', 'spacing_y', 'auto_columns_min_width',
		'col_default_width', 'row_default_height', 'content_width', 'content_height', 'dialog_width',
		'dialog_height']
}

fn vml_expr_uses_element_geometry(expr &VmlExpr, scope VmlScope) bool {
	if expr.kind == .path {
		parts := expr.value.split('.')
		if parts.len >= 2 && parts[0] in scope.ids
			&& parts[1] in ['x', 'y', 'width', 'height'] {
			return true
		}
	}
	if !isnil(expr.left) && vml_expr_uses_element_geometry(expr.left, scope) { return true }
	if !isnil(expr.right) && vml_expr_uses_element_geometry(expr.right, scope) { return true }
	if !isnil(expr.third) && vml_expr_uses_element_geometry(expr.third, scope) { return true }
	for arg in expr.args {
		if vml_expr_uses_element_geometry(arg, scope) { return true }
	}
	for part in expr.parts {
		if !isnil(part.expr) && vml_expr_uses_element_geometry(part.expr, scope) { return true }
	}
	return false
}

fn validate_vml_geometry_scope(node &VmlNode, parent string, incoming VmlScope, author VmlScope) !VmlScope {
	if node.caller_content {
		value := &VmlNode{ ...node, caller_content: false }
		validate_vml_geometry_scope(value, parent, author, author)!
		return incoming
	}
	mut scope := vml_clone_scope(incoming)
	if node.tag != '__Component' && node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{}
	}
	for property in node.properties {
		// Component arguments are data; only their shared child-layout arguments
		// participate in the surrounding container's layout.
		if node.tag == '__Component' && property.name !in vml_flex_child_properties { continue }
		if parent != 'Absolute' && vml_layout_dimension_property(property.name)
			&& vml_expr_uses_element_geometry(property.expr, scope) {
			return vml_visual_error(property, 'element geometry in `${property.name}` requires a parent Absolute container')
		}
	}
	if node.tag == '__Component' {
		mut private := VmlScope{}
		for child in node.children {
			private = validate_vml_geometry_scope(child, parent, private, incoming)!
		}
		return incoming
	}
	child_parent := if node.tag == 'Repeater' { parent } else { node.tag }
	for child in node.children {
		if node.tag != 'Repeater' && child.tag == 'Repeater' { continue }
		scope = validate_vml_geometry_scope(child, child_parent, scope, author)!
	}
	// Ordinary containers retain static children before registering list factories.
	// A factory sees those ids, but its per-row ids do not escape to the container.
	if node.tag != 'Repeater' {
		for child in node.children {
			if child.tag == 'Repeater' {
				validate_vml_geometry_scope(child, child_parent, scope, author)!
			}
		}
	} else {
		return incoming
	}
	return vml_node_output_scope(node, incoming, scope)
}

fn validate_compiled_vml_visual_scope(node &VmlNode, parent string, in_repeater bool) ! {
	if node.tag == 'Slot' { return }
	if node.tag == '__Component' {
		for child in node.children {
			validate_compiled_vml_visual_scope(child, parent, in_repeater)!
		}
		return
	}
	if node.tag in ['Menu', 'MenuBar'] {
		validate_compiled_vml_menu(node)!
		return
	}
	if node.tag !in ['Screen', 'View', 'Absolute', 'Flex', 'Row', 'Column', 'Grid', 'Scroll',
		'ScaledContent', 'Label', 'Run', 'TextInput', 'TextArea', 'Image', 'Button', 'Checkbox',
		'Dropdown', 'ProgressBar', 'Slider', 'Switch', 'Spinner', 'MessageBox', 'Repeater', 'MenuItem',
		'Option'] && !vml_widget_tag(node.tag) {
		return vml_visual_node_error(node, 'unsupported VML element `${node.tag}`')
	}
	if node.tag == 'Label' && node.children.any(it.tag !in ['Run', 'MenuItem']) {
		return vml_visual_node_error(node, 'Label children must be Run nodes')
	}
	if node.tag == 'TextInput' && node.children.any(it.tag == 'Run') {
		return vml_visual_node_error(node, 'TextInput is single-line; use TextArea for Run content')
	}
	if node.tag == 'Run' && parent !in ['Label', 'TextArea'] {
		return vml_visual_node_error(node, 'Run must be a child of Label or TextArea')
	}
	if node.tag == 'Run' && node.children.len > 0 {
		return vml_visual_node_error(node, 'Run cannot contain children')
	}

	mut seen := map[string]bool{}
	for property in node.properties {
		if property.name in ['x', 'y'] && parent != 'Absolute' {
			return vml_visual_error(property, 'x/y require a parent Absolute container')
		}
		if property.name == 'orientation' && node.tag in ['Row', 'Column'] {
			return vml_visual_error(property, '${node.tag} selects its orientation')
		}
		if property.name in seen {
			return vml_visual_error(property, 'duplicate property `${property.name}`')
		}
		seen[property.name] = true
		if !vml_visual_property_allowed(node, property.name, parent) {
			return vml_visual_error(property, 'unsupported property `${property.name}` on ${node.tag}')
		}
		if !property.name.starts_with('on_') && property.name != 'model' {
			validate_vml_visual_value(node, property, property.expr, true, in_repeater || node.tag == 'Repeater')!
		}
	}
	if node.tag == 'Label' && node.children.any(it.tag == 'Run') {
		if 'text' in seen || 'bind.text' in seen {
			return vml_visual_node_error(node, 'Label uses either text or Run children')
		}
		if node.children.any(it.tag !in ['Run', 'MenuItem']) {
			return vml_visual_node_error(node, 'Label children must be Run nodes')
		}
	}
	if node.tag == 'ScaledContent' {
		for name in ['content_width', 'content_height'] {
			if name !in seen {
				return vml_visual_node_error(node, 'ScaledContent requires `${name}`')
			}
		}
	}
	// Repeater delegates occupy the surrounding container; the directive creates no element.
	child_parent := if node.tag == 'Repeater' { parent } else { node.tag }
	for child in node.children {
		validate_compiled_vml_visual_scope(child, child_parent, in_repeater || node.tag == 'Repeater')!
	}
}

fn validate_vml_native_visual(node &VmlNode) ! {
	if node.tag in ['ScaledContent', 'Run'] {
		return vml_visual_node_error(node, '${node.tag} requires the custom renderer')
	}
	for property in node.properties {
		base := vml_visual_base_property(property.name)
		if base != property.name || base in ['translate_x', 'translate_y', 'scale_x', 'scale_y',
			'origin_x', 'origin_y', 'weight', 'letter_spacing', 'line_height', 'line_height_factor',
			'baseline_offset', 'tabular_figures', 'font_family', 'background_color', 'strikethrough',
			'shadow', 'outline', 'vertical_align', 'link', 'head_indent', 'first_line_indent',
			'hyphenation_factor', 'border_left_color', 'border_top_color', 'border_right_color',
			'border_bottom_color', 'border_pattern', 'dash_length', 'dash_gap', 'outline_color',
			'outline_width', 'outline_offset'] {
			return vml_visual_error(property, '`${property.name}` requires the custom renderer')
		}
	}
	for child in node.children { validate_vml_native_visual(child)! }
}

fn (c &VmlCompiler) visual_box_style(properties map[string]string, prefix string, patch bool) string {
	mut fields := []string{}
	for name in vml_box_properties {
		if name in ['border_width', 'corner_radius'] { continue }
		mut value := properties[prefix + name] or { '' }
		if name == 'radius' {
			value = vml_value(properties, prefix + 'corner_radius', prefix + 'radius', '')
		}
		if name in ['border_left', 'border_top', 'border_right', 'border_bottom'] {
			value = vml_value(properties, prefix + name, prefix + 'border_width', '')
		}
		if value.len == 0 { continue }
		field := if name == 'background' { 'bg' } else { name }
		fields << '${field}: ${value}'
	}
	return 'ui2.${if patch { 'BoxStylePatch' } else { 'BoxStyle' }}{${fields.join(', ')}}'
}

fn (c &VmlCompiler) interaction_style(properties map[string]string) string {
	mut fields := []string{}
	for state in ['hover', 'focus', 'pressed', 'disabled'] {
		fields << '${state}: ${c.visual_box_style(properties, state + '_', true)}'
		if color := properties[state + '_color'] {
			fields << '${state}_text: ui2.TextStylePatch{color: ${color}}'
		}
	}
	return 'ui2.InteractionStyle{${fields.join(', ')}}'
}

fn (mut c VmlCompiler) prepare_visual_runs(node &VmlNode, suffix string, mut inherited map[string]string, scope VmlScope) {
	mut runs := []string{}
	for index, child in node.children {
		if child.tag != 'Run' { continue }
		mut properties := inherited.clone()
		for property in child.properties {
			name := 'vml_property_${suffix}_run_${index}_${vml_var(property.name)}'
			c.location = VmlLocation{ path: property.expr.source, line: property.line, column: property.column }
			value := c.visual_property_value(child, property, property.expr, scope)
			c.writeln('\t${name} := ${value}')
			c.writeln('\t_ = ${name}')
			c.property_positions[name] = property
			properties[property.name] = name
			if property.name == 'size' { properties.delete('font_size') }
		}
		runs << 'ui2.TextRun{text: ${vml_prop(properties, 'text', "''")}, style: ${c.text_style(properties)}}'
	}
	name := 'vml_runs_${suffix}'
	c.writeln('\t${name} := ${vml_array_literal('ui2.TextRun', runs)}')
	inherited['@runs'] = name
	inherited['@run_text'] = "${name}.map(it.text).join('')"
}

fn vml_layout_padding(properties map[string]string, typ string) string {
	mut fields := []string{}
	for side in ['left', 'top', 'right', 'bottom'] {
		fields << '${side}: ${vml_value(properties, 'padding_' + side, 'padding', 'f64(0)')}'
	}
	return 'ui2.${typ}{${fields.join(', ')}}'
}

fn (c &VmlCompiler) visual_child_properties(node &VmlNode, path string) map[string]string {
	mut properties := map[string]string{}
	for property in node.properties {
		properties[property.name] = 'vml_property_${vml_var(path)}_${vml_var(property.name)}'
	}
	return properties
}

fn vml_flex_item(element string, properties map[string]string) string {
	mut fields := ['element: ${element}']
	for pair in [['flex_basis', 'basis'], ['flex_grow', 'grow'], ['flex_shrink', 'shrink'],
		['min_width', 'minimum_width'], ['min_height', 'minimum_height'],
		['max_width', 'maximum_width'], ['max_height', 'maximum_height'], ['align_self', 'align_self']] {
		if value := properties[pair[0]] { fields << '${pair[1]}: ${value}' }
	}
	return 'ui2.FlexChild{${fields.join(', ')}}'
}

fn (c &VmlCompiler) visual_layout_config(node &VmlNode, frame string, properties map[string]string, children string, spans string) string {
	mut fields := ['id: ${vml_quote(node.id)}', 'frame: ${frame}', 'box: ${c.box_style(properties)}',
		'children: ${children}']
	if node.tag == 'Grid' {
		fields << 'padding: ${vml_layout_padding(properties, 'GridPadding')}'
		fields << 'child_spans: ${spans}'
		fields << 'columns: int(${vml_value(properties, 'columns', 'cols', 'f64(0)')})'
		fields << 'spacing: ui2.GridSpacing{horizontal: ${vml_value(properties, 'spacing_x', 'spacing', 'f64(0)')}, vertical: ${vml_value(properties, 'spacing_y', 'spacing', 'f64(0)')}}'
		for pair in [['rows', 'rows'], ['max_columns', 'max_columns'],
			['auto_columns_min_width', 'auto_columns_min_width'],
			['col_default_width', 'column_default_width'],
			['row_default_height', 'row_default_height'], ['col_force_default', 'force_column_width'],
			['row_force_default', 'force_row_height'], ['orientation', 'orientation']] {
			if value := properties[pair[0]] {
				fields << '${pair[1]}: ${if pair[0] in ['rows', 'max_columns'] {
					'int(' + value + ')'
				} else {
					value
				}}'
			}
		}
		return 'ui2.GridConfig{${fields.join(', ')}}'
	}
	fields << 'padding: ${vml_layout_padding(properties, 'LayoutPadding')}'
	fields << 'orientation: ${if node.tag == 'Row' {
		'ui2.LayoutOrientation.horizontal'
	} else if node.tag == 'Column' {
		'ui2.LayoutOrientation.vertical'
	} else {
		vml_prop(properties, 'orientation', 'ui2.LayoutOrientation.horizontal')
	}}'
	if 'spacing' in properties && 'gap' !in properties { fields << 'gap: ' + properties['spacing'] }
	for pair in [['gap', 'gap'], ['line_gap', 'line_gap'], ['wrap', 'wrap'], ['justify', 'justify'],
		['align_items', 'align']] {
		if value := properties[pair[0]] { fields << '${pair[1]}: ${value}' }
	}
	return 'ui2.FlexConfig{${fields.join(', ')}}'
}

// Retain authored children and their typed layout rules once. ui2's LayoutTree
// measures and allocates this tree, including wrapping at the allocated width.
fn (mut c VmlCompiler) compile_visual_layout(node &VmlNode, path string, input string, frame string, properties map[string]string, incoming VmlScope, placement VmlPlacement, default_key string) VmlScope {
	_ = input
	_ = placement
	suffix := vml_var(path)
	grid := node.tag == 'Grid'
	mut scope := vml_clone_scope(incoming)
	items := 'vml_items_${suffix}'
	spans := 'vml_spans_${suffix}'
	children := 'vml_children_${suffix}'
	c.writeln('\tmut ${items} := []ui2.${if grid { 'Element' } else { 'FlexChild' }}{}')
	c.writeln('\tmut ${spans} := []ui2.GridSpan{}')
	c.writeln('_ = ${spans}')
	c.writeln('\tmut ${children} := []ui2.Element{}')
	visible := node.children.filter(it.tag !in ['MenuItem', 'Option', 'Run'])
	for index, child in visible {
		child_path := '${path}.${index}'
		if child.tag == 'Repeater' { continue }
		child_input := 'vml_input_${vml_var(child_path)}'
		c.writeln('\t${child_input} := ui2.rect(0, 0, ${frame}.width, ${frame}.height)')
		child_scope := c.compile_node(child, child_path, child_input, scope, '', .preferred)
		for id, named in child_scope.ids { scope.ids[id] = named }
		c.write_child_layout(child, 'vml_node_' + vml_var(child_path), vml_var(child_path), node.tag, child_scope)
		child_properties := c.visual_child_properties(child, child_path)
		element := 'vml_element_${vml_var(child_path)}'
		c.writeln('\t${items} << ${if grid {
			element
		} else {
			vml_flex_item(element, child_properties)
		}}')
		c.writeln('\t${children} << ${element}')
		if grid {
			c.writeln('\t${spans} << ui2.GridSpan{column_span: int(${vml_prop(child_properties, 'column_span', 'f64(1)')}), row_span: int(${vml_prop(child_properties, 'row_span', 'f64(1)')})}')
		}
	}
	config := 'vml_config_${suffix}'
	c.writeln('\t${config} := ${c.visual_layout_config(node, frame, properties, items, spans)}')
	base := 'vml_layout_${suffix}'
	c.writeln('\t${base} := ui2.${if grid { 'grid_declaration' } else { 'flex' }}(${config}) or { panic(err) }')
	mutable := properties.clone()
	c.compile_element(node, suffix + '_plain', frame, children, mutable, scope, default_key)
	plain := 'vml_declaration_${suffix}_plain'
	c.writeln('\tvml_declaration_${suffix} := ui2.Element{...${plain}, frame: ${base}.frame, children: ${children}, layout: ${base}.layout, layout_input: ${base}.layout_input}')
	return scope
}

fn vml_visual_node_error(node &VmlNode, message string) IError {
	return if node.source.len > 0 {
		error('${node.source}:${node.line}:${node.column}: ${message}')
	} else {
		error('${message} at line ${node.line}, column ${node.column}')
	}
}
