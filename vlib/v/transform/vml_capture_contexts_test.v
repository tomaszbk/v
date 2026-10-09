module transform

import v.flat
import v.types
import v.token

fn test_specialized_builder_borrows_locked_main_model_type() {
	mut a := flat.FlatAst.new()
	id := a.add_val(.ident, 'model')
	mut tc := types.TypeChecker.new(&a)
	mut transformer := new_transformer(mut a, &tc, map[string]bool{})
	assert transformer.resolved_receiver_arg_compatible(id, 'main.App', '&App')
	assert transformer.resolved_receiver_arg_compatible(id, '&main.App', 'App')
	assert !transformer.resolved_receiver_arg_compatible(id, 'other.App', '&App')
	assert !transformer.resolved_receiver_arg_compatible(id, 'main.App', '&other.App')
	assert !transformer.resolved_receiver_arg_compatible(id, 'main.App', '&&App')
	assert !transformer.resolved_receiver_arg_compatible(id, 'fn (mut App)', 'fn (App)')
}

fn test_scoped_batch_publishes_capture_context_through_worker() {
	$if !v3_no_parallel ? {
		mut a := flat.FlatAst.new()
		mut tc := types.TypeChecker.new(&a)
		mut master := new_transformer(mut a, &tc, map[string]bool{})
		worker_tc := tc.fork_for_parallel_transform(&a)
		mut worker := master.fork_worker(&a, worker_tc)
		peer_tc := tc.fork_for_parallel_transform(&a)
		peer := master.fork_worker(&a, peer_tc)
		batch_tc := worker_tc.fork_for_parallel_transform(&a)
		mut batch := worker.fork_scoped_batch_worker(&a, batch_tc)
		start := a.nodes.len
		batch.add_fn_literal_capture_context('__vml_capture_Ctx', 'main', ['value'], {
			'value': 'int'
		})
		assert '__vml_capture_Ctx' !in worker_tc.structs
		worker.absorb_scoped_batch(batch, unsafe { nil }, start)
		assert '__vml_capture_Ctx' !in master.structs
		assert '__vml_capture_Ctx' !in tc.structs
		assert '__vml_capture_Ctx' !in tc.struct_modules
		assert '__vml_capture_Ctx' !in tc.struct_files
		assert '__vml_capture_Ctx' !in peer.structs
		assert '__vml_capture_Ctx' !in peer_tc.structs
		assert worker.structs['__vml_capture_Ctx'].fields[0].name == 'value'
		assert worker_tc.structs['__vml_capture_Ctx'][0].name == 'value'
		assert '__vml_capture_Ctx' in worker.generated_capture_contexts
		master.merge_worker_used_fns(worker)
		assert tc.structs['__vml_capture_Ctx'][0].typ == types.Type(types.int_)
		assert master.structs['__vml_capture_Ctx'].fields[0].name == 'value'
	}
}

fn test_parallel_vml_work_items_have_distinct_capture_names() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	mut master := new_transformer(mut a, &tc, map[string]bool{})
	first_tc := tc.fork_for_parallel_transform(&a)
	mut first := master.fork_worker(&a, first_tc)
	second_tc := tc.fork_for_parallel_transform(&a)
	mut second := master.fork_worker(&a, second_tc)
	first.literal_free_fn_body = true
	first.item_range_hi = 100
	second.literal_free_fn_body = true
	second.item_range_hi = 200
	first_name := first.new_fn_literal_name()
	second_name := second.new_fn_literal_name()
	assert first_name == '__anon_fn_work_100_0'
	assert second_name == '__anon_fn_work_200_0'
	assert first_name != second_name
	first.add_fn_literal_capture_context('${first_name}_Ctx', 'main', ['app'], {
		'app': '&main.App'
	})
	second.add_fn_literal_capture_context('${second_name}_Ctx', 'main', ['row'], {
		'row': 'int'
	})
	master.merge_worker_used_fns(first)
	master.merge_worker_used_fns(second)
	assert master.structs['${first_name}_Ctx'].fields[0].name == 'app'
	assert master.structs['${second_name}_Ctx'].fields[0].name == 'row'
}

fn test_specialized_compile_error_is_a_located_check_diagnostic() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	tc.check_concrete_generic_bodies = true
	mut transformer := new_transformer(mut a, &tc, map[string]bool{})
	call := transformer.make_call('__v_compile_error', [transformer.make_string_literal('schema error')])
	position := token.new_pos(7, 0)
	node := a.node(call)
	a.nodes[int(call)] = flat.Node{ ...node, pos: position }
	transformer.record_selected_compile_error_call(call, a.node(call))
	assert tc.errors.len == 1
	assert tc.errors[0].msg == 'schema error'
	assert tc.errors[0].pos == position
	assert transformer.monomorph_errors.len == 0
}
