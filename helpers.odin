package ts

// This file adds helpers and convenience procedures.

import "core:mem"
import "core:runtime"
import "core:fmt"

@(private)
alloc_context: runtime.Context

/*
Set the allocator used by tree-sitter to one managed by Odin.

NOTE: `.Resize` in Odin is used for `realloc`, but Odin's allocators rely on having an `old_size`
passed through. Tree Sitter does not give this to us though.
The default heap allocator will thus be (probably) the only allocator to work out of the box here.
If you get segfaults, you can opt to use the `Compat_Allocator` in this package, it will keep the
allocated sizes in an 8 byte header before each allocation, and passes this along to the actual allocator.
*/
set_odin_allocator :: proc(allocator := context.allocator) {
	odin_malloc :: proc "c" (size: uint) -> rawptr {
		context = alloc_context
		addr, err := runtime.mem_alloc_non_zeroed(int(size), 16)
		if err != nil {
			fmt.panicf("tree-sitter malloc could not be satisfied: %v", err)
		}
		return raw_data(addr)
	}

	odin_calloc :: proc "c" (num: uint, size: uint) -> rawptr {
		context = alloc_context
		addr, err := runtime.mem_alloc(int(num)*int(size), 16)
		if err != nil {
			fmt.panicf("tree-sitter calloc could not be satisfied: %v", err)
		}
		return raw_data(addr)
	}

	odin_realloc :: proc "c" (ptr: rawptr, size: uint) -> rawptr {
		context = alloc_context
		// `old_size` of `max(int)` prohibits the default allocator from zeroing the region.
		// Other allocators can be wrapped by the `Compat_Allocator` in this package to keep track
		// of allocation sizes to pass along.
		addr, err := runtime.mem_resize(ptr, max(int), int(size), 16)
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
// This is most allocators, although the default heap allocator seems to work normally without this
// wrapping allocator.
//
// The overhead of this allocator is an extra 8 bytes allocated for each allocation, these bytes are
// used as an i64 to store the allocation size.
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
	Header :: struct {
		size: i64,
	}

	rra := (^Compat_Allocator)(allocator_data)
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		assert(alignment == 16)
		alignment := 8

		size := size
		size += size_of(Header)

		data = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location) or_return

		header := cast(^Header)(raw_data(data))
		header.size = i64(size)

		data = data[size_of(Header):]
		return

	case .Free:
		header := cast(^Header)(uintptr(old_memory)-size_of(Header))

		old_size   := int(header.size)
		old_memory := header

		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)

	case .Resize:
		assert(alignment == 16)
		alignment := 8

		header := cast(^Header)(uintptr(old_memory)-size_of(Header))

		size       := size + size_of(Header)
		old_size   := int(header.size)
		old_memory := header

		data = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location) or_return

		header = cast(^Header)(raw_data(data))
		header.size = i64(size)

		data = data[size_of(Header):]
		return

	case .Free_All, .Query_Info, .Query_Features:
		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)

	case: unreachable()
	}
}

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
