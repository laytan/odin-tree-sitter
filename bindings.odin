package ts

// This file contains the general bindings.

when ODIN_OS != .Windows {
	foreign import ts "tree-sitter/libtree-sitter.a"
}

/*******************/
/* Section - Types */
/*******************/

State_Id :: distinct u16
Symbol   :: distinct u16
Field_Id :: distinct u16

// typedef struct TSLanguage TSLanguage;
// typedef struct TSParser TSParser;
// typedef struct TSTree TSTree;
// typedef struct TSQuery TSQuery;
// typedef struct TSQueryCursor TSQueryCursor;
// typedef struct TSLookaheadIterator TSLookaheadIterator;

Language           :: distinct struct{}
Parser             :: distinct struct{}
Tree               :: distinct struct{}
Query              :: distinct struct{}
Query_Cursor       :: distinct struct{}
Lookahead_Iterator :: distinct struct{}

Input_Encoding :: enum i32 {
	UTF8 = 0,
	UTF16,
}

Symbol_Type :: enum i32 {
	Regular = 0,
	Anonymous,
	Auxiliary,
}

Point :: struct {
	row: u32,
	col: u32,
}

Range :: struct {
	start_point: Point,
	end_point:   Point,
	start_byte:  u32,
	end_byte:    u32,
}

Input :: struct {
	payload:  rawptr,
	read:     proc "c" (payload: rawptr, byte_index: u32, position: Point, bytes_read: ^u32) -> cstring,
	encoding: Input_Encoding,
}

Log_Type :: enum i32 {
	Parse = 0,
	Lex,
}

Logger :: struct {
	payload: rawptr,
	log:     proc "c" (payload: rawptr, log_type: Log_Type, buffer: cstring),
}

Input_Edit :: struct {
	start_byte:    u32,
	old_end_byte:  u32,
	new_end_byte:  u32,
	start_point:   Point,
	old_end_point: Point,
	new_end_point: Point,
}

Node :: struct {
	ctx:  [4]u32,
	id:   rawptr,
	tree: ^Tree,
}

Tree_Cursor :: struct {
	tree: rawptr,
	id:   rawptr,
	ctx:  [2]u32,
}

Query_Capture :: struct {
	node:  Node,
	index: u32,
}

Quantifier :: enum i32 {
	Zero = 0,
	Zero_Or_One,
	Zero_Or_More,
	One,
	One_Or_More,
}

Query_Match :: struct {
	id:            u32,
	pattern_index: u16,
	capture_count: u16,
	captures:      [^]Query_Capture,
}

Query_Predicate_Step_Type :: enum i32 {
	Done = 0,
	Capture,
	String,
}

Query_Predicate_Step :: struct {
	type:     Query_Predicate_Step_Type,
	value_id: u32,
}

Query_Error :: enum i32 {
	None = 0,
	Syntax,
	Node_Type,
	Field,
	Capture,
	Structure,
	Language,
}

/********************/
/* Section - Parser */
/********************/

