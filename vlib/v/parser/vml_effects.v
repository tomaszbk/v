module parser

// Every dynamic presentation property patches its canonical ui2 field. The
// runtime validates and publishes retained nodes; layout remains in ui2.
fn vml_property_patch(node &VmlNode, name string, value string) ?string {
	if node.tag == 'Slider' && name in ['background', 'color', 'value_track_color', 'thumb_color',
		'track_width', 'thumb_size'] {
		field := match name {
			'background' { 'track_color' }
			'color' { 'value_track_color' }
			else { name }
		}
		return 'slider_style: ui2.SliderStyle{...element.slider_style, ${field}: ${value}}'
	}
	if node.tag == 'Switch' && name in ['color', 'inactive_color', 'active_color', 'thumb_color',
		'disabled_track_color', 'disabled_thumb_color'] {
		field := match name {
			'inactive_color' { 'inactive_track_color' }
			'color', 'active_color' { 'active_track_color' }
			else { name }
		}
		return 'switch_style: ui2.SwitchStyle{...element.switch_style, ${field}: ${value}}'
	}
	if node.tag == 'TextInput' && name == 'password' { return 'secure: ${value}' }
	base := vml_visual_base_property(name)
	if base != name {
		state := name[..name.len - base.len - 1]
		member := if base == 'color' { state + '_text' } else { state }
		typ := if base == 'color' { 'TextStylePatch' } else { 'BoxStylePatch' }
		field := match base {
			'background' { 'bg' }
			'corner_radius' { 'radius' }
			else { base }
		}
		fields := if base == 'border_width' {
			['border_left', 'border_top', 'border_right', 'border_bottom'].map('${it}: ${value}').join(', ')
		} else {
			'${field}: ${value}'
		}
		return 'interaction_style: ui2.InteractionStyle{...element.interaction_style, ${member}: ui2.${typ}{...element.interaction_style.${member}, ${fields}}}'
	}
	if name in vml_box_properties {
		field := match name {
			'background' { 'bg' }
			'corner_radius' { 'radius' }
			else { name }
		}
		fields := if name == 'border_width' {
			['border_left', 'border_top', 'border_right', 'border_bottom'].map('${it}: ${value}').join(', ')
		} else {
			'${field}: ${value}'
		}
		return 'box: ui2.BoxStyle{...element.box, ${fields}}'
	}
	if name in vml_text_properties && !(node.tag in ['Slider', 'Switch', 'ProgressBar'] && name == 'color') {
		field := if name in ['font_size', 'size'] { 'size' } else { name }
		return 'text_style: ui2.TextStyle{...element.text_style, ${field}: ${value}}'
	}
	if name in ['x', 'y', 'width', 'height'] {
		return 'frame: ui2.Rect{...element.frame, ${name}: ${value}}'
	}
	if node.tag in ['Flex', 'Row', 'Column', 'Grid', 'Stack'] {
		kind := if node.tag == 'Grid' {
			'grid'
		} else if node.tag == 'Stack' {
			'stack'
		} else {
			'flex'
		}
		typ := if kind == 'grid' {
			'GridConfig'
		} else if kind == 'stack' {
			'StackConfig'
		} else {
			'FlexConfig'
		}
		mut field := name
		if name.starts_with('padding') {
			padding := if kind == 'grid' { 'GridPadding' } else { 'LayoutPadding' }
			fields := if name == 'padding' {
				['left', 'top', 'right', 'bottom'].map('${it}: ${value}').join(', ')
			} else {
				name.all_after('padding_') + ': ' + value
			}
			return 'layout: ui2.LayoutSpec{...element.layout, ${kind}: ui2.${typ}{...element.layout.${kind}, padding: ui2.${padding}{...element.layout.${kind}.padding, ${fields}}}}'
		}
		if kind == 'grid' && name in ['spacing', 'spacing_x', 'spacing_y'] {
			fields := if name == 'spacing' {
				'horizontal: ${value}, vertical: ${value}'
			} else {
				'${if name == 'spacing_x' { 'horizontal' } else { 'vertical' }}: ${value}'
			}
			return 'layout: ui2.LayoutSpec{...element.layout, grid: ui2.GridConfig{...element.layout.grid, spacing: ui2.GridSpacing{...element.layout.grid.spacing, ${fields}}}}'
		}
		field = match name {
			'cols' { 'columns' }
			'col_default_width' { 'column_default_width' }
			'col_force_default' { 'force_column_width' }
			'row_force_default' { 'force_row_height' }
			'align_items' { 'align' }
			'spacing' { 'gap' }
			else { field }
		}
		if field in ['gap', 'line_gap', 'wrap', 'justify', 'align', 'orientation', 'columns', 'rows',
			'max_columns', 'auto_columns_min_width', 'column_default_width', 'row_default_height',
			'force_column_width', 'force_row_height', 'align_x', 'align_y'] {
			return 'layout: ui2.LayoutSpec{...element.layout, ${kind}: ui2.${typ}{...element.layout.${kind}, ${field}: ${value}}}'
		}
	}
	if node.tag == 'ScaledContent' && name in ['content_width', 'content_height'] {
		return 'content_size: ui2.LayoutSize{...element.content_size, ${name.all_after('content_')}: ${value}}'
	}
	field := match name {
		'bind.text', 'text' { 'text' }
		'checked', 'bind.checked', 'active', 'bind.active', 'pressed', 'bind.pressed' { 'checked' }
		'bind.value' { 'value' }
		'source', 'path' { 'image_path' }
		'native' { 'native_style' }
		'persistent' { 'persistent_scrollbars' }
		'pad_left' { 'padding_left' }
		'min' { 'min_value' }
		'max' { 'max_value' }
		else { name }
	}
	if field in ['key', 'text', 'checked', 'value', 'image_path', 'native_style',
		'persistent_scrollbars', 'hidden', 'enabled', 'tooltip', 'cursor', 'accessibility_role',
		'accessibility_label', 'accessibility_value', 'secure', 'autocorrect', 'readonly',
		'disable_scroll', 'placeholder', 'keyboard', 'padding_left', 'clickable', 'draggable',
		'long_press', 'swipe_left', 'button_behavior', 'rotation', 'translate_x', 'translate_y',
		'scale_x', 'scale_y', 'origin_x', 'origin_y', 'min_value', 'max_value', 'step', 'orientation',
		'padding', 'value_track', 'value_track_color', 'thumb_color', 'track_width', 'thumb_size',
		'inactive_color', 'active_color', 'disabled_track_color', 'disabled_thumb_color',
		'text_autoupdate', 'group', 'allow_no_selection'] {
		return '${field}: ${value}'
	}
	return none
}

