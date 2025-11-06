package ts

// This file contains tiny wrappers/replacements of the C API.

import "core:strings"
import "core:time"
import "core:os"

// set the ranges of text that the parser should include when parsing.
//
// by default, the parser will always include entire documents. this function
// allows you to parse only a *portion* of a document but still return a syntax
// tree whose ranges match up with the document as a whole. you can also pass
// multiple disjoint ranges.
//
// the second parameter specifies the slice of ranges.
// the parser does *not* take ownership of these ranges; it copies the data,
// so it doesn't matter how these ranges are allocated.
//
// if `len(ranges)` is zero, then the entire document will be parsed. otherwise,
// the given ranges must be ordered from earliest to latest in the document,
// and they must not overlap. that is, the following must hold for all:
//
// `i < len(ranges) - 1`: `ranges[i].end_byte <= ranges[i + 1].start_byte`
//
// if this requirement is not satisfied, the operation will fail, the ranges
// will not be assigned, and this function will return `false`. on success,
// this function returns `true`
parser_set_included_ranges :: #force_inline proc(self: Parser, ranges: []Range) -> bool {
	return _parser_set_included_ranges(self, raw_data(ranges), u32(len(ranges)))
}

// Get the ranges of text that the parser will include when parsing.
parser_included_ranges :: #force_inline proc(self: Parser) -> []Range {
	length: u32 = ---
	multi := _parser_included_ranges(self, &length)
	return multi[:length]
}

// Use the parser to parse some source code stored in one contiguous buffer.
// The other two parameters are the same as in the [`parser_parse`] function
// above.
parser_parse_string :: #force_inline proc(self: Parser, string: string, old_tree: Tree = nil) -> Tree {
	return _parser_parse_string(self, old_tree, strings.unsafe_string_to_cstring(string), u32(len(string)))
}

// Use the parser to parse some source code stored in one contiguous buffer with
// a given encoding. The other parameters work the same as in the
// [`parser_parse_string`] method above. The `encoding` parameter indicates whether
// the text is encoded as UTF8 or UTF16.
parser_parse_string_encoding :: #force_inline proc(self: Parser, string: string, encoding: Input_Encoding, old_tree: Tree = nil) -> Tree {
	return _parser_parse_string_encoding(self, old_tree, strings.unsafe_string_to_cstring(string), u32(len(string)), encoding)
}

// Set the maximum duration that parsing should be allowed to take before halting.
//
// If parsing takes longer than this, it will halt early, returning NULL.
// See [`parser_parse`] for more information.
@(deprecated="use `parser_parse_with_options` and pass in a callback instead, this will be removed in 0.26.")
parser_set_timeout :: #force_inline proc(self: Parser, timeout: time.Duration) {
	_parser_set_timeout_micros(self, u64(timeout / time.Microsecond))
}

// Get the duration that parsing is allowed to take.
@(deprecated="use `parser_parse_with_options` and pass in a callback instead, this will be removed in 0.26.")
parser_timeout :: #force_inline proc(self: Parser) -> time.Duration {
	micros := _parser_timeout_micros(self)
	return time.Duration(time.Duration(micros) * time.Microsecond)
}

// Set the file descriptor to which the parser should write debugging graphs
// during parsing. The graphs are formatted in the DOT language. You may want
// to pipe these graphs directly to a `dot(1)` process in order to generate
// SVG output. You can turn off this logging by passing a negative `fd`.
parser_print_dot_graphs :: #force_inline proc(self: Parser, fd: os.Handle) {
	_parser_print_dot_graphs(self, i32(fd))
}

// Get the array of included ranges that was used to parse the syntax tree.
//
// NOTE: The returned slice must be freed by the caller.
tree_included_ranges :: #force_inline proc(self: Tree) -> []Range {
	length: u32 = ---
	multi := _tree_included_ranges(self, &length)
	return multi[:length]
}

// Compare an old edited syntax tree to a new syntax tree representing the same
// document, returning a slice of ranges whose syntactic structure has changed.
//
// For this to work correctly, the old syntax tree must have been edited such
// that its ranges match up to the new tree. Generally, you'll want to call
// this function right after calling one of the [`parser_parse`] functions.
// You need to pass the old tree that was passed to parse, as well as the new
// tree that was returned from that function.
//
// NOTE: The returned array is allocated using the provided `malloc` and the caller is responsible
// for freeing.
tree_get_changed_ranges :: #force_inline proc(old_tree: Tree, new_tree: Tree) -> []Range {
	length: u32 = ---
	multi := _tree_get_changed_ranges(old_tree, new_tree, &length)
	return multi[:length]
}

