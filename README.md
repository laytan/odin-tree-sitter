# Odin Tree Sitter

API bindings, wrappers and convenience for [Tree Sitter](https://github.com/tree-sitter/tree-sitter).

A small API example has been written in `example`.

Odin documentation has been published here: [odin-tree-sitter.laytan.dev](https://odin-tree-sitter.laytan.dev/).

## Build script

In order to make installing tree-sitter and its grammars easier, a build script was written.
With it tree-sitter itself can be installed, and more importantly the grammars can be installed and have bindings generated.

NOTE: On Windows, you must run this script through the Developer Command Prompt bundled with Visual Studio.

You can change the c compiler or archiver by setting the `CC` and `AR` environment variables.

### Installing tree-sitter

Command installs tree-sitter itself by downloading the git repository, compiling it, and putting the
static library and license in the `tree-sitter` subdirectory.

Debug symbols, a different repo or branch and more can be configured using flags and options.

```sh
odin run build -- install -h
Usage:
        build install [-branch] [-clean] [-debug] [-minimum-os-version] [-repo]
Flags:
        -branch:<string>              | Branch of the tree-sitter git repo to install, default is
        -clean                        | First uninstall.
        -debug                        | Compile tree-sitter with debug symbols.
        -minimum-os-version:<string>  | The minimum OS version to target (only used on Darwin, default is 12.0.0).
        -repo:<string>                | Repo to install, default is 'https://github.com/tree-sitter/tree-sitter'.
```

### Installing and generating bindings for language grammar

Command installs specific tree-sitter grammars by downloading the git repository, compiling the parser,
and putting the parser, readme, license and query files in its own subdirectory under `parsers`.
Bindings are also automatically generated in this directory.

The bindings will contain one procedure in the format `tree_sitter_LANGUAGE_NAME` and constants that use
`#load` to load in the query files it provides.

```sh
odin run build -- install-parser -h
Usage:
        build install-parser parser [-clean] [-debug] [-minimum-os-version] [-name] [-path] [-yes]
Flags:
        -parser:<string>, required    | git URL of the parser to be installed.
                                      |
        -clean                        | First uninstall.
        -debug                        | Compile parser with debug symbols.
        -minimum-os-version:<string>  | The minimum OS version to target (only used on Darwin, default is 12.0.0).
        -name:<string>                | Overwrite the language name.
        -path:<string>                | Subdirectory to compile.
        -yes                          | Automatically confirm questions to their defaults (non-interactive) mode.
```
