package ts_build

import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
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

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info, {.Level, .Terminal_Color})

	args := slice.clone_to_dynamic(os.args)

	if len(os.args) < 2 {
		print_usage(os.stderr)	
		os.exit(1)
	}

	switch os.args[1] {
	case "help":
		print_usage(os.stdout)
		return
	case "install":
		args[0] = strings.join({args[0], args[1]}, " ")
		ordered_remove(&args, 1)

		ok := install(args[:])
		os.exit(0 if ok else 1)
	case "install-parser":
		args[0] = strings.join({args[0], args[1]}, " ")
		ordered_remove(&args, 1)

		ok := install_parser(args[:])
		os.exit(0 if ok else 1)
	case:
		log.errorf("unknown command %q", os.args[1])
		print_usage(os.stderr)
		os.exit(1)
	}
}

Install_Opts :: struct {
	debug:              bool   `usage:"Compile tree-sitter with debug symbols."`,
	unoptimized:        bool   `usage:"Compile tree-sitter without optimizations."`,
	minimum_os_version: string `usage:"The minimum OS version to target (only used on Darwin, default is 12.0.0)."`,
	branch:             string `usage:"Branch of the tree-sitter git repo to install, default is 'v0.26.3'."`,
	repo:               string `usage:"Repo to install, default is 'https://github.com/tree-sitter/tree-sitter'."`,
	clean:              bool   `usage:"First uninstall."`,
}

install :: proc(args: []string) -> bool {
	iopts := Install_Opts{
		branch             = "v0.26.3",
		repo               = "https://github.com/tree-sitter/tree-sitter",
		minimum_os_version = "12.0.0",
	}
	flags.parse_or_exit(&iopts, args)

	return _install(iopts)
}

Install_Parser_Opts :: struct {
	parser:             string `args:"required,pos=0" usage:"git URL of the parser to be installed."`,
	debug:              bool   `usage:"Compile parser with debug symbols."`,
	unoptimized:        bool   `usage:"Compile parser without optimizations."`,
	minimum_os_version: string `usage:"The minimum OS version to target (only used on Darwin, default is 12.0.0)."`,
	yes:                bool   `usage:"Automatically confirm questions to their defaults (non-interactive) mode."`,
	name:               string `usage:"Overwrite the language name."`,
	clean:              bool   `usage:"First uninstall."`,
	path:               string `usage:"Subdirectory to compile."`,
}

install_parser :: proc(args: []string) -> bool {
	iopts := Install_Parser_Opts{
		minimum_os_version = "12.0.0",
	}
	flags.parse_or_exit(&iopts, args)

	return _install_parser(iopts)
}

PROGRAM :: "build"

BINDINGS :: `package ts_{0:s}

import ts "../.."

when ODIN_OS == .Windows {{
	foreign import ts_{0:s} "parser.lib"
}} else {{
	foreign import ts_{0:s} "parser.a"
}}

foreign ts_{0:s} {{
	tree_sitter_{0:s} :: proc() -> ts.Language ---
}}

`
