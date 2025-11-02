# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

notedown.nvim is a Neovim plugin for Notedown Flavored Markdown with LSP integration. It provides wikilink support, list text objects, and workspace-aware parser selection. The plugin communicates with `notedown-language-server` (a separate Go project) to provide LSP features.

## Commands

For a complete list of user commands and development commands, see [COMMANDS.md](COMMANDS.md).

Key development commands:
- `make test` - Run all tests in Docker (recommended)
- `make format` - Format code and apply license headers
- `make check` - Run all checks (hygiene, tests, dirty check)

## Architecture

### Core Components

**Plugin Entry Point** (`plugin/notedown.lua`):
- Loaded once by Neovim's plugin system
- Registers TreeSitter language mapping (notedown → markdown)
- Creates user commands (`:NotedownReload`, `:NotedownWorkspaceStatus`, etc.)
- Calls `require("notedown").setup()` with defaults

**Main Module** (`lua/notedown/init.lua`):
- Contains all plugin logic (workspace detection, LSP client management, text objects)
- `setup()` function: Configures plugin and starts LSP server if in notedown workspace
- `find_notedown_workspace()`: Walks up directory tree to find `.notedown/` directory
- `should_use_notedown_parser()`: Determines if buffer should use notedown vs markdown filetype
- Autocmds handle buffer-level LSP attachment and filetype detection

**Configuration** (`lua/notedown/config.lua`):
- Defines default configuration structure
- LSP server command: `notedown-language-server serve --log-level debug --log-file /tmp/notedown.log`

### Workspace Detection Flow

1. On `BufRead` or `BufNewFile` for `*.md` files:
   - Walk up from file's directory looking for `.notedown/` directory
   - If found: Set `filetype=notedown` and mark workspace root
   - If not found: Set `filetype=markdown`

2. On `FileType` event for `markdown` or `notedown`:
   - Call `vim.lsp.start()` to attach LSP client (or reuse existing)
   - Set workspace root to `.notedown/` parent directory
   - Enable LSP-based folding for notedown files
   - Set up wikilink concealment for notedown files
   - Register `al` text object for list manipulation

3. LSP client lifecycle:
   - One shared client per workspace root
   - Early start: If CWD is in notedown workspace, LSP starts during setup()
   - Lazy start: Otherwise, starts when first notedown buffer opens

### LSP Integration Patterns

**Synchronous LSP Requests**:
- Used for interactive features requiring immediate feedback
- Example: `get_list_item_boundaries()` uses `client.request_sync()` with 1000ms timeout
- Folding expression uses synchronous requests with caching to avoid performance issues

**Command Execution**:
- `get_notedown_command_client()`: Helper to find LSP client with `executeCommandProvider` capability
- Supports optional timeout with retry logic for initialization race conditions
- Commands: `notedown.getListItemBoundaries`, `notedown.getConcealRanges`, `notedown.executeCodeBlocks`

**Folding Implementation**:
- Custom `notedown_foldexpr()` because `vim.lsp.foldexpr()` doesn't compute levels correctly
- Caches folding ranges per buffer with version tracking (changedtick)
- Refreshes cache on buffer changes before computing fold levels

**Concealment**:
- Uses LSP command `notedown.getConcealRanges` to get wikilink target positions
- Applies `matchaddpos()` for precise character-range concealment
- Debounced updates on text changes (300ms) to avoid excessive LSP requests

### Text Object Implementation

The `al` (around list) text object:
- Mapped in both operator-pending and visual modes
- Calls LSP command `notedown.getListItemBoundaries` with cursor position
- Receives start/end lines (0-based LSP) and converts to 1-based Vim
- Selects entire list item including all nested children using line-wise visual mode
- Works with standard operators: `dal` (delete), `yal` (yank), `cal` (change), `val` (visual select)

## Testing Architecture

For instructions on running tests, see [DEVELOPMENT.md](DEVELOPMENT.md). This section describes the internal testing architecture.

### Test Framework Design

Tests use a simplified, self-contained approach inspired by folke/trouble.nvim:

**No External Dependencies**: Pure Lua assertions, no busted/plenary/luaunit required

**Real LSP Integration**: Tests build actual `notedown-language-server` binary:
- Local: Builds from Go source in parent repo's `language-server/` directory
- Docker: Uses pre-installed binary from GitHub releases

**Spec File Pattern**:
```lua
-- Each spec file exports a boolean return value
local function test_something()
  print_test("feature name")
  -- Test logic with assertions
  assert_equals(actual, expected, "description")
end

-- Main entry point
return run_spec("spec name", {
  test_something,
  test_another_thing,
})
```

**Test Isolation**:
- Each test creates temporary workspace in `/tmp/`
- Workspaces include `.notedown/` directory to trigger notedown detection
- Cleanup happens after each test (or on failure)
- Shared utilities in `tests/test_utils.lua` for workspace creation/cleanup

### Test Runner (`tests/minit.lua`)

1. Detects environment (Docker vs local)
2. Builds or locates LSP server binary
3. Configures plugin with test binary path
4. Runs all spec files in sequence
5. Exits with `qall!` (success) or `cquit!` (failure)

### Key Test Utilities (`tests/test_utils.lua`)

