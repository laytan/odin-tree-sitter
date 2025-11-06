package main

// Generated through `odin run build -- install`
import ts ".."

// Generated through `odin run build -- install-parser https://github.com/tree-sitter-grammars/tree-sitter-odin`
import ts_odin "../parsers/odin"

import "core:fmt"
import "core:os"
import "core:log"
import "core:mem"

main :: proc() {
	logger := log.create_console_logger(.Debug when ODIN_DEBUG else .Info, {
		.Level,
		.Terminal_Color,
		.Short_File_Path,
		.Line,
	})
	context.logger = logger

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	la: log.Log_Allocator
	log.log_allocator_init(&la, .Debug, .Human)
	context.allocator = log.log_allocator(&la)

	compat: ts.Compat_Allocator
	ts.compat_allocator_init(&compat)

	defer {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %m\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	}

	{
		ts.set_odin_allocator(ts.compat_allocator(&compat))

		parser := ts.parser_new()
		defer ts.parser_delete(parser)

		ts.parser_set_odin_logger(parser, &logger, .Debug)

		odin_lang := ts_odin.tree_sitter_odin()

		ok := ts.parser_set_language(parser, odin_lang)
		fmt.assertf(ok, "version mismatch between tree-sitter-odin (%v) and tree-sitter itself (%v-%v)", ts.language_abi_version(odin_lang), ts.MIN_COMPATIBLE_LANGUAGE_VERSION, ts.LANGUAGE_VERSION)

		data, read_ok := os.read_entire_file(#file)
		fmt.assertf(read_ok, "reading current file at %q failed", #file)
		defer delete(data)
		source := string(data)

		tree := ts.parser_parse_string(parser, source)
		assert(tree != nil)
		defer ts.tree_delete(tree)

		root := ts.tree_root_node(tree)

		// child := ts.node_named_child(root, 0)
		// fmt.println(ts.node_text(child, source))

		{
			query, err_offset, err := ts.query_new(odin_lang, ts_odin.HIGHLIGHTS)
			fmt.assertf(err == nil, "could not new a query, %v at %v", err, err_offset)
			defer ts.query_delete(query)

			cursor := ts.query_cursor_new()
			defer ts.query_cursor_delete(cursor)

			ts.query_cursor_exec(cursor, query, root)

			for match, cap_idx in ts.query_cursor_next_capture(cursor) {
				cap := match.captures[cap_idx]
				if len(ts.query_predicates_for_pattern(query, u32(match.pattern_index))) > 0 {
					continue
				}
				fmt.printf("%q: %s", ts.node_text(cap.node, source), ts.query_capture_name_for_id(query, cap.index))
				fmt.println()
			}
		}
	}
}
