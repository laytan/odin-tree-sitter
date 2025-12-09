package ts_build

import    "core:fmt"
import    "core:log"
import    "core:path/filepath"
import    "core:strings"
import os "core:os/os2"

_install :: proc(opts: Install_Opts) -> bool {
	paths   := paths()
	lib_dir := filepath.join({paths.repo_dir, "tree-sitter"})

	if os.exists(lib_dir) {
		if (confirm("tree-sitter already exists, reinstall", opts.clean) or_return) {
			rmrf(lib_dir)
		} else {
			return false
		}
	}

	exec("git", "clone", opts.repo, "--depth=1", strings.concatenate({"--branch=", opts.branch}), "tmp-tree-sitter") or_return
	defer rmrf("tmp-tree-sitter")

	/* cc -I/lib/include -I/lib/src -I/lib/src/wasm -O3 -c lib/src/lib.c */
	{
		cmd: [dynamic]string

		include_dir := filepath.join({ "tmp-tree-sitter", "lib", "include" })
		src_dir     := filepath.join({ "tmp-tree-sitter", "lib", "src" })
		wasm_dir    := filepath.join({ "tmp-tree-sitter", "lib", "src", "wasm" })

		when ODIN_OS == .Windows {
			append(&cmd, "/Ox")
			append(&cmd, "/EHsc")
			append(&cmd, "/c")

			append(&cmd, fmt.tprintf("/I%s", include_dir))
			append(&cmd, fmt.tprintf("/I%s", src_dir))
			append(&cmd, fmt.tprintf("/I%s", wasm_dir))

			if opts.debug {
				append(&cmd, "/Z7")
			}
		} else {
			append(&cmd, "-O3")
			append(&cmd, "-c")

			append(&cmd, fmt.tprintf("-I%s", include_dir))
			append(&cmd, fmt.tprintf("-I%s", src_dir))
			append(&cmd, fmt.tprintf("-I%s", wasm_dir))

			when ODIN_OS == .Darwin {
				append(&cmd, fmt.tprintf("-mmacosx-version-min=%s", opts.minimum_os_version))
			}

			if opts.debug {
				append(&cmd, "-g")
			}
		}
		append(&cmd, filepath.join({"tmp-tree-sitter", "lib", "src", "lib.c"}))

		compile(&cmd) or_return
	}
	defer rm_file("lib.obj" when ODIN_OS == .Windows else "lib.o")

	/* ar cr libtree-sitter.a lib.o */
	{
		cmd: [dynamic]string

		when ODIN_OS == .Windows {
			append(&cmd, "/OUT:libtree-sitter.lib")
			append(&cmd, "lib.obj")
		} else {
			append(&cmd, "cr")
			append(&cmd, "libtree-sitter.a")
			append(&cmd, "lib.o")
		}

		archive(&cmd) or_return
	}

	if err := os.make_directory_all(lib_dir); err != nil && err != .Exist {
		log.errorf("could not make directory %q", lib_dir)
		return false
	}

	when ODIN_OS == .Windows {
		cp_file("libtree-sitter.lib", filepath.join({lib_dir, "libtree-sitter.lib"}), rm_src=true) or_return
	} else {
		cp_file("libtree-sitter.a", filepath.join({lib_dir, "libtree-sitter.a"}), rm_src=true) or_return

		if ODIN_OS == .Darwin && opts.debug {
			/* dsymutil lib.o $lib_dir/libtree-sitter.dSYM */
			exec("dsymutil", "lib.o", "-o", filepath.join({lib_dir, "libtree-sitter.dSYM"})) or_return
		}
	}

	cp_file("tmp-tree-sitter/LICENSE", filepath.join({lib_dir, "LICENSE"})) or_return

	log.info("successfully installed tree-sitter")
	return true
}

