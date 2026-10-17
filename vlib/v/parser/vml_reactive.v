module parser

import v.pref
import v.scanner
import v.token
import vml

// vml_property_is_reactive reports whether a property reads a source that can
// change after the build: the app, theme tokens, scope specials or element
// geometry. Other properties are static fields of the props literal.
fn vml_property_is_reactive(property vml.Property, scope VmlScope) bool {
	if property.expr.kind == .literal { return false }
	if vml_style_uses_theme(property.expr) { return true }
	if vml.expr_uses_path(property.expr, 'app') { return true }
	for member, _ in scope.special {
		if !member.starts_with('__') && vml.expr_uses_path(property.expr, member) { return true }
	}
	for id, _ in scope.ids {
		if vml.expr_uses_path(property.expr, id) { return true }
	}
	return false
}

// scope_captures lists every capture a closure over `scope` may need;
// `finish_scope_captures` keeps the ones its body uses.
fn (c &VmlCompiler) scope_captures(scope VmlScope) []string {
	mut captures := []string{}
	if c.uses_app { captures << 'mut app' }
	for name, value in scope.special {
		if name.starts_with('__signal_') {
			if ('mut ' + value) !in captures { captures << 'mut ' + value }
		} else if !name.starts_with('__') && value.starts_with('vml_') && !value.contains('.') && value !in captures {
			captures << value
		}
	}
	for _, node in scope.ids {
		if node !in captures { captures << node }
	}
	captures << c.callback_captures.filter(it !in captures)
	return captures
}

// Lowered identifiers reflect the actual lexical scope, including nested item
// aliases and callbacks. Scan the completed body so quoted ids and comments do
// not turn unused outer bindings into captures.
fn (mut c VmlCompiler) finish_scope_captures(capture_start int, body_start int, candidates []string) {
	body := c.out.spart(body_start, c.out.len - body_start)
	captures := vml_used_captures(body, candidates)
	// Replacing only the capture list keeps the generated source-line mapping.
	tail := c.out.cut_to(capture_start)
	c.out.write_string('[' + captures.join(', ') + ']' + tail[2..])
}

fn vml_used_captures(body string, candidates []string) []string {
	mut files := token.FileSet.new()
	mut file := files.add_file('<vml-callback>', body.len)
	file.index_lines(body)
	mut lexer := scanner.new_scanner(&pref.Preferences{}, .normal)
	lexer.init(file, body)
	mut names := map[string]bool{}
	mut previous := token.Token.eof
	for {
		kind := lexer.scan()
		if kind == .eof { break }
		if kind == .name && previous != .dot { names[lexer.lit] = true }
		previous = kind
	}
	mut captures := []string{}
	for candidate in candidates {
		name := candidate.trim_string_left('mut ')
		if name in names && candidate !in captures { captures << candidate }
	}
	return captures
}