fn (mut c VmlCompiler) compile_structural_effect(node &VmlNode, suffix string, incoming VmlScope) {
	if node.tag !in ['Accordion', 'AccordionItem', 'TabbedPanel', 'Tab', 'TreeView', 'TreeNode',
		'ScreenManager', 'Screen', 'ManagedScreen', 'ScreenView', 'Carousel', 'Popup', 'ModalView',
		'ToggleButton', 'MessageBox', 'ProgressBar', 'Spinner'] {
		return
	}
	if node.tag == 'Screen' && vml_find_property(node, 'name') == none { return }
	variable := 'vml_node_' + suffix
	sources := 'vml_children_' + suffix.trim_string_right('_base')
	if node.tag !in ['MessageBox', 'ProgressBar', 'Spinner'] {
		c.writeln('${variable}.set_sources(${sources}) or { panic(err) }')
	}
	mut scope := vml_clone_scope(incoming)
	scope.special['__node_suffix'] = suffix
	mut captures := c.scope_captures(scope)
	captures << 'mut ' + variable
	if ('mut ' + scope.component) !in captures { captures << 'mut ' + scope.component }
	for name, reference in c.event_references {
		if name.starts_with(suffix + ':message_action:') && reference !in captures {
			captures << reference
		}
	}
	for name in vml_event_names {
		if reference := c.event_references[suffix + ':' + name] {
			if reference !in captures { captures << reference }
		}
	}
	prefix := '${variable}.structure(' + vml_quote('@widget') + ', fn '
	capture_start := c.out.len + prefix.len
	c.writeln(prefix + '[] () !ui2.Element {')
	body_start := c.out.len
	if c.uses_app { c.writeln('${scope.component}.watch_app()!') }
	c.writeln('element := ${variable}.element()')
	children := 'vml_widget_sources_' + suffix
	if node.tag !in ['MessageBox', 'ProgressBar', 'Spinner'] {
		c.writeln('${children} := ${variable}.child_elements()!')
		c.writeln('_ = ${children}')
	}
	c.writeln('frame := ${variable}.frame()!')
	mut properties := map[string]string{}
	for property in node.properties {
		if property.name in ['id', 'ref'] || vml_is_event(property.name) { continue }
		properties[property.name] = c.property_effect_value(node, property, suffix, scope)
		captures << c.property_memo_capture(suffix, property.name)
	}
	for child in node.children {
		if child.tag == 'Option' {
			captures << c.property_memo_capture(vml_content_suffix(suffix, child), 'text')
		}
	}
	c.effect_mode = true
	if node.tag == 'MessageBox' {
		c.compile_message_box(node, suffix + '_effect', 'frame', properties, scope, 'element.key', 'element.on_event')
	} else if node.tag == 'ProgressBar' {
		c.compile_progress_bar(node, suffix + '_effect', 'frame', properties, scope, 'element.key', 'element.on_event')
	} else if node.tag == 'Spinner' {
		c.compile_spinner(node, suffix + '_effect', 'frame', properties, scope, 'element.key', 'element.on_event')
	} else {
		c.compile_widget(node, suffix + '_effect', 'frame', children, properties, scope, 'element.key', 'element.on_event')
	}
	c.effect_mode = false
	c.writeln('return vml_declaration_${suffix}_effect')
	c.finish_scope_captures(capture_start, body_start, captures)
	c.writeln('}) or { panic(err) }')
}

