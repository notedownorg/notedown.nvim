# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Test Commands

### Running Tests
- `nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run()" -c "qall!"` - Run all tests
- `nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run_file('tests/test_list_movement.lua')" -c "qall!"` - Run specific test file
- `nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run_file('tests/test_list_movement.lua', {filter = 'nested'})" -c "qall!"` - Run tests matching pattern

### Golden File Testing
- `UPDATE_GOLDEN=1 nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run_file('tests/test_list_movement.lua')" -c "qall!"` - Update golden files when expected behavior changes

## Test Architecture

### Testing Framework
Uses `mini.test` from the mini.nvim ecosystem for structured test organization and execution. Tests are organized in test sets with clear hierarchical naming.

### Test Categories

#### List Movement Tests (`test_list_movement.lua`)
- **Golden File Approach**: Uses input/expected output file pairs in `testdata/list_movement/`
- **Test Types**: Simple (4-item lists), nested (6-level deep), tasks (checkbox lists), boundary conditions
- **Cursor Validation**: Verifies cursor position after movement commands
- **Shared LSP**: Uses `lsp_shared.lua` for persistent LSP session across tests

#### Wikilink Tests (`test_wikilink.lua`)
- **LSP Integration**: Tests wikilink navigation, completion, diagnostics, and code actions
- **Dedicated LSP**: Uses `lsp_dedicated.lua` for isolated LSP sessions per test
- **Real LSP Server**: Spawns actual notedown-language-server binary for authentic testing

### Helper System

#### Golden File Testing (`helpers/golden.lua`)
- **File-based Testing**: Compares actual output against expected golden files
- **Diff Generation**: Provides clear visual diffs when tests fail
- **Automatic Updates**: `UPDATE_GOLDEN=1` environment variable regenerates golden files
- **Workspace Management**: Creates temporary test workspaces with proper cleanup

#### LSP Integration Helpers
- **Shared LSP** (`lsp_shared.lua`): Single persistent LSP session for performance in list movement tests
- **Dedicated LSP** (`lsp_dedicated.lua`): Isolated LSP sessions for wikilink feature testing
- **Binary Management**: Handles LSP server binary compilation and cleanup

##### LSP Session Strategy

**Default: Use Shared LSP (`lsp_shared.lua`)**
- Single persistent LSP session across all tests for performance
- Suitable for most text transformation and document manipulation tests
- Avoids LSP startup overhead and provides faster test execution

**Use Dedicated LSP (`lsp_dedicated.lua`) only when:**
- Testing features that depend on **global workspace state** (wikilink auto-completion, workspace file indexing)
- Testing **LSP-specific operations** (diagnostics, code actions, go-to-definition)
- Tests require **isolated file structures** or **conflicting workspace setups**
- Validating **cross-file relationships** or **workspace-wide indexing**

Examples:
- ✅ **Shared**: List movements, text formatting, cursor positioning
- ⚠️ **Dedicated**: Wikilink completion (needs workspace file discovery), ambiguous link diagnostics, cross-file navigation

#### Test Utilities (`helpers/utils.lua`)
- **Workspace Creation**: Temporary test workspace setup and cleanup
- **Neovim Child Processes**: Manages headless Neovim instances for testing
- **File Operations**: Test file creation and content management

### Test Data Structure

```
testdata/list_movement/
├── simple/              # Basic 4-item list movements
├── nested/              # Deep nested lists (6 levels)
└── tasks/               # Task list movements with checkboxes
```

Each category contains:
- `input.md` - Initial test content
- `{operation}.md` - Expected output after specific operations

### Key Testing Patterns

#### Golden File Pattern
```lua
T["category - descriptive name"] = function()
    golden.test_list_movement("category", "expected_file", {
        search_pattern = "text to find for cursor positioning",
        command = "NotedownMoveUp",
        expected_cursor = { line, character }
    })
end
```

#### LSP Testing Pattern
```lua
-- Setup workspace and LSP
local workspace = setup_test_workspace()
local child = utils.new_child_neovim()
lsp.setup(child, workspace)

-- Execute LSP operations
child.lua("vim.lsp.buf.definition()")

-- Validate results and cleanup
child.stop()
utils.cleanup_test_workspace(workspace)
```

### Dependencies
- **mini.nvim**: Automatically downloaded to test dependencies directory
- **notedown-language-server**: Built from parent LSP implementation
- **Temporary Workspaces**: Created in `/tmp/` with automatic cleanup

### Test Environment
- **Headless Neovim**: All tests run without UI
- **Minimal Init**: Custom minimal configuration for testing isolation
- **Provider Disabling**: Node, Perl, Python, Ruby providers disabled for speed
- **Package Path Management**: Tests directory added to Lua package path for helper imports