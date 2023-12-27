# Odin Tree Sitter

API bindings, wrappers and convenience for [Tree Sitter](https://github.com/tree-sitter/tree-sitter).

A small API example has been written in `example`.

Odin documentation has been published here: [odin-tree-sitter.laytan.dev](https://odin-tree-sitter.laytan.dev/).

## Build script

In order to make installing tree-sitter and its grammars easier, a build script was written.
With it tree-sitter itself can be installed, and more importantly the grammars can be installed and have bindings generated.

### Installing tree-sitter

Command installs tree-sitter itself by downloading the git repository, compiling it, and putting the
static library and license in the `tree-sitter` subdirectory.

Debug symbols, a different repo or branch and more can be configured using flags and options.

```sh
odin run build -- install --help
Usage:
        build install [flags]
Flags:
        -help,-h               Show this message.
        -debug,-d              Compile tree-sitter with debug symbols.
        -minimum-os-version,-m The minimum OS version to target (only used on Darwin, default is 12.0.0).
        -branch,-b             Branch of the tree-sitter git repo to install, default is "master".
        -repo,-r               Repo to install, default is "https://github.com/tree-sitter/tree-sitter".
        -clean,-c              First uninstall
```

### Installing and generating bindings for language grammar

Command installs specific tree-sitter grammars by downloading the git repository, compiling the parser,
and putting the parser, readme, license and query files in its own subdirectory under `parsers`.
Bindings are also automatically generated in this directory.

The bindings will contain one procedure in the format `tree_sitter_LANGUAGE_NAME` and constants that use
`#load` to load in the query files it provides.

```sh
odin run build -- install-parser --help
Usage:
        build install-parser [git-url]
Example:
        build install-parser https://github.com/amaanq/tree-sitter-odin
Flags:
        -help,-h               Show this message.
        -debug,-d              Compile parser with debug symbols.
        -minimum-os-version,-m The minimum OS version to target (only used on Darwin, default is 12.0.0).
        -yes,-y                Automatically confirm questions to their defaults (non-interactive) mode.
        -name,-n               Overwrite the language name.
        -clean,-c              First uninstall.
        -path,-p               Subdirectory to compile.
```
