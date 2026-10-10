// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
module main

import os

fn test_key_errors_identify_the_authored_vml_location_on_mount_and_update() ! {
	dir := os.join_path(os.vtmp_dir(), 'vml_key_locations_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	bin := os.join_path(dir, 'keys')
	compiled := os.exec([@VEXE, '-b', 'c', '-cc', 'clang', '-W', '-d', 'ui2_headless', '-o', bin, @DIR])
	assert compiled.exit_code == 0, compiled.output
	valid := os.exec([bin])
	assert valid.exit_code == 0, valid.output
	assert valid.output.contains('Valid keyed VML reorder preserves nodes'), valid.output
	for entry in [
		['--duplicate-key', 'rows.vml:2:5:', 'duplicate compiled VML list key'],
		['--duplicate-update', 'rows.vml:2:5:', 'duplicate compiled VML list key'],
		['--empty-key', 'rows.vml:2:5:', 'compiled VML list key cannot be empty'],
		['--duplicate-sibling', 'siblings.vml:1:1:', 'duplicate sibling key'],
	] {
		result := os.exec([bin, entry[0]])
		assert result.exit_code != 0, result.output
		assert result.output.contains(entry[1]), result.output
		assert result.output.contains(entry[2]), result.output
	}
}
