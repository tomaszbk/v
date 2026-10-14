module parser

fn vml_builder_property_type(node &VmlNode, property VmlProperty) string {
	if property.name == 'style' { return 'ui2.StylePatch' }
	if vml_visual_integer_property(property) { return 'int' }
	return match vml_property_use(property) {
		.number { 'f64' }
		.bool_ { 'bool' }
		.color { 'u32' }
		.raw {
			match vml_visual_base_property(property.name) {
				'overlay' { 'ui2.OverlayConfig' }
				'point' { '?ui2.OverlayPoint' }
				'placement' { 'ui2.OverlayPlacement' }
				'backdrop' { 'ui2.BoxStyle' }
				'scroll_mode' { 'ui2.ScrollMode' }
				'align' { 'ui2.Align' }
				'valign' { 'ui2.VAlign' }
				'align_items', 'align_self' { 'ui2.LayoutAlignment' }
				'justify' { 'ui2.FlexJustify' }
				'border_pattern' { 'ui2.BorderPattern' }
				'orientation' {
					if node.tag == 'Grid' {
						'ui2.GridOrientation'
					} else if node.tag == 'Slider' {
						'ui2.Orientation'
					} else {
						'ui2.LayoutOrientation'
					}
				}
				else { 'string' }
			}
		}
		else { 'string' }
	}
}

fn vml_builder_path(path string) string {
	return path.replace('_measure', '').replace('_width', '')
}