@(link_prefix="ts_")
foreign ts {
	/**
	 * Create a new parser.
	 *
	 * TSParser *ts_parser_new(void);
	 */
	parser_new :: proc() -> ^Parser ---

	/**
	 * Delete the parser, freeing all of the memory that it used.
	 *
	 * void ts_parser_delete(TSParser *self);
	 */
	parser_delete :: proc(self: ^Parser) ---

	/**
	 * Get the parser's current language.
	 *
	 * const TSLanguage *ts_parser_language(const TSParser *self);
	 */
	parser_language :: proc(self: ^Parser) -> ^Language ---

	/**
	 * Set the language that the parser should use for parsing.
	 *
	 * Returns a boolean indicating whether or not the language was successfully
	 * assigned. True means assignment succeeded. False means there was a version
	 * mismatch: the language was generated with an incompatible version of the
	 * Tree-sitter CLI. Check the language's version using [`language_version`]
	 * and compare it to this library's [`LANGUAGE_VERSION`] and
	 * [`MIN_COMPATIBLE_LANGUAGE_VERSION`] constants.
	 *
	 * bool ts_parser_set_language(TSParser *self, const TSLanguage *language);
	 */
	parser_set_language :: proc(self: ^Parser, language: ^Language) -> bool ---

	/**
	 * Set the ranges of text that the parser should include when parsing.
	 *
	 * By default, the parser will always include entire documents. This function
	 * allows you to parse only a *portion* of a document but still return a syntax
	 * tree whose ranges match up with the document as a whole. You can also pass
	 * multiple disjoint ranges.
	 *
	 * The second and third parameters specify the location and length of an array
	 * of ranges. The parser does *not* take ownership of these ranges; it copies
	 * the data, so it doesn't matter how these ranges are allocated.
	 *
	 * If `count` is zero, then the entire document will be parsed. Otherwise,
	 * the given ranges must be ordered from earliest to latest in the document,
	 * and they must not overlap. That is, the following must hold for all:
	 *
	 * `i < count - 1`: `ranges[i].end_byte <= ranges[i + 1].start_byte`
	 *
	 * If this requirement is not satisfied, the operation will fail, the ranges
	 * will not be assigned, and this function will return `false`. On success,
	 * this function returns `true`
	 *
	 * bool ts_parser_set_included_ranges(TSParser *self, const TSRange *ranges, uint32_t count);
	 */
	@(link_name="ts_parser_set_included_ranges")
	_parser_set_included_ranges :: proc(self: ^Parser, ranges: [^]Range, count: u32) -> bool ---

	/**
	 * Get the ranges of text that the parser will include when parsing.
	 *
	 * The returned pointer is owned by the parser. The caller should not free it
	 * or write to it. The length of the array will be written to the given
	 * `count` pointer.
	 *
	 * const TSRange *ts_parser_included_ranges(const TSParser *self, uint32_t *count);
	 */
	@(link_name="ts_parser_included_ranges")
	_parser_included_ranges :: proc(self: ^Parser, count: ^u32) -> [^]Range ---

	/**
	 * Use the parser to parse some source code and create a syntax tree.
	 *
	 * If you are parsing this document for the first time, pass `NULL` for the
	 * `old_tree` parameter. Otherwise, if you have already parsed an earlier
	 * version of this document and the document has since been edited, pass the
	 * previous syntax tree so that the unchanged parts of it can be reused.
	 * This will save time and memory. For this to work correctly, you must have
	 * already edited the old syntax tree using the [`tree_edit`] function in a
	 * way that exactly matches the source code changes.
	 *
	 * The [`Input`] parameter lets you specify how to read the text. It has the
	 * following three fields:
	 * 1. [`read`]: A function to retrieve a chunk of text at a given byte offset
	 *    and (row, column) position. The function should return a pointer to the
	 *    text and write its length to the [`bytes_read`] pointer. The parser does
	 *    not take ownership of this buffer; it just borrows it until it has
	 *    finished reading it. The function should write a zero value to the
	 *    [`bytes_read`] pointer to indicate the end of the document.
	 * 2. [`payload`]: An arbitrary pointer that will be passed to each invocation
	 *    of the [`read`] function.
	 * 3. [`encoding`]: An indication of how the text is encoded. Either
	 *    `TSInputEncodingUTF8` or `TSInputEncodingUTF16`.
	 *
	 * This function returns a syntax tree on success, and `NULL` on failure. There
	 * are three possible reasons for failure:
	 * 1. The parser does not have a language assigned. Check for this using the
	 *	  [`parser_language`] function.
	 * 2. Parsing was cancelled due to a timeout that was set by an earlier call to
	 *    the [`parser_set_timeout`] function. You can resume parsing from
	 *    where the parser left out by calling [`parser_parse`] again with the
	 *    same arguments. Or you can start parsing from scratch by first calling
	 *    [`parser_reset`].
	 * 3. Parsing was cancelled using a cancellation flag that was set by an
	 *    earlier call to [`parser_set_cancellation_flag`]. You can resume parsing
	 *    from where the parser left out by calling [`parser_parse`] again with
	 *    the same arguments.
	 *
	 * [`read`]: Input::read
	 * [`payload`]: Input::payload
	 * [`encoding`]: Input::encoding
	 * [`bytes_read`]: Input::read
	 *
	 * TSTree *ts_parser_parse(TSParser *self, const TSTree *old_tree, TSInput input);
	 */
	parser_parse :: proc(self: ^Parser, old_tree: ^Tree, input: Input) -> Maybe(^Tree) ---

	/**
	 * Use the parser to parse some source code stored in one contiguous buffer.
	 * The first two parameters are the same as in the [`ts_parser_parse`] function
	 * above. The second two parameters indicate the location of the buffer and its
	 * length in bytes.
	 *
	 * TSTree *ts_parser_parse_string(TSParser *self, const TSTree *old_tree, const char *string, uint32_t length);
	 */
	@(link_name="ts_parser_parse_string")
	_parser_parse_string :: proc(self: ^Parser, old_tree: ^Tree, string: cstring, length: u32) -> ^Tree ---

	/**
	 * Use the parser to parse some source code stored in one contiguous buffer with
	 * a given encoding. The first four parameters work the same as in the
	 * [`ts_parser_parse_string`] method above. The final parameter indicates whether
	 * the text is encoded as UTF8 or UTF16.
	 *
	 * TSTree *ts_parser_parse_string_encoding(TSParser *self, const TSTree *old_tree, const char *string, uint32_t length, TSInputEncoding encoding);
	 */
	@(link_name="ts_parser_parse_string_encoding")
	_parser_parse_string_encoding :: proc(self: ^Parser, old_tree: ^Tree, string: cstring, length: u32, encoding: Input_Encoding) -> ^Tree ---

	/**
	 * Instruct the parser to start the next parse from the beginning.
	 *
	 * If the parser previously failed because of a timeout or a cancellation, then
	 * by default, it will resume where it left off on the next call to
	 * [`parser_parse`] or other parsing functions. If you don't want to resume,
	 * and instead intend to use this parser to parse some other document, you must
	 * call [`parser_reset`] first.
	 *
	 * void ts_parser_reset(TSParser *self);
	 */
	parser_reset :: proc(self: ^Parser) ---

	/**
	 * Set the maximum duration in microseconds that parsing should be allowed to
	 * take before halting.
	 *
	 * If parsing takes longer than this, it will halt early, returning NULL.
	 * See [`ts_parser_parse`] for more information.
	 *
	 * void ts_parser_set_timeout_micros(TSParser *self, uint64_t timeout_micros);
	 */
	@(link_name="ts_parser_set_timeout_micros")
	_parser_set_timeout_micros :: proc(self: ^Parser, timeout_micros: u64) ---

	/**
	 * Get the duration in microseconds that parsing is allowed to take.
	 *
	 * uint64_t ts_parser_timeout_micros(const TSParser *self);
	 */
	@(link_name="ts_parser_timeout_micros")
	_parser_timeout_micros :: proc(self: ^Parser) -> u64 ---

	/**
	 * Set the parser's current cancellation flag pointer.
	 *
	 * If a non-null pointer is assigned, then the parser will periodically read
	 * from this pointer during parsing. If it reads a non-zero value, it will
	 * halt early, returning NULL. See [`parser_parse`] for more information.
	 *
	 * void ts_parser_set_cancellation_flag(TSParser *self, const size_t *flag);
	 */
	parser_set_cancellation_flag :: proc(self: ^Parser, flag: ^uint) ---

	/**
	 * Get the parser's current cancellation flag pointer.
	 *
	 * const size_t *ts_parser_cancellation_flag(const TSParser *self);
	 */
	parser_cancellation_flag :: proc(self: ^Parser) -> ^uint ---

	/**
	 * Set the logger that a parser should use during parsing.
	 *
	 * The parser does not take ownership over the logger payload. If a logger was
	 * previously assigned, the caller is responsible for releasing any memory
	 * owned by the previous logger.
	 *
	 * void ts_parser_set_logger(TSParser *self, TSLogger logger);
	 */
	parser_set_logger :: proc(self: ^Parser, logger: Logger) ---

	/**
	 * Get the parser's current logger.
	 *
	 * TSLogger ts_parser_logger(const TSParser *self);
	 */
	parser_logger :: proc(self: ^Parser) -> Logger ---

	/**
	 * Set the file descriptor to which the parser should write debugging graphs
	 * during parsing. The graphs are formatted in the DOT language. You may want
	 * to pipe these graphs directly to a `dot(1)` process in order to generate
	 * SVG output. You can turn off this logging by passing a negative number.
	 *
	 * void ts_parser_print_dot_graphs(TSParser *self, int fd);
	 */
	@(link_name="ts_parser_print_dot_graphs")
	_parser_print_dot_graphs :: proc(self: ^Parser, fd: i32) ---

	/******************/
	/* Section - Tree */
	/******************/

	/**
	 * Create a shallow copy of the syntax tree. This is very fast.
	 *
	 * You need to copy a syntax tree in order to use it on more than one thread at
	 * a time, as syntax trees are not thread safe.
	 *
	 * TSTree *ts_tree_copy(const TSTree *self);
	 */
	tree_copy :: proc(self: ^Tree) -> ^Tree ---

	/**
	 * Delete the syntax tree, freeing all of the memory that it used.
	 *
	 * void ts_tree_delete(TSTree *self);
	 */
	 tree_delete :: proc(self: ^Tree) ---

	/**
	 * Get the root node of the syntax tree.
	 *
	 * TSNode ts_tree_root_node(const TSTree *self);
	 */
	tree_root_node :: proc(self: ^Tree) -> Node ---

	/**
	 * Get the root node of the syntax tree, but with its position
	 * shifted forward by the given offset.
	 *
	 * TSNode ts_tree_root_node_with_offset(const TSTree *self, uint32_t offset_bytes, TSPoint offset_extent);
	 */
	tree_root_node_with_offset :: proc(self: ^Tree, offset_bytes: u32, offset_extent: Point) -> Node ---

	/**
	 * Get the language that was used to parse the syntax tree.
	 *
	 * const TSLanguage *ts_tree_language(const TSTree *self);
	 */
	tree_language :: proc(self: ^Tree) -> ^Language ---

	/**
	 * Get the array of included ranges that was used to parse the syntax tree.
	 *
	 * The returned pointer must be freed by the caller.
	 *
	 * TSRange *ts_tree_included_ranges(const TSTree *self, uint32_t *length);
	 */
	@(link_name="ts_tree_included_ranges")
	_tree_included_ranges :: proc(self: ^Tree, length: ^u32) -> [^]Range ---

	/**
	 * Edit the syntax tree to keep it in sync with source code that has been
	 * edited.
	 *
	 * You must describe the edit both in terms of byte offsets and in terms of
	 * (row, column) coordinates.
	 *
	 * void ts_tree_edit(TSTree *self, const TSInputEdit *edit);
	 */
	tree_edit :: proc(self: ^Tree, edit: ^Input_Edit) ---

	/**
	 * Compare an old edited syntax tree to a new syntax tree representing the same
	 * document, returning an array of ranges whose syntactic structure has changed.
	 *
	 * For this to work correctly, the old syntax tree must have been edited such
	 * that its ranges match up to the new tree. Generally, you'll want to call
	 * this function right after calling one of the [`ts_parser_parse`] functions.
	 * You need to pass the old tree that was passed to parse, as well as the new
	 * tree that was returned from that function.
	 *
	 * The returned array is allocated using `malloc` and the caller is responsible
	 * for freeing it using `free`. The length of the array will be written to the
	 * given `length` pointer.
	 *
	 * TSRange *ts_tree_get_changed_ranges(const TSTree *old_tree, const TSTree *new_tree, uint32_t *length);
	 */
	@(link_name="ts_tree_get_changed_ranges")
	_tree_get_changed_ranges :: proc(old_tree: ^Tree, new_tree: ^Tree, length: ^u32) -> [^]Range ---

	/**
	 * Write a DOT graph describing the syntax tree to the given file.
	 *
	 * void ts_tree_print_dot_graph(const TSTree *self, int file_descriptor);
	 */
	@(link_name="ts_tree_print_dot_graph")
	_tree_print_dot_graph :: proc(self: ^Tree, file_descriptor: i32) ---

	/******************/
	/* Section - Node */
	/******************/

	/**
	 * Get the node's type as a null-terminated string.
	 *
	 * const char *ts_node_type(TSNode self);
	 */
	node_type :: proc(self: Node) -> cstring ---

	/**
	 * Get the node's type as a numerical id.
	 *
	 * TSSymbol ts_node_symbol(TSNode self);
	 */
	node_symbol :: proc(self: Node) -> Symbol ---

	/**
	 * Get the node's language.
	 *
	 * const TSLanguage *ts_node_language(TSNode self);
	 */
	node_language :: proc(self: Node) -> ^Language ---

	/**
	 * Get the node's type as it appears in the grammar ignoring aliases as a
	 * null-terminated string.
	 *
	 * const char *ts_node_grammar_type(TSNode self);
	 */
	node_grammar_type :: proc(self: Node) -> cstring ---

	/**
	 * Get the node's type as a numerical id as it appears in the grammar ignoring
	 * aliases. This should be used in [`language_next_state`] instead of
	 * [`node_symbol`].
	 *
	 * TSSymbol ts_node_grammar_symbol(TSNode self);
	 */
	node_grammar_symbol :: proc(self: Node) -> Symbol ---

	/**
	 * Get the node's start byte.
	 *
	 * uint32_t ts_node_start_byte(TSNode self);
	 */
	node_start_byte :: proc(self: Node) -> u32 ---

	/**
	 * Get the node's start position in terms of rows and columns.
	 *
	 * TSPoint ts_node_start_point(TSNode self);
	 */
	node_start_point :: proc(self: Node) -> Point ---

	/**
	 * Get the node's end byte.
	 *
	 * uint32_t ts_node_end_byte(TSNode self);
	 */
	node_end_byte :: proc(self: Node) -> u32 ---

	/**
	 * Get the node's end position in terms of rows and columns.
	 *
	 * TSPoint ts_node_end_point(TSNode self);
	 */
	node_end_point :: proc(self: Node) -> Point ---

	/**
	 * Get an S-expression representing the node as a string.
	 *
	 * NOTE: This string is allocated with the provided `malloc` and the caller is responsible for
	 * freeing it using `free`.
	 *
	 * char *ts_node_string(TSNode self);
	 */
	node_string :: proc(self: Node) -> cstring ---

	/**
	 * Check if the node is null. Functions like [`node_child`] and
	 * [`node_next_sibling`] will return a null node to indicate that no such node
	 * was found.
	 *
	 * bool ts_node_is_null(TSNode self);
	 */
	node_is_null :: proc(self: Node) -> bool ---

	/**
	 * Check if the node is *named*. Named nodes correspond to named rules in the
	 * grammar, whereas *anonymous* nodes correspond to string literals in the
	 * grammar.
	 *
	 * bool ts_node_is_named(TSNode self);
	 */
	node_is_named :: proc(self: Node) -> bool ---

	/**
	 * Check if the node is *missing*. Missing nodes are inserted by the parser in
	 * order to recover from certain kinds of syntax errors.
	 *
	 * bool ts_node_is_missing(TSNode self);
	 */
	node_is_missing :: proc(self: Node) -> bool ---

	/**
	 * Check if the node is *extra*. Extra nodes represent things like comments,
	 * which are not required the grammar, but can appear anywhere.
	 *
	 * bool ts_node_is_extra(TSNode self);
	 */
	node_is_extra :: proc(self: Node) -> bool ---

	/**
	 * Check if a syntax node has been edited.
	 *
	 * bool ts_node_has_changes(TSNode self);
	 */
	node_has_changes :: proc(self: Node) -> bool ---

	/**
	 * Check if the node is a syntax error or contains any syntax errors.
	 *
	 * bool ts_node_has_error(TSNode self);
	 */
	node_has_error :: proc(self: Node) -> bool ---

	/**
	 * Check if the node is a syntax error.
	 *
	 * bool ts_node_is_error(TSNode self);
	 */
	node_is_error :: proc(self: Node) -> bool ---

	/**
	 * Get this node's parse state.
	 *
	 * TSStateId ts_node_parse_state(TSNode self);
	 */
	node_parse_state :: proc(self: Node) -> State_Id ---

	/**
	 * Get the parse state after this node.
	 *
	 * TSStateId ts_node_next_parse_state(TSNode self);
	 */
	node_next_parse_state :: proc(self: Node) -> State_Id ---

	/**
	 * Get the node's immediate parent.
	 *
	 * TSNode ts_node_parent(TSNode self);
	 */
	node_parent :: proc(self: Node) -> Node ---

	/**
	 * Get the node's child at the given index, where zero represents the first
	 * child.
	 *
	 * TSNode ts_node_child(TSNode self, uint32_t child_index);
	 */
	node_child :: proc(self: Node, child_index: u32) -> Node ---

	/**
	 * Get the field name for node's child at the given index, where zero represents
	 * the first child. Returns NULL, if no field is found.
	 *
	 * const char *ts_node_field_name_for_child(TSNode self, uint32_t child_index);
	 */
	node_field_name_for_child :: proc(self: Node, child_index: u32) -> cstring ---

	/**
	 * Get the node's number of children.
	 *
	 * uint32_t ts_node_child_count(TSNode self);
	 */
	node_child_count :: proc(self: Node) -> u32 ---

	/**
	 * Get the node's *named* child at the given index.
	 *
	 * See also [`ts_node_is_named`].
	 *
	 * TSNode ts_node_named_child(TSNode self, uint32_t child_index);
	 */
	node_named_child :: proc(self: Node, child_index: u32) -> Node ---

	/**
	 * Get the node's number of *named* children.
	 *
	 * See also [`ts_node_is_named`].
	 *
	 * uint32_t ts_node_named_child_count(TSNode self);
	 */
	node_named_child_count :: proc(self: Node) -> u32 ---

	/**
	 * Get the node's child with the given field name.
	 *
	 * TSNode ts_node_child_by_field_name(TSNode self, const char *name, uint32_t name_length);
	 */
	@(link_name="ts_node_child_by_field_name")
	_node_child_by_field_name :: proc(self: Node, name: cstring, name_length: u32) -> Node ---

	/**
	 * Get the node's child with the given numerical field id.
	 *
	 * You can convert a field name to an id using the
	 * [`ts_language_field_id_for_name`] function.
	 *
	 * TSNode ts_node_child_by_field_id(TSNode self, TSFieldId field_id);
	 */
	node_child_by_field_id :: proc(self: Node, field_id: Field_Id) -> Node ---

	/**
	 * Get the node's next / previous sibling.
	 *
	 * TSNode ts_node_next_sibling(TSNode self);
	 * TSNode ts_node_prev_sibling(TSNode self);
	 */
	 node_next_sibling :: proc(self: Node) -> Node ---
	 node_prev_sibling :: proc(self: Node) -> Node ---

	/**
	 * Get the node's next / previous *named* sibling.
	 *
	 * TSNode ts_node_next_named_sibling(TSNode self);
	 * TSNode ts_node_prev_named_sibling(TSNode self);
	 */
	node_next_named_sibling :: proc(self: Node) -> Node ---
	node_prev_named_sibling :: proc(self: Node) -> Node ---

	/**
	 * Get the node's first child that extends beyond the given byte offset.
	 *
	 * TSNode ts_node_first_child_for_byte(TSNode self, uint32_t byte);
	 */
	 node_first_child_for_byte :: proc(self: Node, byte: u32) -> Node ---

	/**
	 * Get the node's first named child that extends beyond the given byte offset.
	 *
	 * TSNode ts_node_first_named_child_for_byte(TSNode self, uint32_t byte);
	 */
	 node_first_named_child_for_byte :: proc(self: Node, byte: u32) -> Node ---

	/**
	 * Get the node's number of descendants, including one for the node itself.
	 *
	 * uint32_t ts_node_descendant_count(TSNode self);
	 */
	node_descendant_count :: proc(self: Node) -> u32 ---

	/**
	 * Get the smallest node within this node that spans the given range of bytes
	 * or (row, column) positions.
	 *
	 * TSNode ts_node_descendant_for_byte_range(TSNode self, uint32_t start, uint32_t end);
	 * TSNode ts_node_descendant_for_point_range(TSNode self, TSPoint start, TSPoint end);
	 */
	node_descendant_for_byte_range  :: proc(self: Node, start, end: u32)   -> Node ---
	node_descendant_for_point_range :: proc(self: Node, start, end: Point) -> Node ---

	/**
	 * Get the smallest named node within this node that spans the given range of
	 * bytes or (row, column) positions.
	 *
	 * TSNode ts_node_named_descendant_for_byte_range(TSNode self, uint32_t start, uint32_t end);
	 * TSNode ts_node_named_descendant_for_point_range(TSNode self, TSPoint start, TSPoint end);
	 */
	node_named_descendant_for_byte_range  :: proc(self: Node, start, end: u32)   -> Node ---
	node_named_descendant_for_point_range :: proc(self: Node, start, end: Point) -> Node ---

	/**
	 * Edit the node to keep it in-sync with source code that has been edited.
	 *
	 * This function is only rarely needed. When you edit a syntax tree with the
	 * [`tree_edit`] function, all of the nodes that you retrieve from the tree
	 * afterward will already reflect the edit. You only need to use [`node_edit`]
	 * when you have a [`Node`] instance that you want to keep and continue to use
	 * after an edit.
	 *
	 * void ts_node_edit(TSNode *self, const TSInputEdit *edit);
	 */
	node_edit :: proc(self: ^Node, edit: ^Input_Edit) ---

	/**
	 * Check if two nodes are identical.
	 *
	 * bool ts_node_eq(TSNode self, TSNode other);
	 */
	node_eq :: proc(self, other: Node) -> bool ---

	/************************/
	/* Section - TreeCursor */
	/************************/

	/**
	 * Create a new tree cursor starting from the given node.
	 *
	 * A tree cursor allows you to walk a syntax tree more efficiently than is
	 * possible using the [`Node`] functions. It is a mutable object that is always
	 * on a certain syntax node, and can be moved imperatively to different nodes.
	 *
	 * TSTreeCursor ts_tree_cursor_new(TSNode node);
	 */
	tree_cursor_new :: proc(node: Node) -> Tree_Cursor ---

	/**
	 * Delete a tree cursor, freeing all of the memory that it used.
	 *
	 * void ts_tree_cursor_delete(TSTreeCursor *self);
	 */
	tree_cursor_delete :: proc(self: ^Tree_Cursor) ---	

	/**
	 * Re-initialize a tree cursor to start at a different node.
	 *
	 * void ts_tree_cursor_reset(TSTreeCursor *self, TSNode node);
	 */
	tree_cursor_reset :: proc(self: ^Tree_Cursor, node: Node) ---	

	/**
	 * Re-initialize a tree cursor to the same position as another cursor.
	 *
	 * Unlike [`tree_cursor_reset`], this will not lose parent information and
	 * allows reusing already created cursors.
	 *
	 * void ts_tree_cursor_reset_to(TSTreeCursor *dst, const TSTreeCursor *src);
	 */
	tree_cursor_reset_to :: proc(dst: ^Tree_Cursor, src: ^Tree_Cursor) ---	

	/**
	 * Get the tree cursor's current node.
	 *
	 * TSNode ts_tree_cursor_current_node(const TSTreeCursor *self);
	 */
	tree_cursor_current_node :: proc(self: ^Tree_Cursor) -> Node ---	

	/**
	 * Get the field name of the tree cursor's current node.
	 *
	 * This returns `NULL` if the current node doesn't have a field.
	 * See also [`node_child_by_field_name`].
	 *
	 * const char *ts_tree_cursor_current_field_name(const TSTreeCursor *self);
	 */
	tree_cursor_current_field_name :: proc(self: ^Tree_Cursor) -> cstring ---	

	/**
	 * Get the field id of the tree cursor's current node.
	 *
	 * This returns zero if the current node doesn't have a field.
	 * See also [`node_child_by_field_id`], [`language_field_id_for_name`].
	 *
	 * TSFieldId ts_tree_cursor_current_field_id(const TSTreeCursor *self);
	 */
	tree_cursor_current_field_id :: proc(self: ^Tree_Cursor) -> Field_Id ---

	/**
	 * Move the cursor to the parent of its current node.
	 *
	 * This returns `true` if the cursor successfully moved, and returns `false`
	 * if there was no parent node (the cursor was already on the root node).
	 *
	 * bool ts_tree_cursor_goto_parent(TSTreeCursor *self);
	 */
	tree_cursor_goto_parent :: proc(self: ^Tree_Cursor)	-> bool ---

	/**
	 * Move the cursor to the next sibling of its current node.
	 *
	 * This returns `true` if the cursor successfully moved, and returns `false`
	 * if there was no next sibling node.
	 *
	 * bool ts_tree_cursor_goto_next_sibling(TSTreeCursor *self);
	 */
	tree_cursor_goto_next_sibling :: proc(self: ^Tree_Cursor) -> bool ---

	/**
	 * Move the cursor to the previous sibling of its current node.
	 *
	 * This returns `true` if the cursor successfully moved, and returns `false` if
	 * there was no previous sibling node.
	 *
	 * NOTE: this function may be slower than
	 * [`tree_cursor_goto_next_sibling`] due to how node positions are stored. In
	 * the worst case, this will need to iterate through all the children upto the
	 * previous sibling node to recalculate its position.
	 *
	 * bool ts_tree_cursor_goto_previous_sibling(TSTreeCursor *self);
	 */
	tree_cursor_goto_previous_sibling :: proc(self: Tree_Cursor) -> bool ---

	/**
	 * Move the cursor to the first child of its current node.
	 *
	 * This returns `true` if the cursor successfully moved, and returns `false`
	 * if there were no children.
	 *
	 * bool ts_tree_cursor_goto_first_child(TSTreeCursor *self);
	 */
	tree_cursor_goto_first_child :: proc(self: ^Tree_Cursor) -> bool ---

	/**
	 * Move the cursor to the last child of its current node.
	 *
	 * This returns `true` if the cursor successfully moved, and returns `false` if
	 * there were no children.
	 *
	 * NOTE: this function may be slower than [`tree_cursor_goto_first_child`]
	 * because it needs to iterate through all the children to compute the child's
	 * position.
	 *
	 * bool ts_tree_cursor_goto_last_child(TSTreeCursor *self);
	 */
	tree_cursor_goto_last_child :: proc(self: ^Tree_Cursor) -> bool ---	

	/**
	 * Move the cursor to the node that is the nth descendant of
	 * the original node that the cursor was constructed with, where
	 * zero represents the original node itself.
	 *
	 * void ts_tree_cursor_goto_descendant(TSTreeCursor *self, uint32_t goal_descendant_index);
	 */
	tree_cursor_goto_descendant :: proc(self: ^Tree_Cursor, goal_descendant_index: u32) ---	

	/**
	 * Get the index of the cursor's current node out of all of the
	 * descendants of the original node that the cursor was constructed with.
	 *
	 * uint32_t ts_tree_cursor_current_descendant_index(const TSTreeCursor *self);
	 */
	tree_cursor_current_descendant_index :: proc(self: ^Tree_Cursor) -> u32 ---	

	/**
	 * Get the depth of the cursor's current node relative to the original
	 * node that the cursor was constructed with.
	 *
	 * uint32_t ts_tree_cursor_current_depth(const TSTreeCursor *self);
	 */
	tree_cursor_current_depth :: proc(self: ^Tree_Cursor) -> u32 ---

	/**
	 * Move the cursor to the first child of its current node that extends beyond
	 * the given byte offset or point.
	 *
	 * This returns the index of the child node if one was found, and returns -1
	 * if no such child was found.
	 *
	 * int64_t ts_tree_cursor_goto_first_child_for_byte(TSTreeCursor *self, uint32_t goal_byte);
	 * int64_t ts_tree_cursor_goto_first_child_for_point(TSTreeCursor *self, TSPoint goal_point);
	 */
	ts_tree_cursor_goto_first_child_for_byte  :: proc(self: ^Tree_Cursor, goal_byte: u32)    -> i64 ---	
	ts_tree_cursor_goto_first_child_for_point :: proc(self: ^Tree_Cursor, goal_point: Point) -> i64 ---	

	/**
	 * TSTreeCursor ts_tree_cursor_copy(const TSTreeCursor *cursor);
	 */
	tree_cursor_copy :: proc(cursor: ^Tree_Cursor) -> Tree_Cursor ---

	/*******************/
	/* Section - Query */
	/*******************/

	/**
	 * Create a new query from a string containing one or more S-expression
	 * patterns. The query is associated with a particular language, and can
	 * only be run on syntax nodes parsed with that language.
	 *
	 * If all of the given patterns are valid, this returns a [`TSQuery`].
	 * If a pattern is invalid, this returns `NULL`, and provides two pieces
	 * of information about the problem:
	 * 1. The byte offset of the error is written to the `error_offset` parameter.
	 * 2. The type of error is written to the `error_type` parameter.
	 *
	 * TSQuery *ts_query_new(const TSLanguage *language, const char *source, uint32_t source_len, uint32_t *error_offset, TSQueryError *error_type);
	 */
	@(link_name="ts_query_new")
	_query_new :: proc(language: ^Language, source: cstring, source_len: u32, error_offset: ^u32, error_type: ^Query_Error) -> ^Query ---

	/**
	 * Delete a query, freeing all of the memory that it used.
	 *
	 * void ts_query_delete(TSQuery *self);
	 */
	query_delete :: proc(self: ^Query) ---	

	/**
	 * Get the number of patterns, captures, or string literals in the query.
	 *
	 * uint32_t ts_query_pattern_count(const TSQuery *self);
	 * uint32_t ts_query_capture_count(const TSQuery *self);
	 * uint32_t ts_query_string_count(const TSQuery *self);
	 */
	query_pattern_count :: proc(self: ^Query) -> u32 ---
	query_capture_count :: proc(self: ^Query) -> u32 ---
	query_string_count  :: proc(self: ^Query) -> u32 ---

	/**
	 * Get the byte offset where the given pattern starts in the query's source.
	 *
	 * This can be useful when combining queries by concatenating their source
	 * code strings.
	 *
	 * uint32_t ts_query_start_byte_for_pattern(const TSQuery *self, uint32_t pattern_index);
	 */
	query_start_byte_for_pattern :: proc(self: ^Query, pattern_index: u32) -> u32 ---
	

	/**
	 * Get all of the predicates for the given pattern in the query.
	 *
	 * The predicates are represented as a single array of steps. There are three
	 * types of steps in this array, which correspond to the three legal values for
	 * the `type` field:
	 * - `TSQueryPredicateStepTypeCapture` - Steps with this type represent names
	 *    of captures. Their `value_id` can be used with the
	 *   [`ts_query_capture_name_for_id`] function to obtain the name of the capture.
	 * - `TSQueryPredicateStepTypeString` - Steps with this type represent literal
	 *    strings. Their `value_id` can be used with the
	 *    [`ts_query_string_value_for_id`] function to obtain their string value.
	 * - `TSQueryPredicateStepTypeDone` - Steps with this type are *sentinels*
	 *    that represent the end of an individual predicate. If a pattern has two
	 *    predicates, then there will be two steps with this `type` in the array.
	 *
	 * const TSQueryPredicateStep *ts_query_predicates_for_pattern(const TSQuery *self, uint32_t pattern_index, uint32_t *step_count);
	 */
	@(link_name="ts_query_predicates_for_pattern")
	_query_predicates_for_pattern :: proc(self: ^Query, pattern_index: u32, step_count: ^u32) -> [^]Query_Predicate_Step ---

	/*
	 * Check if the given pattern in the query has a single root node.
	 *
	 * bool ts_query_is_pattern_rooted(const TSQuery *self, uint32_t pattern_index);
	 */
	query_is_pattern_rooted :: proc(self: ^Query, pattern_index: u32) -> bool ---	

	/*
	 * Check if the given pattern in the query is 'non local'.
	 *
	 * A non-local pattern has multiple root nodes and can match within a
	 * repeating sequence of nodes, as specified by the grammar. Non-local
	 * patterns disable certain optimizations that would otherwise be possible
	 * when executing a query on a specific range of a syntax tree.
	 *
	 * bool ts_query_is_pattern_non_local(const TSQuery *self, uint32_t pattern_index);
	 */
	query_is_pattern_non_local :: proc(self: ^Query, pattern_index: u32) -> bool ---	

	/*
	 * Check if a given pattern is guaranteed to match once a given step is reached.
	 * The step is specified by its byte offset in the query's source code.
	 *
	 * bool ts_query_is_pattern_guaranteed_at_step(const TSQuery *self, uint32_t byte_offset);
	 */
	query_is_pattern_guaranteed_at_step :: proc(self: ^Query, byte_offset: u32) -> bool ---	

	/**
	 * Get the name and length of one of the query's captures, or one of the
	 * query's string literals. Each capture and string is associated with a
	 * numeric id based on the order that it appeared in the query's source.
	 *
	 * const char *ts_query_capture_name_for_id(const TSQuery *self, uint32_t index, uint32_t *length);
	 */
	@(link_name="ts_query_capture_name_for_id")
	_query_capture_name_for_id :: proc(self: ^Query, index: u32, length: ^u32) -> cstring ---

	/**
	 * Get the quantifier of the query's captures. Each capture is * associated
	 * with a numeric id based on the order that it appeared in the query's source.
	 *
	 * TSQuantifier ts_query_capture_quantifier_for_id(const TSQuery *self, uint32_t pattern_index, uint32_t capture_index);
	 */
	query_capture_quantifier_for_id :: proc(self: ^Query, pattern_index: u32, capture_index: u32) -> Quantifier ---

	/**
	 * const char *ts_query_string_value_for_id(const TSQuery *self, uint32_t index, uint32_t *length);
	 */
	@(link_name="ts_query_string_value_for_id")
	_query_string_value_for_id :: proc(self: ^Query, index: u32, length: ^u32) -> cstring ---

	/**
	 * Disable a certain capture within a query.
	 *
	 * This prevents the capture from being returned in matches, and also avoids
	 * any resource usage associated with recording the capture. Currently, there
	 * is no way to undo this.
	 *
	 * void ts_query_disable_capture(TSQuery *self, const char *name, uint32_t length);
	 */
	@(link_name="ts_query_disable_capture")
	_query_disable_capture :: proc(self: ^Query, name: cstring, length: u32) ---	

	/**
	 * Disable a certain pattern within a query.
	 *
	 * This prevents the pattern from matching and removes most of the overhead
	 * associated with the pattern. Currently, there is no way to undo this.
	 *
	 * void ts_query_disable_pattern(TSQuery *self, uint32_t pattern_index);
	 */
	query_disable_pattern :: proc(self: ^Query, pattern_index: u32) ---	

	/**
	 * Create a new cursor for executing a given query.
	 *
	 * The cursor stores the state that is needed to iteratively search
	 * for matches. To use the query cursor, first call [`query_cursor_exec`]
	 * to start running a given query on a given syntax node. Then, there are
	 * two options for consuming the results of the query:
	 * 1. Repeatedly call [`query_cursor_next_match`] to iterate over all of the
	 *    *matches* in the order that they were found. Each match contains the
	 *    index of the pattern that matched, and an array of captures. Because
	 *    multiple patterns can match the same set of nodes, one match may contain
	 *    captures that appear *before* some of the captures from a previous match.
	 * 2. Repeatedly call [`query_cursor_next_capture`] to iterate over all of the
	 *    individual *captures* in the order that they appear. This is useful if
	 *    don't care about which pattern matched, and just want a single ordered
	 *    sequence of captures.
	 *
	 * If you don't care about consuming all of the results, you can stop calling
	 * [`query_cursor_next_match`] or [`query_cursor_next_capture`] at any point.
	 * You can then start executing another query on another node by calling
	 * [`query_cursor_exec`] again.
	 *
	 * TSQueryCursor *ts_query_cursor_new(void);
	 */
	query_cursor_new :: proc() -> ^Query_Cursor ---	

	/**
	 * Delete a query cursor, freeing all of the memory that it used.
	 *
	 * void ts_query_cursor_delete(TSQueryCursor *self);
	 */
	query_cursor_delete :: proc(self: ^Query_Cursor) ---	

	/**
	 * Start running a given query on a given node.
	 *
	 * void ts_query_cursor_exec(TSQueryCursor *self, const TSQuery *query, TSNode node);
	 */
	query_cursor_exec :: proc(self: ^Query_Cursor, query: ^Query, node: Node) ---	

	/**
	 * Manage the maximum number of in-progress matches allowed by this query
	 * cursor.
	 *
	 * Query cursors have an optional maximum capacity for storing lists of
	 * in-progress captures. If this capacity is exceeded, then the
	 * earliest-starting match will silently be dropped to make room for further
	 * matches. This maximum capacity is optional — by default, query cursors allow
	 * any number of pending matches, dynamically allocating new space for them as
	 * needed as the query is executed.
	 *
	 * bool ts_query_cursor_did_exceed_match_limit(const TSQueryCursor *self);
	 * uint32_t ts_query_cursor_match_limit(const TSQueryCursor *self);
	 * void ts_query_cursor_set_match_limit(TSQueryCursor *self, uint32_t limit);
	 */
	query_cursor_did_exceed_match_limit :: proc(self: ^Query_Cursor) -> bool     ---
	query_cursor_match_limit            :: proc(self: ^Query_Cursor) -> u32      ---
	query_cursor_set_match_limit        :: proc(self: ^Query_Cursor, limit: u32) ---
	
	/**
	 * Set the range of bytes or (row, column) positions in which the query
	 * will be executed.
	 *
	 * void ts_query_cursor_set_byte_range(TSQueryCursor *self, uint32_t start_byte, uint32_t end_byte);
	 * void ts_query_cursor_set_point_range(TSQueryCursor *self, TSPoint start_point, TSPoint end_point);
	 */
	 query_cursor_set_byte_range  :: proc(self: ^Query_Cursor, start_byte,  end_byte: u32)    ---
	 query_cursor_set_point_range :: proc(self: ^Query_Cursor, start_point, end_point: Point) ---
	

	/**
	 * Advance to the next match of the currently running query.
	 *
	 * If there is a match, write it to `*match` and return `true`.
	 * Otherwise, return `false`.
	 *
	 * bool ts_query_cursor_next_match(TSQueryCursor *self, TSQueryMatch *match);
	 * void ts_query_cursor_remove_match(TSQueryCursor *self, uint32_t match_id);
	 */
	 @(link_name="ts_query_cursor_next_match")
	 _query_cursor_next_match   :: proc(self: ^Query_Cursor, match: ^Query_Match) -> bool ---
	 query_cursor_remove_match  :: proc(self: ^Query_Cursor, match_id: u32)               ---
	

	/**
	 * Advance to the next capture of the currently running query.
	 *
	 * If there is a capture, write its match to `*match` and its index within
	 * the matche's capture list to `*capture_index`. Otherwise, return `false`.
	 *
	 * bool ts_query_cursor_next_capture(TSQueryCursor *self, TSQueryMatch *match, uint32_t *capture_index);
	 */
	@(link_name="ts_query_cursor_next_capture")
	_query_cursor_next_capture :: proc(self: ^Query_Cursor, match: ^Query_Match, capture_index: ^u32) -> bool ---

	/**
	 * Set the maximum start depth for a query cursor.
	 *
	 * This prevents cursors from exploring children nodes at a certain depth.
	 * Note if a pattern includes many children, then they will still be checked.
	 *
	 * The zero max start depth value can be used as a special behavior and
	 * it helps to destructure a subtree by staying on a node and using captures
	 * for interested parts. Note that the zero max start depth only limit a search
	 * depth for a pattern's root node but other nodes that are parts of the pattern
	 * may be searched at any depth what defined by the pattern structure.
	 *
	 * Set to `max(u32)` to remove the maximum start depth.
	 *
	 * void ts_query_cursor_set_max_start_depth(TSQueryCursor *self, uint32_t max_start_depth);
	 */
	query_cursor_set_max_start_depth :: proc(self: ^Query_Cursor, max_start_depth: u32) ---

	/**********************/
	/* Section - Language */
	/**********************/

	/**
	 * Get the number of distinct node types in the language.
	 *
	 * uint32_t ts_language_symbol_count(const TSLanguage *self);
	 */
	language_symbol_count :: proc(self: ^Language) -> u32 ---	

	/**
	 * Get the number of valid states in this language.
	 *
	 * uint32_t ts_language_state_count(const TSLanguage *self);
	 */
	language_state_count :: proc(self: ^Language) -> u32 ---

	/**
	 * Get a node type string for the given numerical id.
	 *
	 * const char *ts_language_symbol_name(const TSLanguage *self, TSSymbol symbol);
	 */
	language_symbol_name :: proc(self: ^Language, symbol: Symbol) -> cstring ---	

	/**
	 * Get the numerical id for the given node type string.
	 *
	 * TSSymbol ts_language_symbol_for_name(const TSLanguage *self, const char *string, uint32_t length, bool is_named);
	 */
	@(link_name="ts_language_symbol_for_name")
	_language_symbol_for_name :: proc(self: ^Language, string: cstring, length: u32, is_named: bool) -> Symbol ---

	/**
	 * Get the number of distinct field names in the language.
	 *
	 * uint32_t ts_language_field_count(const TSLanguage *self);
	 */
	language_field_count :: proc(self: ^Language) -> u32 ---	

	/**
	 * Get the field name string for the given numerical id.
	 *
	 * const char *ts_language_field_name_for_id(const TSLanguage *self, TSFieldId id);
	 */
	language_field_name_for_id :: proc(self: ^Language, id: Field_Id) -> cstring ---	

	/**
	 * Get the numerical id for the given field name string.
	 *
	 * TSFieldId ts_language_field_id_for_name(const TSLanguage *self, const char *name, uint32_t name_length);
	 */
	@(link_name="ts_language_field_id_for_name")
	_language_field_id_for_name :: proc(self: ^Language, name: cstring, name_length: u32) -> Field_Id ---	

	/**
	 * Check whether the given node type id belongs to named nodes, anonymous nodes,
	 * or a hidden nodes.
	 *
	 * See also [`node_is_named`]. Hidden nodes are never returned from the API.
	 *
	 * TSSymbolType ts_language_symbol_type(const TSLanguage *self, TSSymbol symbol);
	 */
	language_symbol_type :: proc(self: ^Language, symbol: Symbol) -> Symbol_Type ---	

	/**
	 * Get the ABI version number for this language. This version number is used
	 * to ensure that languages were generated by a compatible version of
	 * Tree-sitter.
	 *
	 * See also [`parser_set_language`].
	 *
	 * uint32_t ts_language_version(const TSLanguage *self);
	 */
	language_version :: proc(self: ^Language) -> u32 ---	

	/**
	 * Get the next parse state. Combine this with lookahead iterators to generate
	 * completion suggestions or valid symbols in error nodes. Use
	 * [`node_grammar_symbol`] for valid symbols.
	 *
	 * TSStateId ts_language_next_state(const TSLanguage *self, TSStateId state, TSSymbol symbol);
	 */
	language_next_state :: proc(self: ^Language, state: State_Id, symbol: Symbol) -> State_Id ---

	/********************************/
	/* Section - Lookahead Iterator */
	/********************************/

	/**
	 * Create a new lookahead iterator for the given language and parse state.
	 *
	 * This returns `NULL` if state is invalid for the language.
	 *
	 * Repeatedly using [`lookahead_iterator_next`] and
	 * [`lookahead_iterator_current_symbol`] will generate valid symbols in the
	 * given parse state. Newly created lookahead iterators will contain the `ERROR`
	 * symbol.
	 *
	 * Lookahead iterators can be useful to generate suggestions and improve syntax
	 * error diagnostics. To get symbols valid in an ERROR node, use the lookahead
	 * iterator on its first leaf node state. For `MISSING` nodes, a lookahead
	 * iterator created on the previous non-extra leaf node may be appropriate.
	 *
	 * TSLookaheadIterator *ts_lookahead_iterator_new(const TSLanguage *self, TSStateId state);
	 */
	lookahead_iterator_new :: proc(self: ^Language, state: State_Id) -> ^Lookahead_Iterator ---
	
	/**
	 * Delete a lookahead iterator freeing all the memory used.
	 *
	 * void ts_lookahead_iterator_delete(TSLookaheadIterator *self);
	 */
	lookahead_iterator_delete :: proc(self: ^Lookahead_Iterator) ---

	/**
	 * Reset the lookahead iterator to another state.
	 *
	 * This returns `true` if the iterator was reset to the given state and `false`
	 * otherwise.
	 *
	 * bool ts_lookahead_iterator_reset_state(TSLookaheadIterator *self, TSStateId state);
	 */
	lookahead_iterator_reset_state :: proc(self: ^Lookahead_Iterator, state: State_Id) -> bool ---

	/**
	 * Reset the lookahead iterator.
	 *
	 * This returns `true` if the language was set successfully and `false`
	 * otherwise.
	 *
	 * bool ts_lookahead_iterator_reset(TSLookaheadIterator *self, const TSLanguage *language, TSStateId state);
	 */
	lookahead_iterator_reset :: proc(self: ^Lookahead_Iterator, language: ^Language, state: State_Id) -> bool ---

	/**
	 * Get the current language of the lookahead iterator.
	 *
	 * const TSLanguage *ts_lookahead_iterator_language(const TSLookaheadIterator *self);
	 */
	lookahead_iterator_language :: proc(self: ^Lookahead_Iterator) -> ^Language ---

	/**
	 * Advance the lookahead iterator to the next symbol.
	 *
	 * This returns `true` if there is a new symbol and `false` otherwise.
	 *
	 * bool ts_lookahead_iterator_next(TSLookaheadIterator *self);
	 */
	lookahead_iterator_next :: proc(self: ^Lookahead_Iterator) -> bool ---

	/**
	 * Get the current symbol of the lookahead iterator;
	 *
	 * TSSymbol ts_lookahead_iterator_current_symbol(const TSLookaheadIterator *self);
	 */
	lookahead_iterator_current_symbol :: proc(self: ^Lookahead_Iterator) -> Symbol ---

	/**
	 * Get the current symbol type of the lookahead iterator as a null terminated
	 * string.
	 *
	 * const char *ts_lookahead_iterator_current_symbol_name(const TSLookaheadIterator *self);
	 */
	lookahead_iterator_current_symbol_name :: proc(self: ^Lookahead_Iterator) -> cstring ---
}