// Write a DOT graph describing the syntax tree to the given file.
tree_print_dot_graph :: #force_inline proc(self: Tree, fd: os.Handle) {
	_tree_print_dot_graph(self, i32(fd))
}

// Get the node's child with the given field name.
node_child_by_field_name :: #force_inline proc(self: Node, name: string) -> Node {
	return _node_child_by_field_name(self, strings.unsafe_string_to_cstring(name), u32(len(name)))
}

// Get the smallest node within this node that spans the given range of bytes or (row, column) positions.
node_descendant_for_range :: proc {
	node_descendant_for_byte_range,
	node_descendant_for_point_range,
}

// Get the smallest named node within this node that spans the given range of bytes or (row, column) positions.
node_named_descendant_for_range :: proc {
	node_named_descendant_for_byte_range,
	node_named_descendant_for_point_range,
}

// Move the cursor to the first child of its current node that extends beyond
// the given byte offset or point.
//
// This returns the index of the child node if one was found, and returns -1
// if no such child was found.
tree_cursor_goto_first_child_for :: proc {
	tree_cursor_goto_first_child_for_byte,
	tree_cursor_goto_first_child_for_point,
}

// Create a new query from a string containing one or more S-expression
// patterns. The query is associated with a particular language, and can
// only be run on syntax nodes parsed with that language.
//
// If all of the given patterns are valid, this returns a [`TSQuery`].
// If a pattern is invalid, this returns `NULL`, and provides two pieces
// of information about the problem:
// 1. The byte offset of the error is returned in `err_offset`.
// 2. The type of error is returned in `err`.
query_new :: #force_inline proc(language: Language, source: string) -> (query: Query, err_offset: u32, err: Query_Error) {
	query = _query_new(language, strings.unsafe_string_to_cstring(source), u32(len(source)), &err_offset, &err)
	return
}

// Get all of the predicates for the given pattern in the query.
//
// The predicates are represented as a single slice of steps. There are three
// types of steps in this slice, which correspond to the three legal values for
// the `type` field:
// - `.Capture` - Steps with this type represent names of captures.
//    Their `value_id` can be used with the [`query_capture_name_for_id`] function
//    to obtain the name of the capture.
// - `.String` - Steps with this type represent literal strings.
//    Their `value_id` can be used with the [`query_string_value_for_id`] function
//    to obtain their string value.
// - `.Done` - Steps with this type are *sentinels* that represent the end of an individual predicate.
//    If a pattern has two predicates, then there will be two with this `type` in the slice.
query_predicates_for_pattern :: #force_inline proc(self: Query, pattern_index: u32) -> []Query_Predicate_Step {
	length: u32 = ---
	multi := _query_predicates_for_pattern(self, pattern_index, &length)
	return multi[:length]
}

// Get the name of one of the query's captures, or one of the
// query's string literals. Each capture and string is associated with a
// numeric id based on the order that it appeared in the query's source.
query_capture_name_for_id :: #force_inline proc(self: Query, index: u32) -> string {
	length: u32 = ---
	cstr := _query_capture_name_for_id(self, index, &length)
	return string(([^]byte)(cstr)[:length])
}

query_string_value_for_id :: #force_inline proc(self: Query, index: u32) -> string {
	length: u32 = ---
	cstr := _query_string_value_for_id(self, index, &length)
	return string(([^]byte)(cstr)[:length])
}

// Disable a certain capture within a query.
//
// This prevents the capture from being returned in matches, and also avoids
// any resource usage associated with recording the capture. Currently, there
// is no way to undo this.
query_disable_capture :: #force_inline proc(self: Query, name: string) {
	_query_disable_capture(self, strings.unsafe_string_to_cstring(name), u32(len(name)))
}

query_cursor_set_range :: proc {
	query_cursor_set_byte_range,
	query_cursor_set_point_range,
}

// Advance to the next match of the currently running query.
query_cursor_next_match :: #force_inline proc(self: Query_Cursor) -> (match: Query_Match, ok: bool) {
	ok = _query_cursor_next_match(self, &match)
	return
}

