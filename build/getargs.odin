package ts_build

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:slice"
import "core:strings"

args_consume :: proc(v: any, args: []string) -> (unused: []string, ok: bool) {
	v := v

	if v == nil || v.id == nil {
		panic("args container can't be nil")
	}

	v = reflect.any_base(v)
	ti := type_info_of(v.id)
	if !reflect.is_pointer(ti) || ti.id == rawptr {
		panic("args container must be a pointer")
	}

	v = any{(^rawptr)(v.data)^, ti.variant.(reflect.Type_Info_Pointer).elem.id}	

	dargs := slice.to_dynamic(args)
	ok = args_consume_value(v, &dargs, "")
	unused = dargs[:]
	return
}

@(private="file")
args_consume_value :: proc(v: any, args: ^[dynamic]string, name: string) -> bool {
	short := fmt.tprintf("-%s", name[0:1] if len(name) > 0 else " ")

	long := strings.to_kebab_case(name, context.temp_allocator)
	long = fmt.tprintf("--%s", long)

	ti := reflect.type_info_base(type_info_of(v.id))
	#partial switch t in ti.variant {
	case reflect.Type_Info_Struct:
		for name, i in t.names {	
			id := t.types[i].id
			data := rawptr(uintptr(v.data) + t.offsets[i])
			field_any := any{data, id}
			args_consume_value(field_any, args, name) or_return
		}
	case reflect.Type_Info_String:
		switch &dest in v {
		case string:
			for arg, argi in args {
				match: string
				val: string
				switch {
				case strings.has_prefix(arg, long):
					match = long
					val = strings.trim_prefix(arg, long)
				case strings.has_prefix(arg, short):
					match = short
					val = strings.trim_prefix(arg, short)
				}

				if match == "" do continue
				
				ordered_remove(args, argi)

				switch {
				case len(val) > 0 && val[0] == '=':
					dest = val[1:]
				case len(args) > argi && len(args[argi]) > 0 && args[argi][0] != '-':
					dest = args[argi]
					ordered_remove(args, argi)
				case:
					log.errorf("no value given for argument %q", match)
					return false
				}
				break
			}
		case: panic("unimplemented string type")
		}
	case reflect.Type_Info_Boolean:
		switch &dest in v {
		case bool:
			for arg, argi in args {
				switch {
				case strings.has_prefix(arg, long):
					dest = true
					ordered_remove(args, argi)
				case strings.has_prefix(arg, short):
					dest = true
					ordered_remove(args, argi)
				}
			}
		case: panic("unimplemented bool type")
		}
	case: panic("unimplemented args container type")
	}
	return true
}