/*************************************/
/* Section - WebAssembly Integration */
/************************************/

// typedef struct wasm_engine_t TSWasmEngine;
// typedef struct TSWasmStore TSWasmStore;
Wasm_Engine :: distinct struct{}
Wasm_Store  :: distinct struct{}

Wasm_Error_Kind :: enum i32 {
	None = 0,
	Parse,
	Compile,
	Instantiate,
	Allocate,
}

Wasm_Error :: struct {
	kind:    Wasm_Error_Kind,
	message: cstring,
}

@(link_prefix="ts_")
foreign ts {
	/**
	 * Create a Wasm store.
	 *
	 * TSWasmStore *ts_wasm_store_new(TSWasmEngine *engine, TSWasmError *error);
	 */
	wasm_store_new :: proc(engine: ^Wasm_Engine, error: ^Wasm_Error) -> ^Wasm_Store ---

	/**
	 * Free the memory associated with the given Wasm store.
	 *
	 * void ts_wasm_store_delete(TSWasmStore *);
	 */
	wasm_store_delete :: proc(self: ^Wasm_Store) ---

	/**
	 * Create a language from a buffer of Wasm. The resulting language behaves
	 * like any other Tree-sitter language, except that in order to use it with
	 * a parser, that parser must have a Wasm store. Note that the language
	 * can be used with any Wasm store, it doesn't need to be the same store that
	 * was used to originally load it.
	 *
	 * const TSLanguage *ts_wasm_store_load_language(TSWasmStore *, const char *name, const char *wasm, uint32_t wasm_len, TSWasmError *error);
	 */
	@(link_name="ts_wasm_store_load_language")
	_wasm_store_load_language :: proc(self: ^Wasm_Store, name: cstring, wasm: cstring, wasm_len: u32, error: ^Wasm_Error) -> ^Language ---

	/**
	 * Check if the language came from a Wasm module. If so, then in order to use
	 * this langauge with a Parser, that parser must have a Wasm store assigned.
	 *
	 * bool ts_language_is_wasm(const TSLanguage *);
	 */
	language_is_wasm :: proc(self: ^Language) -> bool ---

	/**
	 * Assign the given Wasm store to the parser. A parser must have a Wasm store
	 * in order to use Wasm languages.
	 *
	 * void ts_parser_set_wasm_store(TSParser *, TSWasmStore *);
	 */
	parser_set_wasm_store :: proc(self: ^Parser, store: ^Wasm_Store) ---

	/**
	 * Remove the parser's current Wasm store and return it. This returns NULL if
	 * the parser doesn't have a Wasm store.
	 *
	 * TSWasmStore *ts_parser_take_wasm_store(TSParser *);
	 */
	parser_take_wasm_store :: proc(self: ^Parser) -> ^Wasm_Store ---
}

