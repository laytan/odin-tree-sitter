package ts

// This file adds helpers and convenience procedures.

import "core:mem"
import "core:runtime"
import "core:fmt"
import "core:sync"

@(private)
alloc_context: runtime.Context

// Set the allocator used by tree-sitter to one managed by Odin.
//
// NOTE: `.Resize` in Odin is used for `realloc`, but Odin's allocators rely on having an `old_size`
// passed through. Tree Sitter does not give this to us though.
// The default heap allocator will thus be (probably) the only allocator to work out of the box here.
// If you get segfaults, you can opt to use the `Compat_Allocator` in this package, it will keep the
// allocated sizes in a map to pass along, you can imagine this adds some overhead.
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
		// `old_size` of `max(int)` prohibits the default allocator from zeroing the region.
		// Other allocators can be wrapped by the `Compat_Allocator` in this package to keep track
		// of allocation sizes to pass along.
		addr, err := runtime.mem_resize(ptr, max(int), int(size))
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
Compat_Allocator :: struct {
	sizes:  map[rawptr]int,
	parent: mem.Allocator,
	mu:     sync.Mutex,
}

compat_allocator_init :: proc(rra: ^Compat_Allocator, allocator := context.allocator, sizes_allocator := context.allocator) {
	rra.parent = allocator
	rra.sizes  = make(map[rawptr]int, allocator=sizes_allocator)
}

compat_allocator :: proc(rra: ^Compat_Allocator) -> mem.Allocator {
	return mem.Allocator{
		data      = rra,
		procedure = compat_allocator_proc,
	}
}

compat_allocator_destroy :: proc(rra: ^Compat_Allocator) {
	delete(rra.sizes)
}

@(private)
compat_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
                             size, alignment: int,
                             old_memory: rawptr, old_size: int,
                             location := #caller_location) -> (data: []byte, err: mem.Allocator_Error) {
	rra := (^Compat_Allocator)(allocator_data)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		data, err = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)
		if err == nil {
			sync.guard(&rra.mu)
			rra.sizes[raw_data(data)] = size
		}
		return

	case .Free:
		{
			sync.guard(&rra.mu)
			delete_key(&rra.sizes, old_memory)
		}
		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)

	case .Resize:
		stored_old_size: int; {
			sync.guard(&rra.mu)

			if stored, has_stored := rra.sizes[old_memory]; has_stored {
				stored_old_size = stored
				delete_key(&rra.sizes, old_memory)
			} else {
				stored_old_size = old_size
			}
		}

		data, err = rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, stored_old_size, location)
		if err == nil {
			sync.guard(&rra.mu)
			rra.sizes[raw_data(data)] = size
		}
		return

	case:
		return rra.parent.procedure(rra.parent.data, mode, size, alignment, old_memory, old_size, location)
	}
}

parser_set_odin_logger :: proc(self: ^Parser, logger: ^runtime.Logger, $level: runtime.Logger_Level) {
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
