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

// An allocator that keeps track of allocation sizes and passes it along to resizes.
// This is needed because tree-sitter does not pass old size of allocations on reallocs.
//
// You want to wrap your allocator into this one if you are trying to use any allocator that relies
// on the old size to work.
//
// The overhead of this allocator is an extra 2*size_of(rawptr) bytes allocated for each allocation, these bytes are
// used to store the size and padding to keep the returned alignment to 2*size_of(rawptr) bytes.
Compat_Allocator :: struct {
	parent: mem.Allocator,
}

compat_allocator_init :: proc(rra: ^Compat_Allocator, allocator := context.allocator) {
	rra.parent = allocator
}

compat_allocator :: proc(rra: ^Compat_Allocator) -> mem.Allocator {
	return mem.Allocator{
		data      = rra,
		procedure = compat_allocator_proc,
	}
}

@(private)
compat_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
                             size, alignment: int,
                             old_memory: rawptr, old_size: int,
                             location := #caller_location) -> (data: []byte, err: mem.Allocator_Error) {
	size, old_size := size, old_size

	Header :: struct {
		_padding: [size_of(rawptr)]byte, // We want the structure to be 2*size of ptr bytes so the allocation we return is also aligned to 16 bytes.
		size:     uintptr,
	}

	rra := (^Compat_Allocator)(allocator_data)
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		size := size
		size += size_of(Header)

		data = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location) or_return

		header := cast(^Header)(raw_data(data))
		header.size = uintptr(size)

		data = data[size_of(Header):]
		return

	case .Free:
		header := cast(^Header)(uintptr(old_memory)-size_of(Header))

		old_size    = int(header.size)
		old_memory := header

		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)

	case .Resize, .Resize_Non_Zeroed:
		header := cast(^Header)(uintptr(old_memory)-size_of(Header))

		size        = size + size_of(Header)
		old_size    = int(header.size)
		old_memory := header

		data = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location) or_return

		header = cast(^Header)(raw_data(data))
		header.size = uintptr(size)

		data = data[size_of(Header):]
		return

	case .Free_All, .Query_Info, .Query_Features:
		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)

	case: unreachable()
	}
}

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
			if err != 0 {
				log.warnf("read error: %v", err)
			}

			read^ = u32(n)
			fi.buf[n] = 0
			return cstring(raw_data(fi.buf))
		},
		encoding = encoding,
	}
}
