module parser

// Typed composite declarations lower to the existing ui2 control APIs. Child
// records carry only the relevant typed config, never interpreter AST data.
fn vml_widget_tag(tag string) bool {
	return tag in ['Stack', 'Accordion', 'AccordionItem', 'Carousel', 'CarouselSlide', 'ScreenManager',
		'ManagedScreen', 'ScreenView', 'Popup', 'ModalView', 'TreeView', 'TreeNode', 'TabbedPanel',
		'Tab', 'ToggleButton']
}

fn vml_widget_property_allowed(node &VmlNode, name string, parent string) bool {
	if name in vml_box_properties && vml_widget_tag(node.tag) { return true }
	if name in vml_text_properties && node.tag in ['ToggleButton', 'TreeView'] { return true }
	if name in ['align_self_x', 'align_self_y'] { return parent == 'Stack' }
	return match node.tag {
		'Stack' {
			name in ['padding', 'padding_left', 'padding_top', 'padding_right', 'padding_bottom',
				'align_x', 'align_y']
		}
		'Accordion' {
			name in ['current', 'orientation', 'min_space', 'title_background',
				'active_title_background', 'title_color', 'active_title_color', 'title_font_size',
				'title_corner_radius']
		}
		'AccordionItem' { name in ['title', 'on_select'] }
		'Carousel' {
			name in ['index', 'direction', 'loop', 'min_move', 'ignore_perpendicular_swipes']
		}
		'ScreenManager' { name == 'current' }
		'Screen', 'ManagedScreen', 'ScreenView' { name == 'name' && parent == 'ScreenManager' }
		'Popup', 'ModalView' {
			name in ['open', 'auto_dismiss', 'on_dismiss', 'content_width', 'content_height',
				'size_hint_x', 'size_hint_y', 'overlay_background', 'title', 'title_height',
				'title_color', 'title_font_size', 'title_bold', 'separator_height', 'separator_color']
		}
		'TreeView' {
			name in ['row_height', 'spacing', 'indent', 'disclosure_width', 'row_background',
				'row_corner_radius', 'selected_background', 'disclosure_background', 'selected_color',
				'disclosure_color']
		}
		'TreeNode' { name in ['text', 'title', 'expanded', 'selected', 'on_select', 'on_toggle'] }
		'TabbedPanel' {
			name in ['current', 'current_tab', 'tab_pos', 'tab_height', 'tab_width', 'tab_background',
				'active_tab_background', 'tab_color', 'active_tab_color', 'tab_font_size',
				'tab_corner_radius']
		}
		'Tab' { name in ['text', 'on_select'] }
		'ToggleButton' {
			name in ['text', 'pressed', 'bind.pressed', 'group', 'allow_no_selection', 'down_background',
				'down_color', 'down_corner_radius']
		}
		else { false }
	}
}

fn vml_widget_property_use(name string) ?VmlExprUse {
	if name in ['title_background', 'active_title_background', 'title_color', 'active_title_color',
		'overlay_background', 'separator_color', 'row_background', 'selected_background',
		'disclosure_background', 'selected_color', 'disclosure_color', 'tab_background',
		'active_tab_background', 'tab_color', 'active_tab_color', 'down_background', 'down_color'] {
		return .color
	}
	if name in ['open', 'auto_dismiss', 'expanded', 'selected', 'pressed', 'bind.pressed', 'loop',
		'ignore_perpendicular_swipes', 'title_bold', 'allow_no_selection'] {
		return .bool_
	}
	if name in ['min_space', 'title_font_size', 'title_corner_radius', 'min_move', 'size_hint_x',
		'size_hint_y', 'title_height', 'separator_height', 'row_height', 'spacing', 'indent',
		'disclosure_width', 'row_corner_radius', 'tab_height', 'tab_width', 'tab_font_size',
		'tab_corner_radius', 'down_corner_radius'] {
		return .number
	}
	if name in ['name', 'title', 'group'] { return .string_ }
	return none
}

