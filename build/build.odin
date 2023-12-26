package ts_build

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

print_usage :: proc(fd: os.Handle) {
	w := os.stream_from_handle(fd)
	fmt.wprintf(w, `{0:s} is a tool for installing tree-sitter and its language parsers for use in Odin.
Usage:
	{0:s} command [arguments]
Commands:
	install          Install tree-sitter itself. 
	install-parser   Install a parser.
	help             Show this message.

For further details on a command, invoke the command with the -help flag:
	e.g. {0:s} install -help
`, PROGRAM)
}

HELP_INSTALL :: `Usage:
	{0:s} install [flags]
Flags:
	-help,-h               Show this message.
	-debug,-d              Compile tree-sitter with debug symbols.
	-minimum-os-version,-m The minimum OS version to target (only used on Darwin, default is 12.0.0).
	-branch,-b             Branch of the tree-sitter git repo to install, default is "master".
	-repo,-r               Repo to install, default is "https://github.com/tree-sitter/tree-sitter".
	-clean,-c              First uninstall.
`

HELP_INSTALL_PARSER :: `Usage:
	{0:s} install-parser [git-url]
Example:
	{0:s} install-parser https://github.com/amaanq/tree-sitter-odin
Flags:
	-help,-h               Show this message.
	-debug,-d              Compile parser with debug symbols.
	-minimum-os-version,-m The minimum OS version to target (only used on Darwin, default is 12.0.0).
	-yes,-y                Automatically confirm questions to their defaults (non-interactive) mode.
	-name,-n               Overwrite the language name.
	-clean,-c              First uninstall.
	-path,-p               Subdirectory to compile.
`

main :: proc() {
	context.logger = log.create_console_logger(.Info, {.Level, .Terminal_Color})

	if len(os.args) < 2 {
		print_usage(os.stderr)	
		os.exit(1)
	}

	switch os.args[1] {
	case "help":
		print_usage(os.stdout)
		return
	case "install":
		ok := install(os.args[2:])
		os.exit(0 if ok else 1)
	case "install-parser":
		ok := install_parser(os.args[2:])
		os.exit(0 if ok else 1)
	case:
		log.errorf("unknown command %q", os.args[1])
		print_usage(os.stderr)
		os.exit(1)
	}
}

Install_Opts :: struct {
	help:               bool,
	debug:              bool,
	minimum_os_version: string,
	branch:             string,
	repo:               string,
	clean:              bool,
}

install :: proc(args: []string) -> bool {
	iopts := Install_Opts{
		branch             = "master",
		repo               = "https://github.com/tree-sitter/tree-sitter",
		minimum_os_version = "12.0.0",
	}
	unused := args_consume(&iopts, args) or_return

	if iopts.help {
		fmt.printf(HELP_INSTALL, PROGRAM)
		os.exit(0)
	}

	if len(unused) > 0 {
		log.warnf("unused input %q", strings.join(unused, " "))
	}

	return _install(iopts)
}

Install_Parser_Opts :: struct {
	help:               bool,
	debug:              bool,
	minimum_os_version: string,
	yes:                bool,
	name:               string,
	clean:              bool,
	path:               string,
}

install_parser :: proc(args: []string) -> bool {
	iopts := Install_Parser_Opts{
		minimum_os_version = "12.0.0",
	}
	unused := args_consume(&iopts, args) or_return

	if iopts.help {
		fmt.printf(HELP_INSTALL_PARSER, PROGRAM)
		os.exit(0)
	}

	if len(unused) > 0 {
		parser := unused[0]
		unused = unused[1:]
		if len(unused) > 0 {
			log.warnf("unused input %q", strings.join(unused, " "))
		}
		return _install_parser(parser, iopts)
	}

	log.error("missing git link to parser, please provide it e.g. `build install-parser https://github.com/amaanq/tree-sitter-odin`")
	return false
}

PROGRAM :: "build"

BINDINGS :: `package ts_{0:s}

import ts "../.."

foreign import ts_{0:s} "parser.a"

foreign ts_{0:s} {{
	tree_sitter_{0:s} :: proc() -> ^ts.Language ---
}}

`

Paths :: struct {
	repo_dir:        string, // root of this project/package.
	parsers_dir:     string, // root/parsers.
	tmp_dir:         string, // root/parsers/tmp.
	tmp_parser_path: string, // root/parsers/tmp/parser.a.
}

@(private="file")
_paths: Maybe(Paths)

paths :: proc() -> Paths {
	if pp, ok := _paths.?; ok {
		return pp
	}

	repo_dir        := filepath.dir(filepath.dir(#file))
	parsers_dir     := filepath.join({repo_dir, "parsers"})
	tmp_dir         := filepath.join({parsers_dir, "tmp"})
	tmp_parser_path := filepath.join({tmp_dir, "parser.a"})

	pp := Paths{
		repo_dir        = repo_dir,
		parsers_dir     = parsers_dir,
		tmp_dir         = tmp_dir,
		tmp_parser_path = tmp_parser_path,
	}
	
	_paths = pp
	return pp
}
