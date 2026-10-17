module parser

import vml

// write_mutable_check rejects a write to an `app` field that is not public
// and mutable.
fn (mut c VmlCompiler) write_mutable_check(target string) {
	if !c.once('mutable:' + target) { return }
	field_name := target.all_after('app.')
	c.writeln('\t$for field in app.fields {')
	c.writeln('\t\t$if field.name == ' + vml_quote(field_name) + ' {')
	c.writeln('\t\t\t$if !field.is_pub || !field.is_mut { $compile_error(' + vml_quote('VML target `${target}` must be public and mutable') + ') }')
	c.writeln('\t\t}')
	c.writeln('\t}')
}

// vml_callback_captures lists the closure captures an expression needs: the
// app, the specials it reads (signals mutably, with their setters) and the
// nodes whose geometry it reads.
fn vml_callback_captures(expr &vml.Expr, scope VmlScope) []string {
	mut captures := []string{}
	if vml.expr_uses_path(expr, 'app') { captures << 'mut app' }
	for base, variable in scope.special {
		if base.starts_with('__') || !vml.expr_uses_path(expr, base) { continue }
		captured := if signal := scope.special['__signal_' + base] {
			'mut ' + signal
		} else {
			variable
		}
		if setter := scope.writable[base] {
			if !setter.contains('.') && setter.starts_with('vml_') && setter !in captures {
				captures << setter
			}
		}
		if (!captured.contains('.') && !captured.contains(' ')) || captured.starts_with('mut ') {
			if captured !in captures { captures << captured }
		}
	}
	for id, node in scope.ids {
		for field in ['x', 'y', 'width', 'height'] {
			if vml.expr_uses_path(expr, '${id}.${field}') && node !in captures {
				captures << node
			}
		}
	}
	return captures
}

// write_model_path_checks guards that `app.*` and `item.*` paths read public
// fields. The guards never run; V checks them for the actual model types.
fn (mut c VmlCompiler) write_model_path_checks(expr &vml.Expr, scope VmlScope) {
	if expr.kind == .path {
		parts := expr.value.split('.')
		if parts.len < 2 || parts[0] !in ['app', 'item'] { return }
		mut base := if parts[0] == 'app' { 'app' } else { scope.special['item'] or { return } }
		c.location = vml.Location{ path: expr.source, line: expr.line, column: expr.column }
		for field_name in parts[1..] {
			if field_name == 'len' { break }
			c.write_field_guard(base, field_name, expr.value)
			base += '.' + field_name
		}
	}
	if !isnil(expr.left) && expr.kind != .assignment { c.write_model_path_checks(expr.left, scope) }
	if !isnil(expr.right) { c.write_model_path_checks(expr.right, scope) }
	if !isnil(expr.third) { c.write_model_path_checks(expr.third, scope) }
	for argument in expr.args { c.write_model_path_checks(argument, scope) }
	for part in expr.parts {
		if !isnil(part.expr) { c.write_model_path_checks(part.expr, scope) }
	}
}

// write_app_action_checks guards that actions write public mutable `app`
// fields and call public `app` methods with their declared arity.
fn (mut c VmlCompiler) write_app_action_checks(expr &vml.Expr) {
	if expr.kind == .assignment && expr.left.value.starts_with('app.') {
		c.write_mutable_check(expr.left.value)
	}
	if expr.kind in [.call, .path] && expr.value.starts_with('app.') && expr.value.count('.') == 1 {
		method := expr.value.all_after('app.')
		arity := if expr.kind == .call { expr.args.len.str() } else { '' }
		if c.once('method:${method}:${arity}') {
			c.writeln('\t$for method in app.methods {')
			c.writeln('\t$if method.name == ' + vml_quote(method) + ' {')
			c.writeln('\t$if !method.is_pub { $compile_error(' + vml_quote('VML action method `${method}` must be public') + ') }')
			if expr.kind == .call {
				c.writeln('\t$if method.args.len != ${expr.args.len} { $compile_error(' + vml_quote('VML action `${method}` argument count does not match its declared signature') + ') }')
			}
			c.writeln('\t}\n}')
		}
	}
	if !isnil(expr.left) { c.write_app_action_checks(expr.left) }
	if !isnil(expr.right) { c.write_app_action_checks(expr.right) }
	for argument in expr.args { c.write_app_action_checks(argument) }
}

// compile_write assigns `value` to a writable target: a component state or
// bindable input setter, or a top-level `app` field.
fn (c &VmlCompiler) compile_write(target string, value string, scope VmlScope) string {
	if setter := scope.writable[target] { return '${setter}(${value}) or { panic(err) }' }
	if target.starts_with('app.') && target.count('.') == 1 { return '${target} = ${value}' }
	return '$compile_error(' + vml_quote('VML target `${target}` is read-only or unknown; use state or an explicit bind connection') + ')'
}

// compile_action lowers an action: an assignment, a block, a call of a
// component event (whose payload is checked against its declared types) or
// any other expression.
fn (c &VmlCompiler) compile_action(expr &vml.Expr, scope VmlScope) string {
	if expr.kind == .block { return expr.args.map(c.compile_action(it, scope)).join('\n') }
	if expr.kind == .assignment {
		return c.compile_write(expr.left.value, c.lower_expr(expr.right, scope), scope)
	}
	if expr.kind == .call {
		if parameters := scope.event_parameters[expr.value] {
			mut statements := []string{}
			mut payload_values := []string{}
			for index, parameter in parameters {
				if index >= expr.args.len { break }
				argument := 'vml_payload_' + index.str()
				statements << argument + ' := ' + c.event_payload_value(expr.args[index], parameter.typ, scope)
				statements << '$if ' + argument + ' !is ' + parameter.typ + ' { $compile_error(' + vml_quote('event `' + expr.value + '` payload `' + parameter.name + '` requires exact type ' + parameter.typ) + ') }'
				payload_values << argument
			}
			statements << (scope.special[expr.value] or { expr.value }) + '(' + payload_values.join(', ') + ')'
			// A block scopes the payload temporaries without a constant condition.
			return '{\n' + statements.join('\n') + '\n}'
		}
	}
	return c.lower_expr(expr, scope)
}

// Payload temporaries validate exact types without losing V's contextual enum
// literals or empty arrays. Expressions still execute once, inside the action.
fn (c &VmlCompiler) event_payload_value(expr &vml.Expr, expected string, scope VmlScope) string {
	if expr.kind == .path && expr.value.starts_with('.') { return expected + expr.value }
	if expr.kind == .conditional {
		return '(if ' + c.lower_expr(expr.left, scope) + ' { ' + c.event_payload_value(expr.right, expected, scope) + ' } else { ' + c.event_payload_value(expr.third, expected, scope) + ' })'
	}
	if expr.kind == .array && expected.starts_with('[]') {
		return vml_array_literal(expected[2..], expr.args.map(c.event_payload_value(it, expected[2..], scope)))
	}
	value := c.lower_expr(expr, scope)
	// A bare enum value takes the declared payload type.
	return if value.starts_with('.') { expected + value } else { value }
}
