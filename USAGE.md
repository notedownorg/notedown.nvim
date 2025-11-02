# Usage Guide

## Automatic Features

The plugin automatically:
- Detects Notedown workspaces by finding `.notedown/` directories
- Starts the notedown language server for markdown files in workspaces
- Provides wikilink completion with `[[`
- Enables go-to-definition for wikilinks
- Sets the LSP root directory to the detected workspace root

## LSP Features

### Wikilink Completion

Type `[[` to trigger intelligent completion:

- **Existing Files**: Complete paths to actual markdown files
- **Referenced Targets**: Suggest wikilink targets mentioned in other files
- **Directory Paths**: Complete directory structures for organization

### Go-to-Definition

- Place cursor on a wikilink target
- Use `gd` or your configured go-to-definition keybinding
- Jump to the target file or create it if it doesn't exist

## List Text Object

The plugin provides an "around list" text object (`al`) for precise list manipulation:

- **`dal`**: Delete around list item (puts in default register for pasting)
- **`yal`**: Yank around list item for moving to another location
- **`cal`**: Change around list item (delete and enter insert mode)
- **`val`**: Visually select around list item
- **`"xdal`**: Delete around list item into register `x`

The text object works with **any list type** and includes **all children**:

```markdown
- Main item                    <- cursor anywhere on this line
  - Child item A               <- these children are included
    - Deep nested item
  - Child item B               <- all children included
- Next main item               <- this is NOT included
```

**Use cases:**
- **Reorganizing**: `dal` to cut, move cursor, `p` to paste
- **Duplicating**: `yal` to copy, move cursor, `p` to paste
- **Refactoring**: `cal` to replace entire list structure
- **Selection**: `val` to select for other operations

## Commands

The plugin provides several user commands for workspace management and debugging. See [COMMANDS.md](COMMANDS.md) for the complete list of available commands.

## Configuration

For configuration options including workspace detection, custom LSP server settings, and advanced customization, see [CONFIGURATION.md](CONFIGURATION.md).

## 🐛 Troubleshooting

### LSP Server Not Starting

1. Ensure `notedown-language-server` is in your PATH:
   ```bash
   which notedown-language-server
   ```

2. Check server logs:
   ```bash
   tail -f /tmp/notedown.log
   ```

3. Verify configuration with `:NotedownWorkspaceStatus`

### Wikilink Completion Not Working

1. Ensure a `.notedown/` directory exists in your project root or parent directories
2. Check that LSP server is running: `:LspInfo`
3. Verify workspace detection: `:NotedownWorkspaceStatus`
4. Try typing `[[` and wait for completion popup

### Parser Issues

1. Check LSP server status: `:LspInfo`
2. Verify workspace detection: `:NotedownWorkspaceStatus`
3. Ensure `.notedown/` directory exists in your project root or a parent directory
