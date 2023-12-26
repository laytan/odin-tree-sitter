//+build !windows
package ts_build

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

_WSTATUS    :: proc(x: i32) -> i32  { return x & 0177 }
WIFEXITED   :: proc(x: i32) -> bool { return _WSTATUS(x) == 0 }
WEXITSTATUS :: proc(x: i32) -> i32  { return (x >> 8) & 0x000000ff }

_install :: proc(opts: Install_Opts) -> bool {
	if opts.clean do rmrf("tmp-tree-sitter")

	exec(fmt.ctprintf("git clone %s --depth=1 --branch=%s tmp-tree-sitter", opts.repo, opts.branch)) or_return
	defer rmrf("tmp-tree-sitter")

	cflags := strings.builder_make()
	when ODIN_OS == .Darwin {
		strings.write_string(&cflags, "-mmacosx-version-min=")
		strings.write_string(&cflags, opts.minimum_os_version)
		strings.write_string(&cflags, " ")
	}

	if opts.debug {
		strings.write_string(&cflags, "-g ")
	}

	exec(fmt.ctprintf("CFLAGS=%q make -C tmp-tree-sitter libtree-sitter.a", strings.to_string(cflags))) or_return

	paths   := paths()
	lib_dir := filepath.join({paths.repo_dir, "tree-sitter"})
	
	if errno := os.make_directory(lib_dir); errno != 0 && errno != os.EEXIST {
		log.errorf("could not make directory %q", lib_dir)
		return false
	}

	cp_file("tmp-tree-sitter/libtree-sitter.a", filepath.join({lib_dir, "libtree-sitter.a"})) or_return
	cp_file("tmp-tree-sitter/LICENSE",          filepath.join({lib_dir, "LICENSE"         })) or_return

	return true
}

_install_parser :: proc(parser: string, opts: Install_Parser_Opts) -> (ok: bool) {
	parser := parser

	name := opts.name
	if name == "" {
		name = opts.path
	}
	if name == "" {
		name = name_from_url(parser, opts.yes) or_return
	}

	if !strings.has_suffix(parser, ".git") {
		parser = strings.concatenate({parser, ".git"})
	}

	if !(confirm(fmt.tprintf("URL: %q, language: %q", parser, name), opts.yes) or_return) do return false

	pp := paths()
	parser_dir := filepath.join({pp.parsers_dir, name})
	
	if os.exists(parser_dir) {
		if opts.clean {
			rmrf(parser_dir)
		} else if (confirm("parser already exists, reinstall", opts.yes) or_return) {
			rmrf(parser_dir)
		} else {
			return false
		}
	}

	exec(fmt.ctprintf("git clone --depth=1 %s %s", parser, pp.tmp_dir)) or_return
	defer rmrf(pp.tmp_dir)

	// Section can probably be used by other langs.
	c_files:  [dynamic]string
	ar_files: [dynamic]string
	cwd := os.get_current_directory()
	{
		scanner_path := filepath.join({pp.tmp_dir, opts.path, "src", "scanner.c"})
		if os.exists(scanner_path) {
			append(&c_files, scanner_path)
			append(&ar_files, filepath.join({cwd, "scanner.o"}))
		}

		parser_path := filepath.join({pp.tmp_dir, opts.path, "src", "parser.c"})
		if os.exists(parser_path) {
			append(&c_files, parser_path)
			append(&ar_files, filepath.join({cwd, "parser.o"}))
		}

		if len(c_files) == 0 {
			log.errorf("no c source files found, looked for %q and %q", parser_path, scanner_path)
			return false
		}
	}

	cflags := strings.builder_make()
	when ODIN_OS == .Darwin {
		strings.write_string(&cflags, "-mmacosx-version-min=")
		strings.write_string(&cflags, opts.minimum_os_version)
		strings.write_string(&cflags, " ")
	}

	if opts.debug {
		strings.write_string(&cflags, "-g ")
	}

	exec(fmt.ctprintf(
		"cc -O3 -std=c99 %s -I%s -c %s",
		strings.to_string(cflags),
		filepath.join({pp.tmp_dir, opts.path, "src"}),
		strings.join(c_files[:], " ")),
	) or_return
	defer { for af in ar_files do rm_file(af) }
	
	exec(fmt.ctprintf("ar cr %s %s", pp.tmp_parser_path, strings.join(ar_files[:], " "))) or_return

	if err := os.make_directory(parser_dir); err != 0 {
		log.errorf("could not make directory %q, error code: %i", parser_dir, err)
		return false
	}
	defer { if !ok do rmrf(parser_dir) }

	for lpath, i in ([]string{"LICENSE", "LICENSE.txt", "LICENSE.md", "LICENSE.rst"}) {
		if cp_file(filepath.join({pp.tmp_dir, lpath}), filepath.join({parser_dir, lpath}), try_it=true) {
			break
		} else if i == 3 {
			log.warnf("could not find license at a common path, going on without copying it")
		}
	}

	cp_file(filepath.join({pp.tmp_dir, "README.md"}), filepath.join({parser_dir, "README.md"}), try_it=true)
	cp_file(filepath.join({pp.tmp_dir, "parser.a"}),  filepath.join({parser_dir, "parser.a"}))

	has_queries := cp(filepath.join({pp.tmp_dir, opts.path, "queries"}), filepath.join({parser_dir, "queries"}))

	buf := strings.builder_make()
	fmt.sbprintf(&buf, BINDINGS, name)
	
	if has_queries {
		queries_dir := filepath.join({parser_dir, "queries"})

		queries_fd, errno := os.open(queries_dir, os.O_RDONLY)
		if errno != 0 {
			log.errorf("could not open queries directory %q in parser repo, error number: %v", queries_dir, errno)
			return false
		}
		defer os.close(queries_fd)

		files, dir_errno := os.read_dir(queries_fd, -1)
		if dir_errno != 0 {
			log.errorf("could not read directory contents at %q, error number: %v", queries_dir, dir_errno)
		}

		for info in files {
			if !strings.has_suffix(info.name, ".scm") {
				return false
			}

			type     := strings.trim_suffix(info.name, ".scm")
			constant := strings.to_screaming_snake_case(type)
			rel, _   := filepath.rel(parser_dir, info.fullpath)

			ws :: strings.write_string
			ws(&buf, constant)
			ws(&buf, " :: #load(\"")
			ws(&buf, rel)
			ws(&buf, "\", string)\n\n")
		}
	}
	
	bindings_path := filepath.join({parser_dir, strings.concatenate({name, ".odin"})})
	write_entire_file(bindings_path, buf.buf[:]) or_return
	log.infof("successfully installed the %v parser", name)
	return true
}
