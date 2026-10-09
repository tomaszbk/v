module transform

import v.flat
import v.types
import v.workers

struct VmlCaptureTask {
	worker &Transformer
	lane   int
}

fn vml_capture_batch_task(raw voidptr) voidptr {
	// The pool uses a type-erased argument; each lane owns its AST and helper.
	arg := unsafe { &VmlCaptureTask(raw) }
	mut worker := arg.worker
	for index in 0 .. 16 {
		batch_tc := worker.tc.fork_for_parallel_transform(worker.a)
		mut batch := worker.fork_scoped_batch_worker(worker.a, batch_tc)
		start := worker.a.nodes.len
		batch.add_fn_literal_capture_context('__vml_lane_${arg.lane}_${index}_Ctx', 'main', ['value'], {
			'value': 'int'
		})
		worker.absorb_scoped_batch(batch, unsafe { nil }, start)
	}
	return unsafe { nil }
}

fn test_parallel_scoped_capture_publication_stays_private_until_master_merge() {
	mut a := flat.FlatAst.new()
	mut tc := types.TypeChecker.new(&a)
	mut master := new_transformer(mut a, &tc, map[string]bool{})
	mut args := []&VmlCaptureTask{}
	mut tasks := []workers.Task{}
	for lane in 0 .. 2 {
		mut lane_ast := flat.FlatAst.new()
		worker_tc := tc.fork_for_parallel_transform(&lane_ast)
		worker := master.fork_worker(&lane_ast, worker_tc)
		args << &VmlCaptureTask{ worker: worker, lane: lane }
		tasks << workers.Task{ run: vml_capture_batch_task, arg: voidptr(args.last()) }
	}
	mut pool := workers.new(2)
	defer { pool.close() }
	assert pool.size() == 2
	assert pool.run(tasks)
	assert pool.stats().async_tasks == 2
	assert pool.stats().launch_failures == 0
	for arg in args {
		for index in 0 .. 16 {
			name := '__vml_lane_${arg.lane}_${index}_Ctx'
			other := args[1 - arg.lane].worker
			assert name in arg.worker.structs
			assert name in arg.worker.tc.structs
			assert name !in other.structs
			assert name !in other.tc.structs
			assert name !in other.tc.struct_modules
			assert name !in other.tc.struct_files
			assert name !in master.structs
			assert name !in tc.structs
		}
	}
	for arg in args { master.merge_worker_used_fns(arg.worker) }
	for lane in 0 .. 2 {
		for index in 0 .. 16 {
			name := '__vml_lane_${lane}_${index}_Ctx'
			assert master.structs[name].fields[0].name == 'value'
			assert tc.structs[name][0].typ == types.Type(types.int_)
			assert tc.struct_modules[name] == 'main'
		}
	}
}
