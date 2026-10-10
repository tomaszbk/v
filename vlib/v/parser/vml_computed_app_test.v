module parser

fn test_component_computed_app_read_tracks_the_app_revision_inside_the_memo() {
	root := parse_vml_source('component Caption() { computed caption := app.name Label(text: caption) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	memo := generated.split_into_lines().filter(it.contains('.computed[') && it.contains("('caption',"))[0]
	assert memo.contains('.watch_app()!;'), memo
	assert memo.contains('mut vml_component_0'), memo
	assert memo.contains('return app.name'), memo
}

fn test_component_computed_local_state_has_no_app_revision_dependency() {
	root := parse_vml_source('component Counter() { state count := 0 computed doubled := count * 2 Label(text: doubled) }')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	memo := generated.split_into_lines().filter(it.contains('.computed[') && it.contains("('doubled',"))[0]
	assert !memo.contains('watch_app'), memo
	assert !memo.contains('mut app'), memo
	assert !memo.contains('mut vml_component_0'), memo
	assert memo.contains('_count.get()'), memo
}