/**********************************/
/* Section - Global Configuration */
/**********************************/

@(link_prefix="ts_")
foreign ts {
	/**
	 * Set the allocation functions used by the library.
	 *
	 * By default, Tree-sitter uses the standard libc allocation functions,
	 * but aborts the process when an allocation fails. This function lets
	 * you supply alternative allocation functions at runtime.
	 *
	 * If you pass `NULL` for any parameter, Tree-sitter will switch back to
	 * its default implementation of that function.
	 *
	 * If you call this function after the library has already been used, then
	 * you must ensure that either:
	 *  1. All the existing objects have been freed.
	 *  2. The new allocator shares its state with the old one, so it is capable
	 *     of freeing memory that was allocated by the old allocator.
	 *
	 * void ts_set_allocator(void *(*new_malloc)(size_t), void *(*new_calloc)(size_t, size_t), void *(*new_realloc)(void *, size_t), void (*new_free)(void *));
	 */
	set_allocator :: proc(
		new_malloc:  (proc(uint) -> rawptr),
		new_calloc:  (proc(uint, uint) -> rawptr),
		new_realloc: (proc(rawptr, uint) -> rawptr),
		new_free:    (proc(rawptr)),
	) ---
}

// /**************************/
// /* Section - Highlighting */
// /**************************/
//
// when BIND_HIGHLIGHT {
//
// 	Highlight_Error :: enum i32 {
// 		Ok,
// 		Unknown_Scope,
// 		Timeout,
// 		Invalid_Language,
// 		Invalid_UTF8,
// 		Invalid_Regex,
// 		Invalid_Query,
// 	}
//
// 	Highlighter      :: distinct struct{}
// 	Highlight_Buffer :: distinct struct{}
// 	
// 	@(link_prefix="ts_")
// 	foreign ts {
// 		/**
// 		 * Construct a `Highlighter` by providing a list of strings containing
// 		 * the HTML attributes that should be applied for each highlight value.
// 		 */
// 		@(link_name="ts_highlighter_new")
// 		_highlighter_new :: proc(highlight_names: [^]cstring, attribute_strings: [^]cstring, highlight_count: u32) -> ^Highlighter ---
//
// 		/**
// 		 * Delete a syntax highlighter.
// 		 */
// 		highlighter_delete :: proc(self: ^Highlighter) ---
// 		
// 		/**
// 		 * Add a `Language` to a highlighter. The language is associated with a
// 		 * scope name, which can be used later to select a language for syntax
// 		 * highlighting. Along with the language, you must provide a JSON string
// 		 * containing the compiled PropertySheet to use for syntax highlighting
// 		 * with that language. You can also optionally provide an 'injection regex',
// 		 * which is used to detect when this language has been embedded in a document
// 		 * written in a different language.
// 		 *
// 		 * TSHighlightError ts_highlighter_add_language(
// 		 *   TSHighlighter *self,
// 		 *   const char *language_name,
// 		 *   const char *scope_name,
// 		 *   const char *injection_regex,
// 		 *   const TSLanguage *language,
// 		 *   const char *highlight_query,
// 		 *   const char *injection_query,
// 		 *   const char *locals_query,
// 		 *   uint32_t highlight_query_len,
// 		 *   uint32_t injection_query_len,
// 		 *   uint32_t locals_query_len,
// 		 *   bool apply_all_captures
// 		 * );
// 		 */
// 		@(link_name="ts_highlighter_add_language")
// 		_highlighter_add_language :: proc(
// 			self: ^Highlighter,
// 			language_name: cstring,
// 			scope_name: cstring,
// 			injection_regex: cstring,
// 			language: ^Language,
// 			highlight_query: cstring,
// 			injection_query: cstring,
// 			locals_query: cstring,
// 			highlights_query_len: u32,
// 			injection_query_len: u32,
// 			locals_query_len: u32,
// 			apply_all_captures: bool,
// 		) -> Highlight_Error ---
// 		
// 		/**
// 		 * Compute syntax highlighting for a given document. You must first
// 		 * create a `HighlightBuffer` to hold the output.
// 		 *
// 		 * TSHighlightError ts_highlighter_highlight(
// 		 *   const TSHighlighter *self,
// 		 *   const char *scope_name,
// 		 *   const char *source_code,
// 		 *   uint32_t source_code_len,
// 		 *   TSHighlightBuffer *output,
// 		 *   const size_t *cancellation_flag
// 		 * );
// 		 */
// 		@(link_name="ts_highlighter_highlight")
// 		_highlighter_highlight :: proc(
// 			self: ^Highlighter,
// 			scope_name: cstring,
// 			source_code: cstring,
// 			source_code_len: u32,
// 			output: ^Highlight_Buffer,
// 			cancellation_flag: ^uint,
// 		) -> Highlight_Error ---
// 		
// 		/**
// 		 * HighlightBuffer: This struct stores the HTML output of syntax
// 		 * highlighting. It can be reused for multiple highlighting calls.
// 		 *
// 		 * TSHighlightBuffer *ts_highlight_buffer_new();
// 		 */
// 		highlight_buffer_new :: proc() -> ^Highlight_Buffer ---
//
// 		/**
// 		 * Delete a highlight buffer.
// 		 *
// 		 * void ts_highlight_buffer_delete(TSHighlightBuffer *);
//          */
// 		highlight_buffer_delete :: proc(self: ^Highlight_Buffer) ---
//
// 		/**
// 		 * Access the HTML content of a highlight buffer.
// 		 *
// 		 * const uint8_t *ts_highlight_buffer_content(const TSHighlightBuffer *);
// 		 * const uint32_t *ts_highlight_buffer_line_offsets(const TSHighlightBuffer *);
// 		 * uint32_t ts_highlight_buffer_len(const TSHighlightBuffer *);
// 		 * uint32_t ts_highlight_buffer_line_count(const TSHighlightBuffer *);
// 		 */
// 		highlight_buffer_content      :: proc(self: ^Highlight_Buffer) -> cstring ---
// 		highlight_buffer_line_offsets :: proc(self: ^Highlight_Buffer) -> [^]u32  ---
// 		highlight_buffer_len          :: proc(self: ^Highlight_Buffer) -> u32     ---
// 		highlight_buffer_line_count   :: proc(self: ^Highlight_Buffer) -> u32     ---
// 	}
// }
