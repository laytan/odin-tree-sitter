package ts

// This file adds helpers and convenience procedures.

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

@(private)
alloc_context: runtime.Context

/*
Set the allocator used by tree-sitter to one managed by Odin.

NOTE: `.Resize` in Odin is used for `realloc`, but Odin's allocators rely on having an `old_size`
passed through. Tree Sitter does not give this to us though.

WARN: the allocator you give this must not require `old_size` on resizes. Use the `Compat_Allocator` in this package!
*/
set_odin_allocator :: proc(allocator := context.allocator) {
	odin_malloc :: proc "c" (size: uint) -> rawptr {
		context = alloc_context
		addr, err := runtime.mem_alloc_non_zeroed(int(size))
		if err != nil {
			fmt.panicf("tree-sitter malloc could not be satisfied: %v", err)
		}
		return raw_data(addr)
	}

	odin_calloc :: proc "c" (num: uint, size: uint) -> rawptr {
		context = alloc_context
		addr, err := runtime.mem_alloc(int(num)*int(size))
		if err != nil {
			fmt.panicf("tree-sitter calloc could not be satisfied: %v", err)
		}
		return raw_data(addr)
	}

	odin_realloc :: proc "c" (ptr: rawptr, size: uint) -> rawptr {
		context = alloc_context
		addr, err := runtime.mem_resize(ptr, -1, int(size))
		if err != nil {
			fmt.panicf("tree-sitter realloc could not be satisfied: %v", err)
		}
		return raw_data(addr)
	}

	odin_free :: proc "c" (ptr: rawptr) {
		context = alloc_context
		runtime.mem_free(ptr)
	}

	alloc_context = context
	alloc_context.allocator = allocator
	set_allocator(odin_malloc, odin_calloc, odin_realloc, odin_free)
}

Compat_Allocator      :: mem.Compat_Allocator
compat_allocator_init :: mem.compat_allocator_init
compat_allocator      :: mem.compat_allocator

// NOTE: even though there is nothing printed when the log level is higher, tree-sitter still formats
// all the log messages, this has huge overhead so you should probably only set this if you actually
// have the log level of it.
parser_set_odin_logger :: proc(self: Parser, logger: ^runtime.Logger, $level: runtime.Logger_Level) {
	if logger == nil {
		parser_set_logger(self, Logger{})
		return
	}

	tree_sitter_log :: proc "c" (payload: rawptr, log_type: Log_Type, buffer: cstring) {
		context = runtime.default_context()
		context.logger = (^runtime.Logger)(payload)^
		if level < context.logger.lowest_level {
			return
		}

		buf: [1024]byte = ---
		str := fmt.bprintf(buf[:], "%v - %s", log_type, buffer)

		context.logger.procedure(context.logger.data, level, str, context.logger.options)
		if len(str) == len(buf) {
			context.logger.procedure(context.logger.data, .Error, "tree-sitter log exceeded 1kib and could not be fully printed", context.logger.options)
		}
	}

	parser_set_logger(self, Logger{
		payload = logger,
		log     = tree_sitter_log,
	})
}

node_text :: proc(self: Node, source: string) -> string {
	return source[node_start_byte(self):node_end_byte(self)]
}

// Iterates over the predicates by subslicing them split by the .Done type.
predicates_iter :: proc(preds: ^[]Query_Predicate_Step) -> ([]Query_Predicate_Step, bool) {
	if len(preds) == 0 {
		return nil, false
	}

	n := 0
	for pred in preds {
		if pred.type == .Done {
			break
		}
		n += 1
	}

	pred := preds[:n]
	preds^ = preds[n+1:]
	return pred, true
}

File_Input :: struct {
	fh:  os.Handle,
	buf: []byte,
	ctx: runtime.Context,
}

file_input :: proc(fi: ^File_Input, fh: os.Handle, buf: []byte, encoding: Input_Encoding = .UTF8) -> Input {
	fi.fh = fh
	fi.buf = buf
	fi.ctx = context
	return Input{
		payload  = fi,
		read     = proc "c" (payload: rawptr, off: u32, _: Point, read: ^u32) -> cstring {
			fi := (^File_Input)(payload)
			context = fi.ctx

			n, err := os.read_at(fi.fh, fi.buf, i64(off))
			if err != nil {
				log.warnf("read error: %v", err)
			}

			read^ = u32(n)
			fi.buf[n] = 0
			return cstring(raw_data(fi.buf))
		},
		encoding = encoding,
	}
}
