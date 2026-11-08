module pref

import os


// The V driver reads the same two variables when it evaluates the
// `// vtest build:` constraints of a file, so a mismatch between what a test
// runner writes here and what the driver reads there silently drops a file.
fn test_build_facts_and_defines_round_trip_through_the_environment() {
	previous_facts := os.getenv_opt('VBUILD_FACTS')
	previous_defines := os.getenv_opt('VBUILD_DEFINES')
	defer {
		if value := previous_facts {
			os.setenv('VBUILD_FACTS', value, true)
		} else {
			os.unsetenv('VBUILD_FACTS')
		}
		if value := previous_defines {
			os.setenv('VBUILD_DEFINES', value, true)
		} else {
			os.unsetenv('VBUILD_DEFINES')
		}
	}
	set_build_flags_and_defines(['linux', 'gcc'], ['prod', 'trace_parser'])
	facts, defines := get_build_facts_and_defines()
	assert facts == ['linux', 'gcc']
	assert defines == ['prod', 'trace_parser']
	set_build_flags_and_defines([], [])
	empty_facts, empty_defines := get_build_facts_and_defines()
	assert empty_facts == []
	assert empty_defines == []
	// An environment variable that was never set reads back as no facts either.
	os.unsetenv('VBUILD_FACTS')
	os.unsetenv('VBUILD_DEFINES')
	missing_facts, missing_defines := get_build_facts_and_defines()
	assert missing_facts == []
	assert missing_defines == []
}

// The host target is what the compiler is running on, so it has to agree with the
// os and arch reported for it, and it must be a target the tables accept.
fn test_host_target_is_self_consistent() {
	target := host_target()
	assert target.os == normalized_os(target.os)
	assert target.arch == normalized_arch(target.arch)
	assert target.os == host_os_name()
	assert target.arch == host_arch()
	assert target_from(target.os, target.arch) or { panic(err) } == target
	assert target.abi in ['windows', 'darwin', 'android', 'emscripten', 'gnu']
	assert target.endian in ['little', 'big']
	assert target.pointer_bits in [32, 64]
	assert target.object_format in ['coff', 'macho', 'wasm', 'elf']
	// The default thread stack size is derived only from the pointer width.
	assert target.default_thread_stack_size() == if target.pointer_bits == 32 {
		2 * 1024 * 1024
	} else {
		8 * 1024 * 1024
	}
}