fn vml_widget_typed_value(node &VmlNode, name string, value string) ?string {
	return match name {
		'current' {
			if node.tag == 'ScreenManager' {
				'ui2.ScreenManagerConfig{current: ${value}}.current'
			} else if node.tag in ['Accordion', 'TabbedPanel'] {
				'ui2.TabbedPanelConfig{current: ${value}}.current'
			} else {
				return none
			}
		}
		'current_tab' { 'ui2.TabbedPanelConfig{current: ${value}}.current' }
		'index' {
			if node.tag == 'Carousel' {
				'ui2.CarouselConfig{index: ${value}}.index'
			} else {
				return none
			}
		}
		'tab_pos' { 'ui2.TabbedPanelConfig{tab_position: ${value}}.tab_position' }
		'direction' {
			if node.tag == 'Carousel' {
				'ui2.CarouselConfig{direction: ${value}}.direction'
			} else {
				return none
			}
		}
		'align_x', 'align_y' { 'ui2.StackConfig{${name}: ${value}}.${name}' }
		'align_self_x' { 'ui2.StackChild{align_x: ${value}}.align_x' }
		'align_self_y' { 'ui2.StackChild{align_y: ${value}}.align_y' }
		else { return none }
	}
}

fn vml_widget_box(properties map[string]string, color string, fallback string, radius string, radius_default string) string {
	return 'ui2.BoxStyle{bg: ${vml_prop(properties, color, fallback)}, radius: ${vml_prop(properties, radius, radius_default)}}'
}

fn vml_widget_text(properties map[string]string, color string, fallback string, size string, size_default string, bold bool) string {
	return 'ui2.TextStyle{color: ${vml_prop(properties, color, fallback)}, size: ${vml_prop(properties, size, size_default)}, bold: ${bold}, align: .center}'
}