_install_parser :: proc(opts: Install_Parser_Opts) -> (ok: bool) {
	parser := opts.parser

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

	exec("git", "clone", "--depth=1", parser, pp.tmp_dir) or_return
	defer rmrf(pp.tmp_dir)

	// Section can probably be used by other langs.
	c_files:  [dynamic]string
	ar_files: [dynamic]string

	cwd, err := os.getwd(context.allocator)
	if err != nil {
		log.errorf("failed retrieving working directory: %v", os.error_string(err))
		return false
	}

	{
		scanner_path := filepath.join({pp.tmp_dir, opts.path, "src", "scanner.c"})
		if os.exists(scanner_path) {
			append(&c_files, scanner_path)
			when ODIN_OS == .Windows {
				append(&ar_files, filepath.join({cwd, "scanner.obj"}))
			} else {
				append(&ar_files, filepath.join({cwd, "scanner.o"}))
			}
		}

		parser_path := filepath.join({pp.tmp_dir, opts.path, "src", "parser.c"})
		if os.exists(parser_path) {
			append(&c_files, parser_path)
			when ODIN_OS == .Windows {
				append(&ar_files, filepath.join({cwd, "parser.obj"}))
			} else {
				append(&ar_files, filepath.join({cwd, "parser.o"}))
			}
		}

		if len(c_files) == 0 {
			log.errorf("no c source files found, looked for %q and %q", parser_path, scanner_path)
			return false
		}
	}

	/* cc -c -I/src src/scanner.c src/parser.c */
	{
		cmd: [dynamic]string

		src_dir := filepath.join({pp.tmp_dir, opts.path, "src"})

		when ODIN_OS == .Windows {
			append(&cmd, "/Ox")
			append(&cmd, "/EHsc")
			append(&cmd, "/c")
			append(&cmd, fmt.tprintf("/I%s", src_dir))

			if opts.debug {
				append(&cmd, "/Z7")
			}
		} else {
			append(&cmd, "-O3")
			append(&cmd, fmt.tprintf("-I%s", src_dir))
			append(&cmd, "-c")

			when ODIN_OS == .Darwin {
				append(&cmd, fmt.tprintf("-mmacosx-version-min=%s", opts.minimum_os_version))
			}

			if opts.debug {
				append(&cmd, "-g")
			}
		}
		append(&cmd, ..c_files[:])

		compile(&cmd) or_return
	}
	defer { for af in ar_files do rm_file(af) }

	/* ar cr parser.a parser.o scanner.o */
	{
		cmd: [dynamic]string

		when ODIN_OS == .Windows {
			append(&cmd, fmt.tprintf("/OUT:%s", pp.tmp_parser_path))
		} else {
			append(&cmd, "cr")
			append(&cmd, pp.tmp_parser_path)
		}
		append(&cmd, ..ar_files[:])

		archive(&cmd) or_return
	}

	if merr := os.make_directory_all(parser_dir); merr != nil {
		log.errorf("could not make directory %q: %v", parser_dir, os.error_string(merr))
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

	when ODIN_OS == .Windows {
		cp_file(pp.tmp_parser_path, filepath.join({parser_dir, "parser.lib"}))
	} else {
		cp_file(pp.tmp_parser_path, filepath.join({parser_dir, "parser.a"}))

		if ODIN_OS == .Darwin && opts.debug {
			/* dsymutil parser.o scanner.o -o parser.dSYM */
			cmd: [dynamic]string
			append(&cmd, "dsymutil")
			append(&cmd, ..ar_files[:])
			append(&cmd, "-o")
			append(&cmd, filepath.join({parser_dir, "parser.dSYM"}))
			exec(..cmd[:]) or_return
		}
	}

	// Try to find queries - first at {path}/queries, then fallback to root queries/
	queries_src := filepath.join({pp.tmp_dir, opts.path, "queries"})
	if !os.exists(queries_src) && opts.path != "" {
		queries_src = filepath.join({pp.tmp_dir, "queries"})
	}
	has_queries := cp(queries_src, filepath.join({parser_dir, "queries"}))

	buf := strings.builder_make()
	fmt.sbprintf(&buf, BINDINGS, name)

	if has_queries {
		queries_dir := filepath.join({parser_dir, "queries"})

		queries_fd, errno := os.open(queries_dir, os.O_RDONLY)
		if errno != nil {
			log.errorf("could not open queries directory %q in parser repo: %v", queries_dir, os.error_string(errno))
			return false
		}
		defer os.close(queries_fd)


		iter := os.read_directory_iterator_create(queries_fd)
		defer os.read_directory_iterator_destroy(&iter)

		for info in os.read_directory_iterator(&iter) {
			if !strings.has_suffix(info.name, ".scm") {
				return false
			}

			type     := strings.trim_suffix(info.name, ".scm")
			constant := strings.to_screaming_snake_case(type)
			rel      := fmt.tprintf("queries/%s", info.name)

			ws :: strings.write_string
			ws(&buf, constant)
			ws(&buf, " :: #load(\"")
			ws(&buf, rel)
			ws(&buf, "\", string)\n\n")
		}
	}

	bindings_path := filepath.join({parser_dir, strings.concatenate({name, ".odin"})})
	if werr := os.write_entire_file(bindings_path, buf.buf[:]); werr != nil {
		log.errorf("failed writing bindings: %v", os.error_string(werr))
		return false
	}
	log.infof("successfully installed the %v parser", name)
	return true
}
