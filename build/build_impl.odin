package ts_build

import    "core:fmt"
import    "core:log"
import    "core:path/filepath"
import    "core:strings"
import os "core:os/os2"

_install :: proc(opts: Install_Opts) -> bool {
	repo_dir := filepath.dir(filepath.dir(#file))
	lib_dir  := filepath.join({repo_dir, "tree-sitter"})

	if os.exists(lib_dir) {
		if (confirm("tree-sitter already exists, reinstall", opts.clean) or_return) {
			rmrf(lib_dir)
		} else {
			return false
		}
	}

	if err := os.make_directory_all(lib_dir); err != nil && err != .Exist {
		log.errorf("could not make directory %q", lib_dir)
		return false
	}

	src_dir := filepath.join({lib_dir, "src"})

	exec("git", "clone", opts.repo, "--depth=1", strings.concatenate({"--branch=", opts.branch}), src_dir) or_return
	// Need source for debugging.
	defer if !opts.debug { rmrf(src_dir) }

	/* cc -I/lib/include -I/lib/src -I/lib/src/wasm -O3 -c lib/src/lib.c */
	{
		cmd: [dynamic]string

		ts_include_dir := filepath.join({ src_dir, "lib", "include" })
		ts_src_dir     := filepath.join({ src_dir, "lib", "src" })
		ts_wasm_dir    := filepath.join({ src_dir, "lib", "src", "wasm" })

		when ODIN_OS == .Windows {
			append(&cmd, "/Ox")
			append(&cmd, "/EHsc")
			append(&cmd, "/c")

			append(&cmd, fmt.tprintf("/I%s", ts_include_dir))
			append(&cmd, fmt.tprintf("/I%s", ts_src_dir))
			append(&cmd, fmt.tprintf("/I%s", ts_wasm_dir))

			if opts.debug {
				append(&cmd, "/Z7")
			}
		} else {
			append(&cmd, "-O3")
			append(&cmd, "-c")

			append(&cmd, fmt.tprintf("-I%s", ts_include_dir))
			append(&cmd, fmt.tprintf("-I%s", ts_src_dir))
			append(&cmd, fmt.tprintf("-I%s", ts_wasm_dir))

			when ODIN_OS == .Darwin {
				append(&cmd, fmt.tprintf("-mmacosx-version-min=%s", opts.minimum_os_version))
			}

			if opts.debug {
				append(&cmd, "-g")
			}
		}
		append(&cmd, filepath.join({ts_src_dir, "lib.c"}))

		compile(&cmd) or_return
	}
	defer rm_file("lib.obj" when ODIN_OS == .Windows else "lib.o")

	/* ar cr libtree-sitter.a lib.o */
	{
		cmd: [dynamic]string

		when ODIN_OS == .Windows {
			append(&cmd, fmt.tprintf("/OUT:%s", filepath.join({ lib_dir, "libtree-sitter.lib" })))
			append(&cmd, "lib.obj")
		} else {
			append(&cmd, "cr")
			append(&cmd, filepath.join({ lib_dir, "libtree-sitter.a" }))
			append(&cmd, "lib.o")
		}

		archive(&cmd) or_return
	}

	if ODIN_OS == .Darwin && opts.debug {
		/* dsymutil lib.o $lib_dir/libtree-sitter.dSYM */
		exec("dsymutil", "lib.o", "-o", filepath.join({lib_dir, "libtree-sitter.dSYM"})) or_return
	}

	cp_file(filepath.join({ src_dir, "LICENSE" }), filepath.join({lib_dir, "LICENSE"})) or_return

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

	repo_dir   := filepath.dir(filepath.dir(#file))
	parser_dir := filepath.join({repo_dir, "parsers", name})

	if os.exists(parser_dir) {
		if opts.clean {
			rmrf(parser_dir)
		} else if (confirm("parser already exists, reinstall", opts.yes) or_return) {
			rmrf(parser_dir)
		} else {
			return false
		}
	}

	if merr := os.make_directory_all(parser_dir); merr != nil {
		log.errorf("could not make directory %q: %v", parser_dir, os.error_string(merr))
		return false
	}
	defer { if !ok do rmrf(parser_dir) }

	src_dir := filepath.join({parser_dir, "src"})

	exec("git", "clone", "--depth=1", parser, src_dir) or_return
	// Need source for debugging.
	defer if !opts.debug { rmrf(src_dir) }

	// Section can probably be used by other langs.
	c_files:  [dynamic]string
	ar_files: [dynamic]string

	cwd, err := os.getwd(context.allocator)
	if err != nil {
		log.errorf("failed retrieving working directory: %v", os.error_string(err))
		return false
	}

	{
		scanner_path := filepath.join({src_dir, opts.path, "src", "scanner.c"})
		if os.exists(scanner_path) {
			append(&c_files, scanner_path)
			when ODIN_OS == .Windows {
				append(&ar_files, filepath.join({cwd, "scanner.obj"}))
			} else {
				append(&ar_files, filepath.join({cwd, "scanner.o"}))
			}
		}

		parser_path := filepath.join({src_dir, opts.path, "src", "parser.c"})
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

		parser_src_dir := filepath.join({src_dir, opts.path, "src"})

		when ODIN_OS == .Windows {
			append(&cmd, "/Ox")
			append(&cmd, "/EHsc")
			append(&cmd, "/c")
			append(&cmd, fmt.tprintf("/I%s", parser_src_dir))

			if opts.debug {
				append(&cmd, "/Z7")
			}
		} else {
			append(&cmd, "-O3")
			append(&cmd, fmt.tprintf("-I%s", parser_src_dir))
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
			append(&cmd, fmt.tprintf("/OUT:%s", filepath.join({ parser_dir, "parser.lib" })))
		} else {
			append(&cmd, "cr")
			append(&cmd, filepath.join({ parser_dir, "parser.a" }))
		}
		append(&cmd, ..ar_files[:])

		archive(&cmd) or_return
	}

	if ODIN_OS == .Darwin && opts.debug {
		/* dsymutil parser.o scanner.o -o parser.dSYM */
		cmd: [dynamic]string
		append(&cmd, "dsymutil")
		append(&cmd, ..ar_files[:])
		append(&cmd, "-o")
		append(&cmd, filepath.join({parser_dir, "parser.dSYM"}))
		exec(..cmd[:]) or_return
	}

	for lpath, i in ([]string{"LICENSE", "LICENSE.txt", "LICENSE.md", "LICENSE.rst"}) {
		if cp_file(filepath.join({src_dir, lpath}), filepath.join({parser_dir, lpath}), try_it=true) {
			break
		} else if i == 3 {
			log.warnf("could not find license at a common path, going on without copying it")
		}
	}

	cp_file(filepath.join({src_dir, "README.md"}), filepath.join({parser_dir, "README.md"}), try_it=true)

	// Try to find queries - first at {path}/queries, then fallback to root queries/
	queries_src := filepath.join({src_dir, opts.path, "queries"})
	if !os.exists(queries_src) && opts.path != "" {
		queries_src = filepath.join({src_dir, "queries"})
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