fn (mut c VmlCompiler) compile_widget(node &VmlNode, suffix string, frame string, children string, properties map[string]string, scope VmlScope, key string, action string) bool {
	if !vml_widget_tag(node.tag) && !(node.tag == 'Screen' && vml_find_property(node, 'name') != none) {
		return false
	}
	id := c.control_id(node, suffix, scope)
	box := c.box_style(properties)
	output := 'vml_declaration_${suffix}'
	temporary := 'vml_widget_${suffix}'
	mut constructor := ''
	mut metadata := ''
	match node.tag {
		'Stack' {
			padding := vml_prop(properties, 'padding', 'f64(0)')
			mut rules := []string{}
			for index, child in node.children {
				if child.tag == 'Repeater' { continue }
				align_x := if prop := vml_find_property(child, 'align_self_x') {
					c.visual_property_value(child, prop, prop.expr, scope)
				} else {
					'.auto'
				}
				align_y := if prop := vml_find_property(child, 'align_self_y') {
					c.visual_property_value(child, prop, prop.expr, scope)
				} else {
					'.auto'
				}
				rules << 'ui2.StackChild{element: ${children}[${index}], align_x: ${align_x}, align_y: ${align_y}}'
			}
			constructor = 'ui2.stack(ui2.StackConfig{id: ${id}, frame: ${frame}, box: ${box}, padding: ui2.LayoutPadding{left: ${vml_prop(properties, 'padding_left', padding)}, top: ${vml_prop(properties, 'padding_top', padding)}, right: ${vml_prop(properties, 'padding_right', padding)}, bottom: ${vml_prop(properties, 'padding_bottom', padding)}}, align_x: ${vml_prop(properties, 'align_x', 'ui2.LayoutAlignment.start')}, align_y: ${vml_prop(properties, 'align_y', 'ui2.LayoutAlignment.start')}, children: ${if node.children.any(it.tag == 'Repeater') {
				children + '.map(ui2.StackChild{element: it})'
			} else {
				vml_array_literal('ui2.StackChild', rules)
			}}}) or { panic(err) }'
		}
		'AccordionItem', 'Tab' {
			constructor = 'ui2.view((if ${id}.len > 0 { ${id} + "__content" } else { "" }), ${frame}, ${box}, ${children})'
			title := vml_prop(properties, if node.tag == 'Tab' { 'text' } else { 'title' }, "''")
			typed := if node.tag == 'Tab' {
				'tab: ui2.TabbedPanelTab'
			} else {
				'accordion: ui2.AccordionItem'
			}
			metadata = '${typed}{id: ${id}, title: ${title}, on_event: ${c.event_callback(node, 'on_select', scope)}, enabled: ${vml_prop(properties, 'enabled', 'true')}}'
		}
		'Accordion', 'TabbedPanel' {
			tabs := node.tag == 'TabbedPanel'
			config := if tabs { 'TabbedPanelConfig' } else { 'AccordionConfig' }
			method := if tabs { 'tabbed_panel' } else { 'accordion' }
			member := if tabs { 'tab' } else { 'accordion' }
			type_name := if tabs { 'TabbedPanelTab' } else { 'AccordionItem' }
			config_member := if tabs { 'tabs' } else { 'items' }
			prefix := if tabs { 'tab' } else { 'title' }
			active := if tabs { 'active_tab' } else { 'active_title' }
			more := if tabs {
				'tab_position: ${vml_prop(properties, 'tab_pos', 'ui2.TabPosition.top_left')}, tab_height: ${vml_prop(properties, 'tab_height', 'f64(40)')}, tab_width: ${vml_prop(properties, 'tab_width', 'f64(100)')},'
			} else {
				'orientation: ${vml_prop(properties, 'orientation', 'ui2.LayoutOrientation.horizontal')}, min_space: ${vml_prop(properties, 'min_space', 'f64(44)')},'
			}
			data := '${children}.map(ui2.${type_name}{...(it.compiled_metadata.${member} or {panic("${node.tag} requires typed child declarations")}), content: it})'
			constructor = 'ui2.${method}(ui2.${config}{id: ${id}, frame: ${frame}, box: ${box}, current: ${vml_prop(properties, 'current', vml_prop(properties, 'current_tab', '0'))}, ${more} header_box: ${vml_widget_box(properties, prefix + '_background', 'u32(0xe2e8f0)', prefix + '_corner_radius', 'f64(6)')}, active_header_box: ${vml_widget_box(properties, active + '_background', if tabs {
				'u32(0xffffff)'
			} else {
				'u32(0x2563eb)'
			}, prefix + '_corner_radius', 'f64(6)')}, header_text_style: ${vml_widget_text(properties, prefix + '_color', 'u32(0x475569)', prefix + '_font_size', 'f64(14)', false)}, active_header_text_style: ${vml_widget_text(properties, active + '_color', if tabs {
				'u32(0x0f172a)'
			} else {
				'u32(0xffffff)'
			}, prefix + '_font_size', 'f64(14)', true)}, ${config_member}: ${data}}) or {panic(err)}'
		}
		'CarouselSlide' { constructor = 'ui2.view(${id}, ${frame}, ${box}, ${children})' }
		'Carousel' {
			constructor = 'ui2.carousel(ui2.CarouselConfig{id: ${id}, frame: ${frame}, box: ${box}, index: ${vml_prop(properties, 'index', '0')}, direction: ${vml_prop(properties, 'direction', 'ui2.CarouselDirection.right')}, loop: ${vml_prop(properties, 'loop', 'false')}, min_move: ${vml_prop(properties, 'min_move', 'f64(0.2)')}, ignore_perpendicular_swipes: ${vml_prop(properties, 'ignore_perpendicular_swipes', 'false')}, slides: ${children}}) or {panic(err)}'
		}
		'Screen', 'ManagedScreen', 'ScreenView' {
			constructor = 'ui2.view(${id}, ${frame}, ${box}, ${children})'
			metadata = 'screen: ui2.ManagedScreen{name: ${vml_prop(properties, 'name', id)}}'
		}
		'ScreenManager' {
			constructor = 'ui2.screen_manager(ui2.ScreenManagerConfig{id: ${id}, frame: ${frame}, box: ${box}, current: ${vml_prop(properties, 'current', "''")}, screens: ${children}.map(ui2.ManagedScreen{...(it.compiled_metadata.screen or {panic("ScreenManager requires Screen children")}), content: it})}) or {panic(err)}'
		}
		'Popup', 'ModalView' {
			popup := node.tag == 'Popup'
			config := if popup { 'PopupConfig' } else { 'ModalViewConfig' }
			method := if popup { 'popup' } else { 'modal_view' }
			body := 'ui2.view((if ${id}.len > 0 { ${id} + "__body" } else { "" }), ui2.rect(0,0,${frame}.width,${frame}.height), ui2.BoxStyle{transparent:true}, ${children})'
			more := if popup {
				'surface_box: ${box}, title: ${vml_prop(properties, 'title', "''")}, title_height: ${vml_prop(properties, 'title_height', 'f64(48)')}, title_style: ui2.TextStyle{color:${vml_prop(properties, 'title_color', 'u32(0x0f172a)')},size:${vml_prop(properties, 'title_font_size', 'f64(18)')},bold:${vml_prop(properties, 'title_bold', 'true')},align:.center}, separator_height:${vml_prop(properties, 'separator_height', 'f64(1)')},separator_box:ui2.BoxStyle{bg:${vml_prop(properties, 'separator_color', 'u32(0xe2e8f0)')}},'
			} else {
				'content_box: ${box},'
			}
			constructor = 'ui2.${method}(ui2.${config}{id:${id},frame:${frame},open:${vml_prop(properties, 'open', 'false')},auto_dismiss:${vml_prop(properties, 'auto_dismiss', 'true')},on_dismiss:${c.event_callback(node, 'on_dismiss', scope)},content_width:${vml_prop(properties, 'content_width', 'f64(-1)')},content_height:${vml_prop(properties, 'content_height', 'f64(-1)')},size_hint_x:${vml_prop(properties, 'size_hint_x', 'f64(0.8)')},size_hint_y:${vml_prop(properties, 'size_hint_y', 'f64(0.8)')},overlay_box:ui2.BoxStyle{bg:${vml_prop(properties, 'overlay_background', 'u32(0x475569)')}},${more}content:${body}}) or {panic(err)}'
		}
		'TreeNode' {
			constructor = 'ui2.view((if ${id}.len > 0 { ${id} + "__record" } else { "" }), ${frame}, ${box}, ${children})'
			metadata = 'tree: ui2.TreeViewNode{id:${id},text:${vml_prop(properties, 'text', vml_prop(properties, 'title', "''"))},on_event:${c.event_callback(node, 'on_select', scope)},on_toggle:${c.event_callback(node, 'on_toggle', scope)},expanded:${vml_prop(properties, 'expanded', 'false')},selected:${vml_prop(properties, 'selected', 'false')},enabled:${vml_prop(properties, 'enabled', 'true')},children:${children}.map(it.compiled_metadata.tree or {panic("TreeNode requires TreeNode children")})}'
		}
		'TreeView' {
			constructor = 'ui2.tree_view(ui2.TreeViewConfig{id:${id},frame:${frame},box:${box},row_height:${vml_prop(properties, 'row_height', 'f64(36)')},spacing:${vml_prop(properties, 'spacing', 'f64(2)')},indent:${vml_prop(properties, 'indent', 'f64(24)')},disclosure_width:${vml_prop(properties, 'disclosure_width', 'f64(28)')},row_box:${vml_widget_box(properties, 'row_background', 'u32(0xffffff)', 'row_corner_radius', 'f64(4)')},selected_row_box:${vml_widget_box(properties, 'selected_background', 'u32(0xdbeafe)', 'row_corner_radius', 'f64(4)')},disclosure_box:${vml_widget_box(properties, 'disclosure_background', 'u32(0xffffff)', 'row_corner_radius', 'f64(4)')},text_style:ui2.TextStyle{color:${vml_prop(properties, 'color', 'u32(0x334155)')},size:${vml_prop(properties, 'font_size', 'f64(14)')}},selected_text_style:ui2.TextStyle{color:${vml_prop(properties, 'selected_color', 'u32(0x1d4ed8)')},size:${vml_prop(properties, 'font_size', 'f64(14)')},bold:true},disclosure_text_style:${vml_widget_text(properties, 'disclosure_color', 'u32(0x64748b)', 'font_size', 'f64(14)', false)},nodes:${children}.map(it.compiled_metadata.tree or {panic("TreeView requires TreeNode children")})}) or {panic(err)}'
		}
		'ToggleButton' {
			constructor = 'ui2.toggle_button(ui2.ToggleButtonConfig{id:${id},frame:${frame},on_event:${action},title:${vml_prop(properties, 'text', "''")},pressed:${vml_value(properties, 'pressed', 'bind.pressed', 'false')},group:${vml_prop(properties, 'group', "''")},allow_no_selection:${vml_prop(properties, 'allow_no_selection', 'true')},box:${box},down_box:${vml_widget_box(properties, 'down_background', 'u32(0x2563eb)', 'down_corner_radius', vml_prop(properties, 'corner_radius', 'f64(6)'))},text_style:${c.text_style(properties)},down_text_style:ui2.TextStyle{...${c.text_style(properties)},color:${vml_prop(properties, 'down_color', 'u32(0xffffff)')}},native_style:${vml_prop(properties, 'native', 'false')}})'
		}
		else { return false }
	}
	c.writeln('\t${temporary} := ${constructor}')
	c.writeln('\t${output} := ui2.Element{...${temporary}, key: ${key}')
	if metadata.len > 0 { c.writeln('\tcompiled_metadata: &ui2.CompiledVmlMetadata{${metadata}}') }
	c.write_common_fields(node, suffix, properties, scope, '${temporary}.accessibility_role', '${temporary}.accessibility_label', '${temporary}.accessibility_value')
	c.writeln('\t}')
	return true
}

