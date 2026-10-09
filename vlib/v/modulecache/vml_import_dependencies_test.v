module modulecache

import os

fn test_cached_vml_signature_tracks_transitive_imports_and_resolution_candidates() {
	root := os.join_path(os.vtmp_dir(), 'vml_import_dependencies_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	source := os.join_path(root, 'main.v')
	os.write_file(source, "fn build() { _ = \$vml('main.vml') }")!
	os.write_file(os.join_path(root, 'main.vml'), 'import Card\nView { Card {} }')!
	os.write_file(os.join_path(root, 'card.vml'), 'module Card\nimport CardCaption\nView { CardCaption {} }')!
	caption := os.join_path(root, 'card_caption.vml')
	os.write_file(caption, 'module CardCaption\nLabel { text: "first" }')!
	manager := Manager{ dir: os.join_path(root, 'cache'), enabled: true, salt: 'vml-imports' }
	first := cached_source_signature(manager.dir, 'vml', [source])
	assert first.len > 0
	manager.write_header('main', [source], '// first')!
	assert manager.valid_header('main', [source]) != none
	assert cached_source_signature(manager.dir, 'vml', [source]) == first
	os.write_file(caption, 'module CardCaption\nLabel { text: "changed" }')!
	second := cached_source_signature(manager.dir, 'vml', [source])
	assert second != first, 'transitive VML content must invalidate a warm signature'
	assert manager.valid_header('main', [source]) == none
	manager.write_header('main', [source], '// changed')!
	assert manager.valid_header('main', [source]) != none
	// The exact-case candidate takes precedence over the snake-case file.
	shadow := os.join_path(root, 'CardCaption.vml')
	os.write_file(shadow, 'module CardCaption\nLabel { text: "shadow" }')!
	third := cached_source_signature(manager.dir, 'vml', [source])
	assert third != second
	assert manager.valid_header('main', [source]) == none
	os.rm(shadow)!
	assert cached_source_signature(manager.dir, 'vml', [source]) == second
	os.rm(caption)!
	assert manager.valid_header('main', [source]) == none
	assert !source_signature_details([source], '', '').cacheable
}
