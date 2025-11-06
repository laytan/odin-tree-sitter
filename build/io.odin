package ts_build

import    "core:log"
import    "core:strings"
import os "core:os/os2"

exec :: proc(command: ..string) -> bool {
	log.info(command)

	p, err := os.process_start({
		command = command,
		stdout  = os.stdout,
		stderr  = os.stderr,
	})
	if err != nil {
		log.warnf("starting process: %v", os.error_string(err))
		return false
	}

	state, werr := os.process_wait(p)
	if werr != nil {
		log.errorf("waiting on process: %v", os.error_string(err))
		return false
	}

	if !state.success {
		log.warnf("process exited with status code: %v", state.exit_code)
		return false
	}

	return true
}

compile :: proc(cmd: ^[dynamic]string) -> (ok: bool) {
	tries := []string{"", "cc", "cl", "cl.exe", "gcc", "clang"}

	cc, eok := os.lookup_env("CC", context.temp_allocator)
	if eok { tries[0] = cc }

	inject_at(cmd, 0, "")
	for try in tries {
		cmd[0] = try
		if cmd[0] == ""            do continue
		if ok = exec(..cmd[:]); ok do break
	}

	if !ok {
		log.errorf("failed to compile C code, tried: %s", strings.join(tries, ", "))
	}

	return
}

archive :: proc(cmd: ^[dynamic]string) -> (ok: bool) {
	tries := []string{"", "ar", "lib", "lib.exe"}

	cc, eok := os.lookup_env("AR", context.temp_allocator)
	if eok { tries[0] = cc }

	inject_at(cmd, 0, "")
	for try in tries {
		cmd[0] = try
		if cmd[0] == ""            do continue
		if ok = exec(..cmd[:]); ok do break
	}

	if !ok {
		log.errorf("failed to archive code into library, tried: %s", strings.join(tries, ", "))
	}

	return
}

// First implemented this using a recursive thingy, but it fucked up over symlinks.
rmrf :: proc(path: string) -> (ok: bool) {
	log.debugf("rmrf %q", path)

	err := os.remove_all(path)
	if err != nil {
		log.errorf("failed recursively deleting %q: %v", path, os.error_string(err))
		return false
	}
	return true
}

rm :: proc(path: string) -> bool {
	log.debugf("rm %q", path)

	err := os.remove(path)
	if err != nil {
		log.errorf("failed removing %q: %v", path, os.error_string(err))
		return false
	}

	return true
}

rm_dir  :: rm
rm_file :: rm

cp :: proc(src, dst: string, try_it := false, rm_src := false) -> (ok: bool) {
	log.debugf("cp %q %q", src, dst)

	err := os.copy_directory_all(dst, src)
	if err != nil {
		if try_it {
			log.infof("failed copying %q to %q: %v", src, dst, os.error_string(err))
		} else {
			log.errorf("failed copying %q to %q: %v", src, dst, os.error_string(err))
		}
		return false
	}

	if rm_src {
		if os.is_dir(src) {
			return rmrf(src)
		}

		return rm(src)
	}

	return true
}

cp_file :: cp