// Composite controls allocate their authored content within a surface/header
// region. Children receive that logical size rather than the full outer frame.
fn vml_widget_child_input(tag string, frame string, properties map[string]string, child_count int) ?string {
	mut geometry := ''
	match tag {
		'Popup', 'ModalView' {
			config := if tag == 'Popup' { 'PopupConfig' } else { 'ModalViewConfig' }
			method := if tag == 'Popup' { 'popup_geometry' } else { 'modal_view_geometry' }
			member := if tag == 'Popup' { 'body' } else { 'content' }
			more := if tag == 'Popup' {
				'title_height: ${vml_prop(properties, 'title_height', 'f64(48)')}, separator_height: ${vml_prop(properties, 'separator_height', 'f64(1)')},'
			} else {
				''
			}
			geometry = '(ui2.${method}(ui2.${config}{frame:${frame},content_width:${vml_prop(properties, 'content_width', 'f64(-1)')},content_height:${vml_prop(properties, 'content_height', 'f64(-1)')},size_hint_x:${vml_prop(properties, 'size_hint_x', 'f64(0.8)')},size_hint_y:${vml_prop(properties, 'size_hint_y', 'f64(0.8)')},${more}}) or {panic(err)}).${member}'
		}
		'TabbedPanel' {
			geometry = '(ui2.tabbed_panel_geometry(ui2.TabbedPanelConfig{frame:${frame},tab_position:${vml_prop(properties, 'tab_pos', 'ui2.TabPosition.top_left')},tab_height:${vml_prop(properties, 'tab_height', 'f64(40)')},tab_width:${vml_prop(properties, 'tab_width', 'f64(100)')}}) or {panic(err)}).content'
		}
		'Accordion' {
			geometry = '(ui2.accordion_geometry(ui2.AccordionConfig{frame:${frame},current:${vml_prop(properties, 'current', '0')},orientation:${vml_prop(properties, 'orientation', 'ui2.LayoutOrientation.horizontal')},min_space:${vml_prop(properties, 'min_space', 'f64(44)')},items:[]ui2.AccordionItem{len:${child_count}}}) or {panic(err)}).content'
		}
		else { return none }
	}
	return 'ui2.rect(f64(0),f64(0),${geometry}.width,${geometry}.height)'
}
