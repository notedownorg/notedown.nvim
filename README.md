# 📝 notedown.nvim

A Neovim plugin for [Notedown Flavored Markdown](https://github.com/notedownorg/notedown/tree/main/language) with full LSP integration and automatic workspace detection.

## ✨ Features

- 🔗 **Wikilink Support**: Intelligent completion and navigation for `[[wikilinks]]`
- ✂️ **List Text Object**: Precisely select, delete, yank, and manipulate list items with `dal`, `yal`, `cal`, `val`
- 🏠 **Automatic Workspace Detection**: Uses notedown parser when `.notedown/` directory is found
- 🧠 **Smart LSP Integration**: Seamless language server integration with document synchronization
- ⚡ **Fast**: Efficient workspace detection with path-based matching
- 🔧 **Configurable**: Flexible parser selection modes and workspace configuration

## 📦 Installation

Requires Neovim >= 0.10.0 and [notedown-language-server](https://github.com/notedownorg/notedown) in your PATH.

For detailed installation instructions including language server setup and plugin manager configurations, see [INSTALLATION.md](INSTALLATION.md).

## ⚙️ Configuration

Most users need no configuration! The plugin automatically detects Notedown workspaces by finding `.notedown/` directories.

For workspace detection, advanced configuration options, and customization, see [CONFIGURATION.md](CONFIGURATION.md).

## 🚀 Usage

For detailed usage instructions, LSP features, text objects, advanced configuration, and troubleshooting, see [USAGE.md](USAGE.md).

## 🧪 Development

For information on testing, contributing, and development workflows, see [DEVELOPMENT.md](DEVELOPMENT.md).

## 📄 License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

## 🔗 Related Projects

- [notedown](https://github.com/notedownorg/notedown) - The main Notedown language server and language specification
- [Obsidian](https://obsidian.md) - For wikilink inspiration
