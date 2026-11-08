module main

import os

// v3_exact_output_fixture_path returns the expected-output file of a test fixture in `args`.
fn v3_exact_output_fixture_path(args []string) string {
	for arg in args {
		if arg.len == 0 || arg.starts_with('-') {
			continue
		}
		if os.is_dir(arg) && os.is_file(arg + '.out') {
			return arg + '.out'
		}
		ext := os.file_ext(arg)
		if ext !in ['.v', '.vv', '.vsh'] || arg.len <= ext.len {
			continue
		}
		base := arg[..arg.len - ext.len]
		for suffix in ['.out', '.run.out', '.js.out'] {
			if os.is_file(base + suffix) {
				return base + suffix
			}
		}
	}
	return ''
}

fn v3_exact_output_fixture_args(args []string) bool {
	return v3_exact_output_fixture_path(args) != ''
}