fn (mut c VmlCompiler) compile_content_effect(node &VmlNode, suffix string, scope VmlScope) {
	runs := node.children.filter(it.tag == 'Run')
	menu := node.children.filter(it.tag in ['Option', 'MenuItem'])
	if runs.len == 0 && menu.len == 0 { return }
	mut expressions := []&VmlExpr{}
	for property in node.properties {
		if property.name in vml_text_properties { expressions << property.expr }
	}
	for child in runs { expressions << child.properties.map(it.expr) }
	for child in menu { if title := vml_find_property(child, 'text') { expressions << title.expr } }
	expression := &VmlExpr{ kind: .block, args: expressions }
	mut captures := vml_callback_captures(expression, scope)
	app_dependency := vml_expr_uses_path(expression, 'app')
	if app_dependency { captures << 'mut ' + scope.component }
	variable := 'vml_node_' + suffix
	initial := 'vml_declaration_' + suffix
	if menu.len > 0 { captures << initial }
	prefix := '${variable}.effect(' + vml_quote(if runs.len > 0 { '@runs' } else { '@menu' }) + ', fn '
	capture_start := c.out.len + prefix.len
	c.writeln(prefix + '[] (element ui2.Element) !ui2.Element {')
	body_start := c.out.len
	if app_dependency { c.writeln('${scope.component}.watch_app()!') }
	if runs.len > 0 {
		mut inherited := map[string]string{}
		for property in node.properties {
			if property.name in vml_text_properties {
				inherited[property.name] = c.property_effect_value(node, property, suffix, scope)
				captures << c.property_memo_capture(suffix, property.name)
			}
		}
		mut values := []string{}
		for index, child in node.children {
			if child.tag != 'Run' { continue }
			mut properties := inherited.clone()
			for property in child.properties {
				child_suffix := '${suffix}_run_${index}'
				properties[property.name] = c.property_effect_value(child, property, child_suffix, scope)
				captures << c.property_memo_capture(child_suffix, property.name)
			}
			values << 'ui2.TextRun{text: ${vml_prop(properties, 'text', "''")}, style: ${c.text_style(properties)}}'
		}
		c.writeln('runs := ' + vml_array_literal('ui2.TextRun', values))
		c.writeln("return ui2.Element{...element, text: runs.map(it.text).join(''), text_runs: runs}")
	} else {
		mut values := []string{}
		for index, child in menu {
			text := if property := vml_find_property(child, 'text') {
				child_suffix := vml_content_suffix(suffix, child)
				captures << c.property_memo_capture(child_suffix, property.name)
				c.property_effect_value(child, property, child_suffix, scope)
			} else {
				"''"
			}
			values << 'ui2.MenuEntry{...${initial}.menu[${index}], title: ${text}' + if child.tag == 'Option' {
				', id: ' + text
			} else {
				''
			} + '}'
		}
		c.writeln('return ui2.Element{...element, menu: ' + vml_array_literal('ui2.MenuEntry', values) + '}')
	}
	c.finish_scope_captures(capture_start, body_start, captures)
	c.writeln('}) or { panic(err) }')
}
