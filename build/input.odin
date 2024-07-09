package ts_build

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

ask_for_line :: proc(prompt: string) -> (string, bool) {
	fmt.printf("%s: ", prompt)

	buf: [128]byte = ---
	n: int
	read_loop: for {
		nn, errno := os.read(os.stdin, buf[n:])
		if errno != os.ERROR_NONE {
			log.errorf("could not read user input, error number: %v", errno)
			return "", false
		}
		defer n += nn

		for c in buf[n:n+nn] {
			if c == '\n' {
				break read_loop
			}
		}
	}

	name := strings.clone(strings.trim_space(string(buf[:n])))
	return name, len(name) > 0
}

confirm :: proc(msg: string, skip: bool) -> (bool, bool) {
	if skip do return true, true

	fmt.printf("%s? [y/n]: ", msg)

	buf: [8]byte
	for {
		n, errno := os.read(os.stdin, buf[:])
		if errno != os.ERROR_NONE {
			log.errorf("reading stdin: %v\n", errno)
			return false, false
		}
		if n != 0 do break
	}
	
	switch buf[0] {
	case 'y', 'Y': return true,  true
	case:          return false, true
	}
}

name_from_url :: proc(url: string, skip_input: bool) -> (string, bool) {
	url := url
	url = strings.trim_suffix(url, ".git")
	idx := strings.last_index(url, "tree-sitter-")
	if idx == -1 {
		return ask_for_line("enter the language name")
	}

	name := url[idx+len("tree-sitter-"):]
	confirmation, ok := confirm(fmt.tprintf("detected language name: %q, is that correct", name), skip_input)
	if !ok { return "", false }

	if !confirmation {
		return ask_for_line("enter the language name")
	}
	return name, true
}
