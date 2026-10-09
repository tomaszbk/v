module parser

fn validate_compiled_vml_menu(node &VmlNode) ! {
	allowed := match node.tag {
		'MenuBar', 'MenuSeparator' { []string{} }
		'Menu' { ['title', 'text'] }
		'MenuItem' {
			['id', 'title', 'text', 'on_tap', 'shortcut', 'checked', 'enabled', 'separator']
		}
		else {
			return error('${node.source}:${node.line}:${node.column}: unexpected `${node.tag}` in menu')
		}
	}
	for property in node.properties {
		if property.name !in allowed || property.declared_type.len > 0 {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported `${property.name}` on ${node.tag}')
		}
	}
	if node.tag == 'MenuSeparator' && node.children.len > 0 {
		return error('${node.source}:${node.line}:${node.column}: MenuSeparator cannot have children')
	}
	for child in node.children {
		if node.tag == 'MenuBar' && child.tag != 'Menu' {
			return error('${child.source}:${child.line}:${child.column}: MenuBar expects Menu children')
		}
		validate_compiled_vml_menu(child)!
	}
}

fn (mut c VmlCompiler) compile_menus(root &VmlNode) string {
	c.location = VmlLocation{ path: root.source, line: root.line, column: root.column }
	capture := if c.uses_app { '[mut app] ' } else { '' }
	c.writeln('(fn ${capture}() []ui2.Menu {')
	scope := VmlScope{}
	mut menus := []string{}
	nodes := if root.tag == 'Menu' { [root] } else { root.children }
	for index, node in nodes {
		menus << c.application_menu(node, '${index}', scope)
	}
	c.writeln('\tvml_menus := ${vml_array_literal('ui2.Menu', menus)}')
	c.writeln('\tui2.validate_menus(vml_menus) or { panic(' + vml_quote('${root.source}:${root.line}:${root.column}: ') + ' + err.msg()) }')
	c.writeln('\treturn vml_menus')
	c.writeln('}())')
	c.write_list_guards()
	return c.out.str()
}

fn (c &VmlCompiler) menu_property(node &VmlNode, name string, fallback string, use VmlExprUse) string {
	if property := vml_find_property(node, name) { return c.expr(property.expr, VmlScope{}, use) }
	return fallback
}

fn (mut c VmlCompiler) application_menu(node &VmlNode, path string, scope VmlScope) string {
	mut local := vml_clone_scope(scope)
	if node.imported {
		local.special['__import_parent'] = local.special['__import'] or { '' }
		local.special['__import'] = 'menu_${path}'
	}
	c.write_action_type_checks(node, 'menu_${path}', local)
	items := c.application_menu_items(node, path, local)
	title := c.menu_property(node, 'title', c.menu_property(node, 'text', "''", .raw), .raw)
	c.location = VmlLocation{ path: node.source, line: node.line, column: node.column }
	name := 'vml_menu_${path}'
	c.writeln('\t${name} := ui2.Menu{title: ${title}, items: ${items}}')
	return name
}

fn (mut c VmlCompiler) application_menu_items(node &VmlNode, path string, scope VmlScope) string {
	mut items := []string{}
	for index, child in node.children {
		child_path := '${path}_${index}'
		c.location = VmlLocation{ path: child.source, line: child.line, column: child.column }
		c.write_action_type_checks(child, 'menu_${child_path}', scope)
		if child.tag == 'MenuSeparator' {
			items << 'ui2.menu_separator()'
			continue
		}
		mut local := vml_clone_scope(scope)
		if child.imported {
			local.special['__import_parent'] = local.special['__import'] or { '' }
			local.special['__import'] = 'menu_${child_path}'
		}
		nested := c.application_menu_items(child, child_path, local)
		c.location = VmlLocation{ path: child.source, line: child.line, column: child.column }
		title := c.menu_property(child, 'title', c.menu_property(child, 'text', "''", .raw), .raw)
		fields := if child.tag == 'Menu' {
			''
		} else {
			'id: ${c.control_id(child, child_path, local)}, on_select: ${c.event_callback(child, 'on_tap', local)}, shortcut: ${c.menu_property(child, 'shortcut', "''", .raw)}, checked: ${c.menu_property(child, 'checked', 'false', .raw)}, enabled: ${c.menu_property(child, 'enabled', 'true', .raw)}, separator: ${c.menu_property(child, 'separator', 'false', .raw)}, '
		}
		name := 'vml_menu_item_${child_path}'
		c.writeln('\t${name} := ui2.MenuItem{${fields}title: ${title}, items: ${nested}}')
		items << name
	}
	return vml_array_literal('ui2.MenuItem', items)
}
