module parser

// Parser workers merge local ASTs with shifted node ids. `typeof(expr)` type
// annotations hold expression links and relocate with the ordinary child links.
fn shift_inferred_type(typ string, shift int) string {
	mut result := typ
	mut offset := 0
	marker := 'typeof(__expr_'
	for offset < result.len {
		start := result[offset..].index(marker) or { break } + offset
		end := result[start..].index(')') or { break } + start
		value := result[start + marker.len..end].int()
		replacement := marker + (value + shift).str() + ')'
		result = result[..start] + replacement + result[end + 1..]
		offset = start + replacement.len
	}
	return result
}