// Advance to the next capture of the currently running query.
//
// If there is a capture, return it, and its index within the match's capture. Otherwise return `false`.
query_cursor_next_capture :: #force_inline proc(self: Query_Cursor) -> (match: Query_Match, capture_index: u32, ok: bool) {
	ok = _query_cursor_next_capture(self, &match, &capture_index)
	return
}

// Get the numerical id for the given node type string.
language_symbol_for_name :: #force_inline proc(self: Language, string: string, is_named: bool) -> Symbol {
	return _language_symbol_for_name(self, strings.unsafe_string_to_cstring(string), u32(len(string)), is_named)
}

// Get the numerical id for the given field name string.
language_field_id_for_name :: #force_inline proc(self: Language, name: string) -> Field_Id {
	return _language_field_id_for_name(self, strings.unsafe_string_to_cstring(name), u32(len(name)))
}

// Get a list of all supertype symbols for the language.
language_supertypes :: #force_inline proc(self: Language) -> []Symbol {
	len: u32
	supertypes := _language_supertypes(self, &len)
	return supertypes[:len]
}

// Get a list of all subtype symbol ids for a given supertype symbol.
//
// See `language_supertypes` for fetching all supertype symbols.
language_subtypes :: #force_inline proc(self: Language, supertype: Symbol) -> []Symbol {
	len: u32
	subtypes := _language_subtypes(self, supertype, &len)
	return subtypes[:len]
}

// Create a language from a buffer of Wasm. The resulting language behaves
// like any other Tree-sitter language, except that in order to use it with
// a parser, that parser must have a Wasm store. Note that the language
// can be used with any Wasm store, it doesn't need to be the same store that
// was used to originally load it.
wasm_store_load_language :: #force_inline proc(self: ^Wasm_Store, name: cstring, wasm: string) -> (lang: Language, err: Wasm_Error) {
	lang = _wasm_store_load_language(self, name, strings.unsafe_string_to_cstring(wasm), u32(len(wasm)), &err)
	return
}

// when BIND_HIGHLIGHT {
//
// 	// Construct a `Highlighter` by providing a list of strings containing
// 	// the HTML attributes that should be applied for each highlight value.
// 	highlighter_new :: #force_inline proc(highlight_names: []cstring, attribute_strings: []cstring) -> ^Highlighter {
// 		assert(len(highlight_names) == len(attribute_strings), "highlight_names must be the same length as attribute_strings")
// 		return _highlighter_new(raw_data(highlight_names), raw_data(attribute_strings), u32(len(highlight_names)))
// 	}
//
// 	// Add a `Language` to a highlighter. The language is associated with a
// 	// scope name, which can be used later to select a language for syntax
// 	// highlighting. Along with the language, you must provide a JSON string
// 	// containing the compiled PropertySheet to use for syntax highlighting
// 	// with that language. You can also optionally provide an 'injection regex',
// 	// which is used to detect when this language has been embedded in a document
// 	// written in a different language.
// 	highlighter_add_language :: #force_inline proc(
// 		self: ^Highlighter,
// 		language: Language,
// 		language_name: cstring,
// 		scope_name: cstring,
// 		highlight_query: string,
// 		injection_regex: cstring = nil,
// 		injection_query: string = "",
// 		locals_query: string = "",
// 		apply_all_captures: bool = true,
// 	) -> Highlight_Error {
// 		return _highlighter_add_language(
// 			self,
// 			language_name,
// 			scope_name,
// 			injection_regex,
// 			language,
// 			strings.unsafe_string_to_cstring(highlight_query),
// 			strings.unsafe_string_to_cstring(injection_query),
// 			strings.unsafe_string_to_cstring(locals_query),
// 			u32(len(highlight_query)),
// 			u32(len(injection_query)),
// 			u32(len(locals_query)),
// 			apply_all_captures,
// 		)
// 	}
//
// 	// Compute syntax highlighting for a given document. You must first
// 	// create a `HighlightBuffer` to hold the output.
// 	highlighter_highlight :: #force_inline proc(
// 		self: ^Highlighter,
// 		scope_name: cstring,
// 		source_code: string,
// 		output: ^Highlight_Buffer,
// 		cancellation_flag: ^uint = nil,
// 	) -> Highlight_Error {
// 		return _highlighter_highlight(
// 			self,
// 			scope_name,
// 			strings.unsafe_string_to_cstring(source_code),
// 			u32(len(source_code)),
// 			output,
// 			cancellation_flag,
// 		)
// 	}
// }
