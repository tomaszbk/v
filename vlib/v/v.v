module main

import os

import v.driver

$if gcboehm ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

$if gcboehm_full ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

$if gcboehm_incr ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

$if gcboehm_opt ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

$if gcboehm_leak ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

$if vgc ? {
	$compile_error('V must be built without a garbage collector; use `-gc none` or `-prealloc`')
}

fn main() {
	$if prealloc {
		// The compiler's arenas live until the process ends; the OS reclaims them
		// with less work than unmapping each block in the exit handler.
		unsafe { prealloc_keep_memory_at_exit() }
	}
	driver.run(os.args[1..])
}
