module transform

import v.flat
import v.types

fn vml_inference_test_node(mut a flat.FlatAst, kind flat.NodeKind, children []flat.NodeId) flat.NodeId {
	start := a.children.len
	for child in children { a.add_child(child) }
	return a.add_node(flat.Node{ kind: kind, children_start: start, children_count: flat.child_count(children.len) })
}

fn test_vml_inferred_witness_uses_current_lexical_binding_for_each_specialization() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	mut t := new_transformer(mut a, &tc, map[string]bool{})
	value := a.add_node(flat.Node{ kind: .ident, value: 'value' })
	annotation := 'ui2.Signal[typeof(__vml_expr_${int(value)})]'
	t.scope_parallel_workers = true
	t.scoped_base_nodes = a.nodes.len
	for payload in ['int', 'f64', '[]ui2.RowData'] {
		t.set_var_type('value', payload)
		assert t.resolve_vml_inferred_type_text(annotation) == 'ui2.Signal[${payload}]'
		assert a.node(value).typ == payload
		assert value in t.scoped_owned_base_log
	}
	// Resolving a transform-owned annotation must not publish a scratch-arena
	// Type into the original parser expression's semantic cache.
	if _ := tc.expr_type(value) {
		assert false, 'source witness acquired a synthesized checker type'
	}
}

fn test_vml_app_address_capture_keeps_pointer_storage_and_ordinary_captures_keep_values() {
	for borrowed in [false, true] {
		mut a := flat.FlatAst.new()
		mut tc := types.TypeChecker.new(&a)
		mut t := new_transformer(mut a, &tc, map[string]bool{})
		t.cur_module = 'main'
		t.set_var_type('app', 'Model')
		t.structs['Model'] = StructInfo{ name: 'Model', module: 'main' }
		capture := a.add_node(flat.Node{
			kind:   .ident
			value:  'app'
			is_mut: true
			op:     if borrowed {
				.amp
			} else {
				.none
			}
		})
		start := a.children.len
		a.add_child(capture)
		literal := a.add_node(flat.Node{ kind: .fn_literal, typ: 'void', children_start: start, children_count: 1 })
		_ = t.lift_fn_literal(literal, a.node(literal))
		context := t.structs[t.generated_capture_contexts[0]]
		assert context.fields.len == 1
		assert context.fields[0].typ == if borrowed { '&Model' } else { 'Model' }
	}
}

fn test_vml_immediately_called_builder_still_promotes_its_borrowed_application() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	mut t := new_transformer(mut a, &tc, map[string]bool{})
	capture := a.add_node(flat.Node{ kind: .ident, value: 'app', is_mut: true, op: .amp })
	literal := vml_inference_test_node(mut a, .fn_literal, [capture])
	call := vml_inference_test_node(mut a, .call, [literal])
	t.collect_mut_capture_sources(call)
	assert t.escaping_amp_sources['app']
}