**Workspace Creation**:
- `create_test_workspace(path, test_files)` - Creates notedown workspace with files
- `create_wikilink_test_workspace(path)` - Pre-configured wikilink test setup
- `create_content_test_workspace(content, path, filename)` - Single file workspace with content
- `create_non_notedown_workspace(path, test_files)` - Regular markdown workspace (no `.notedown/`)
- `create_task_workspace(path)` - Workspace with task settings and task list

**LSP Helpers**:
- `wait_for_lsp(timeout_ms)` - Wait for any LSP client to initialize
- `get_notedown_client()` - Get the notedown LSP client instance
- `lsp_request_sync(method, params, timeout_ms)` - Make synchronous LSP request with error handling
- `sync_document_with_lsp(bufnr)` - Send `didOpen` notification to ensure server knows about buffer

**Assertions**:
- `assert_equals(actual, expected, message)` - Basic equality assertion
- `assert_contains(text, pattern, message)` - Pattern matching assertion
- `assert_or_fail(condition, message, context)` - Assertion with automatic cleanup on failure

### Test Specs

- `config_spec.lua` - Workspace detection, configuration loading
- `init_spec.lua` - Plugin initialization and setup
- `workspace_spec.lua` - Workspace management and status
- `folding_spec.lua` - LSP-based folding for headers, lists, code blocks
- `list_text_object_spec.lua` - List boundary detection and `al` text object
- `task_completion_spec.lua` - Task state toggling
- `task_diagnostics_spec.lua` - Task validation and diagnostics
- `code_execution_spec.lua` - Code block execution features

### Docker Testing Environment

**Benefits**:
- Reproducible environment with pinned Neovim version
- Pre-built LSP server from GitHub releases (no Go toolchain needed)
- Matches CI environment exactly
- Isolated from local Neovim configuration

**Environment Variables**:
- `NOTEDOWN_TEST_DOCKER=1` - Signals Docker environment to test runner
- `NOTEDOWN_LSP_PATH=/opt/notedown-lsp/notedown-language-server` - Path to pre-installed LSP binary

**Build Args**:
- `NVIM_VERSION` - Neovim release version (default: v0.10.2)
- `LSP_VERSION` - notedown-language-server release version (default: v0.1.0)

### Test Fixtures (`tests/fixtures.lua`)

Provides workspace templates in `tests/fixtures/workspaces/`:
- `basic/` - Simple notedown workspace with index.md
- `empty/` - Empty workspace without .notedown directory
- `parent-detection/` - Nested directories for testing parent directory detection

## Important Implementation Details

### Filetype vs FileType
- `filetype` (lowercase): Buffer-local option set to "notedown" or "markdown"
- `FileType` (capitalized): Autocmd event triggered when filetype changes
- Plugin sets filetype based on workspace detection, then FileType event triggers LSP attachment

### LSP Client Lifecycle
- `vim.lsp.start()` is idempotent: Safe to call multiple times with same config
- If client already exists for workspace root, it reuses the existing client
- Client persists across buffer changes within same workspace
- `:NotedownReload` stops all clients and forces fresh start

### Concealment Timing
- Initial concealment: 100ms defer after buffer load
- Change debouncing: 300ms defer after text changes
- Retry on LspAttach: 500ms defer when LSP client attaches
- Multiple deferrals ensure concealment works regardless of LSP initialization timing

### Folding Range Caching
- Cache keyed by buffer number
- Includes `changedtick` version to detect stale cache
- Synchronous LSP request with 1000ms timeout (required by Vim's foldexpr evaluation)
- Falls back to fold level 0 if LSP unavailable or timeout

### Workspace Folders
- LSP client includes `workspace_folders` parameter with URI and name
- Uses `vim.uri_from_fname(workspace_root)` for proper file:// URI format
- Enables LSP server to track workspace boundaries and provide workspace-scoped features

## Plugin Commands

See [COMMANDS.md](COMMANDS.md) for the complete list of user commands including `:NotedownWorkspaceStatus`, `:NotedownReload`, `:NotedownMoveUp/Down`, and `:NotedownExecuteCode`.

## Common Development Patterns

### Adding New LSP Commands

1. Add command handler in language-server (separate Go repo)
2. In `init.lua`, create function that:
   - Gets client with `get_notedown_command_client()`
   - Builds params with command name and arguments
   - Calls `client.request_sync()` or `client.request()`
   - Handles result and errors appropriately
3. Add test coverage in appropriate spec file
4. Optionally expose as user command in `plugin/notedown.lua`

### Adding New Tests

1. Choose appropriate spec file or create new `*_spec.lua`
2. Define test function with descriptive name
3. Use `test_utils.create_test_workspace()` for isolation
4. Make assertions with `assert_equals()` or similar
5. Add test function to spec's test list
6. Update `minit.lua` to include new spec file if created

### Formatting and Licensing

All Lua files must have Apache 2.0 license header:
- Run `make format` to auto-apply headers with licenser tool
- Uses `stylua` for consistent Lua formatting
- Configuration in flake.nix for Nix users

## Dependencies

**Runtime**:
- Neovim >= 0.10.0
- `notedown-language-server` binary in PATH (from notedownorg/notedown releases)
- TreeSitter support (built into Neovim 0.10+)

**Development**:
- Go toolchain (for building LSP server locally during tests)
- stylua (for formatting)
- licenser (for license headers)
- Docker (optional, for reproducible testing)
- Nix (optional, provides all dev dependencies)

**Test Dependencies**:
- Neovim (headless mode)
- Go (to build LSP server) OR Docker (uses pre-built binary)
- Temporary directory access (/tmp/)
