module parser

fn test_motion_and_opacity_lower_to_typed_retained_element_properties() {
	root := parse_vml_source('View(id: "panel", motion: app.motion, opacity: app.alpha, hidden: app.closed, translate_x: app.offset)')!
	mut compiler := VmlCompiler{ uses_app: true }
	generated := compiler.compile(root)
	assert generated.contains('ui2.MotionConfig{...app.motion}'), generated
	assert generated.contains('ui2.LayoutSize{width: app.alpha}.width'), generated
	assert generated.contains(".effect('motion'"), generated
	assert generated.contains(".effect('opacity'"), generated
	assert generated.contains('motion: vml_property_0_motion_memo.get()'), generated
	assert generated.contains('opacity: vml_property_0_opacity_memo.get()'), generated
	assert generated.contains(".effect('hidden'"), generated
	assert generated.contains(".effect('translate_x'"), generated
}

fn test_opacity_literal_bounds_and_numeric_type_are_diagnosed_in_vml() {
	for source in ['View(opacity: 0)', 'View(opacity: 0.5)', 'View(opacity: 1)'] {
		parse_vml_source(source)!
	}
	for source in ['View(opacity: -0.1)', 'View(opacity: 1.1)'] {
		parse_vml_source(source) or {
			assert err.msg().contains('opacity must be finite and between zero and one'), err.msg()
			continue
		}
		assert false, source
	}
	for source in ['View(opacity: "0.5")', 'View(opacity: true)'] {
		parse_vml_source(source) or {
			assert err.msg().contains('`opacity` requires a number'), err.msg()
			continue
		}
		assert false, source
	}
}

fn test_motion_and_opacity_require_the_custom_vml_profile() {
	for source in ['View(motion: app.motion)', 'View(opacity: app.alpha)'] {
		root := parse_vml_source(source)!
		validate_vml_native_visual(root) or {
			assert err.msg().contains('requires the custom renderer'), err.msg()
			continue
		}
		assert false, source
	}
}
