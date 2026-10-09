module transform

import v.flat

// Generated closure type annotations retain their ordinary V expression.
// Resolve them while transform owns the same lexical locals as that expression,
// before recording a concrete callback signature or generic specialization.
fn (t &Transformer) resolve_vml_inferred_type_text(typ string) string {
	mut result := typ
	mut offset := 0
	marker := 'typeof(__vml_expr_'
	for offset < result.len {
		start := result[offset..].index(marker) or { break } + offset
		end := result[start..].index(')') or { break } + start + 1
		expression_id := flat.NodeId(result[start + marker.len..end - 1].int())
		if int(expression_id) < 0 || int(expression_id) >= t.a.nodes.len { break }
		value := t.resolve_expr_type(expression_id)
		if value.len == 0 || value == 'void' || value.contains(marker) { break }
		// Source witnesses precede transform's generated-node range. Their AST
		// text is promoted with the enclosing source scope, while a synthesized
		// checker Type would retain pointers into that disposable scope.
		mut writer := unsafe { &Transformer(voidptr(t)) }
		writer.set_node_typ(int(expression_id), value)
		result = result[..start] + value + result[end..]
		offset = start + value.len
	}
	return result
}
