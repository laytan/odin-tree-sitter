package ts_build

import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"

exec :: proc(command: cstring) -> bool {
	log.info(command)
	res := libc.system(command)
	switch {
	case res == -1:
		log.errorf("error spawning command %q", command)
		return false
	case WIFEXITED(res) && WEXITSTATUS(res) == 0:
		return true
	case WIFEXITED(res):
		log.errorf("command %q exited with status code %v", command, WEXITSTATUS(res))
		return false
	case:
		log.error("command %q caused an unknown error", command)
		return false
	}
}

// First implemented this using a recursive thingy, but it fucked up over symlinks.
rmrf :: proc(path: string) -> (ok: bool) {
	when ODIN_OS != .Windows {
		return exec(fmt.ctprintf("rm -rf %q", path))
	} else {
		return exec(fmt.ctprintf("rmdir %q /s /q", path))
	}
}

rm_dir :: proc(path: string) -> bool {
	log.debugf("rm dir %q", path)
	
	// Darwin doesn't have remove_directory???
	when ODIN_OS == .Darwin {
		ok := os.remove(path)
		if !ok { log.errorf("could not remove directory %q", path) }
		return ok
	} else {
		err := os.remove_directory(path)
		if err != 0 { log.errorf("could not remove directory %q, error number: %v", path, err) }
		return err == 0
	}
}

rm_file :: proc(path: string) -> bool {
	log.debugf("rm file %q", path)
	
	// Don't ask me why, but darwin returns bool and others return an error.
	when ODIN_OS == .Darwin {
		ok := os.remove(path)
		if !ok { log.errorf("could not remove file %q", path) }
		return ok
	} else {
		err := os.remove(path)
		if err != 0 { log.errorf("could not remove file %q, error number: %v", path, err) }
		return err == 0
	}
}

cp :: proc(src, dst: string, rm_src := false) -> (ok: bool) {
	info, err := os.lstat(src)
	if err != 0 {
		log.errorf("could not stat %q during copy/move, error number: %v", src, err)
		return false
	}

	if info.is_dir {
		if rm_src {
			log.debugf("moving %q to %q", src, dst)
		} else {
			log.debugf("copying %q to %q", src, dst)
		}

		defer if rm_src {
			if ok do rm_dir(info.fullpath)
		}

		src_fd, src_err := os.open(info.fullpath, os.O_RDONLY)
		if err != 0 {
			log.errorf("could not get file handle for directory %q during copy/move, error number: %v", info.fullpath, src_err)
			return false
		}
		defer os.close(src_fd)

		fi, rerr := os.read_dir(src_fd, -1)
		if rerr != 0 {
			log.errorf("could not read directory contents of %q during copy/move, error number: %v", info.fullpath, rerr)
			return false
		}
		
		log.debugf("making dir %q", dst)
		if err := os.make_directory(dst); err != 0 {
			log.errorf("making directory %q failed, error number: %v", dst, err)
			return false
		}
		defer { if !ok do rm_dir(dst) }
		
		fok := true
		for f in fi {
			_fok := cp(f.fullpath, filepath.join({dst, filepath.base(f.fullpath)}), rm_src)
			if fok { fok = _fok }
		}
		if !fok {
			log.errorf("copying/moving file contents of directory %q to %q failed", src, dst)
			return false
		}
		return true
	}

	if cp_file(src, dst) && rm_src {
		return rm_file(src)
	}
	return true
}

cp_file :: proc(src, dst: string, try_it := false, rm_src := false) -> (ok: bool) {
	if rm_src {
		log.debugf("moving %q to %q", src, dst)
	} else {
		log.debugf("copying %q to %q", src, dst)
	}

	defer if rm_src {
		if ok { ok = rm_file(src) }
	}

	src_data, src_ok := os.read_entire_file(src)
	if !src_ok {
		if try_it {
			log.infof("could not read src file to copy: %q", src)
		} else {
			log.errorf("could not read src file to copy: %q", src)
		}
		return false
	}
	defer delete(src_data)

	write_entire_file(dst, src_data) or_return
	
	return true
}

write_entire_file :: proc(name: string, data: []byte) -> (ok: bool) {
	mode: int = 0
	when ODIN_OS != .Windows {
		mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
	}

	fd, err := os.open(name, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != 0 {
		log.errorf("could not open file to write %q, error number: %v", name, err)
		return false
	}
	defer { if !ok do rm_file(name) }
	defer os.close(fd)

	n: int
	for n < len(data) {
		nn, werr := os.write(fd, data[n:])
		if werr != 0 {
			log.errorf("could not write to file %q, error number: %v", name, werr)
			return false
		}
		n += nn
	}
	return true
}
