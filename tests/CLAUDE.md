# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Neovim plugin test suite.

## Test Commands

### Running Tests
- `nvim -l tests/minit.lua` - Run all tests (builds LSP server and runs all spec files)
- `./scripts/test` - Shell wrapper (runs minit.lua)
- `nvim -l tests/wikilink_spec.lua` - Run specific test file

### Test Structure

Tests use a simplified approach inspired by folke/trouble.nvim:

- **Spec Files**: Tests organized in `*_spec.lua` files with `run_tests()` functions
- **Simple Assertions**: Uses basic assertion functions instead of external frameworks
- **Real LSP Integration**: Tests build and use actual notedown-language-server
- **Test Isolation**: Each test creates temporary workspaces for clean testing

## Test Architecture

### Testing Framework
Uses simple assertion-based testing with no external dependencies. Each test file follows the pattern:
- Has a `run_tests()` function that returns `true`/`false`
- Uses `assert_equals()` and similar helper functions
- Creates temporary test workspaces for isolation
- Cleans up after itself

### Test Files

#### Core Functionality Tests
- `wikilink_spec.lua` - Wikilink navigation, completion, diagnostics, code actions, concealment
- `folding_spec.lua` - LSP-based folding for headers, lists, and code blocks  
- `list_text_object_spec.lua` - List item boundary detection and text objects
- `config_spec.lua` - Configuration and workspace detection
- `init_spec.lua` - Plugin initialization and setup

#### Task System Tests
- `task_completion_spec.lua` - Task completion features
- `task_diagnostics_spec.lua` - Task diagnostics and validation
- `workspace_spec.lua` - Workspace management functionality

### Test Helpers

#### Assertion Functions
```lua
local function assert_equals(actual, expected, message)
  if actual ~= expected then
    error((message or "Assertion failed") .. ": expected " .. tostring(expected) .. " but got " .. tostring(actual))
  end
  print("✓ " .. (message or "Assertion passed"))
end
```

#### Workspace Management
Use the shared workspace utilities from `test_utils.lua`:

```lua
-- Create a notedown workspace with optional test files
local workspace = test_utils.create_test_workspace("/tmp/test-workspace", test_files)

-- Create a workspace with wikilink test files  
local workspace = test_utils.create_wikilink_test_workspace("/tmp/wikilink-test")

-- Create a non-notedown workspace (no .notedown directory)
local workspace = test_utils.create_non_notedown_workspace("/tmp/regular-markdown")

-- Create workspace with content and open file
local workspace = test_utils.create_content_test_workspace(content, "/tmp/content-test")

-- Clean up when done
test_utils.cleanup_test_workspace(workspace)
```

### Test Patterns

#### Basic Test Structure
```lua
local function test_feature_name()
  print("Running test: feature name")
  
  local workspace = test_utils.create_test_workspace("/tmp/test-workspace")
  
  -- Test setup and execution
  vim.cmd("cd " .. workspace)
  vim.cmd("edit test.md")
  
  -- Test assertions
  assert_equals(actual_value, expected_value, "Should match expected value")
  
  test_utils.cleanup_test_workspace(workspace)
  print("✓ feature name test passed")
end
```

#### LSP Integration Testing
```lua
local function test_lsp_feature()
  local workspace = create_test_workspace("/tmp/test-lsp")
  
  vim.cmd("cd " .. workspace)
  vim.cmd("edit test.md")
  
  -- Wait for LSP to initialize
  local lsp_ready = vim.wait(5000, function()
    return #vim.lsp.get_clients() > 0
  end)
  
  if lsp_ready then
    -- Test LSP functionality
    vim.lsp.buf.definition()
    -- Assert expected behavior
  else
    print("✓ No LSP available, skipping advanced tests")
  end
  
  test_utils.cleanup_test_workspace(workspace)
end
```

### Test Runners

#### Main Test Runner (`minit.lua`)
- Builds LSP server binary with proper version info
- Configures notedown plugin with test binary
- Runs all spec files in sequence
- Exits with appropriate status codes

#### Shell Wrapper (`scripts/test`)
- Simple bash script that calls `nvim -l tests/minit.lua`
- Easy integration with Makefile and CI systems

### Dependencies
- **Neovim**: Tests run in headless mode
- **Go toolchain**: Required to build LSP server binary
- **notedown-language-server**: Built automatically by test runners
- **Temporary Workspaces**: Created in `/tmp/` with automatic cleanup

### Test Environment
- **Headless Neovim**: All tests run without UI using `-l` flag
- **Real LSP Server**: Uses actual notedown-language-server binary
- **Isolated Workspaces**: Each test creates temporary directories
- **Clean State**: Tests clean up after themselves to avoid interference

### Adding New Tests

When adding new test functionality:

1. **Choose the Right File**: Add tests to the appropriate `*_spec.lua` file
2. **Follow the Pattern**: Use the standard test function structure
3. **Use Assertions**: Use `assert_equals()` and similar helpers for clear error messages
4. **Workspace Isolation**: Create temporary workspaces for test isolation
5. **Clean Up**: Always clean up test workspaces when done
6. **Update Test List**: Add new test functions to the `run_tests()` function

### Debugging Tests

If tests fail, try these troubleshooting steps:

#### 1. Check Basic Setup
```bash
# Verify neovim is available
nvim --version

# Check if Go is available (needed for LSP binary building)  
go version

# Verify test files exist
ls -la tests/
```

#### 2. Try Shell Wrapper
```bash
# Use the shell wrapper
./scripts/test
```

#### 3. Common Issues
- **LSP build fails**: Check if Go is installed and language-server/ directory exists as sibling (clone from https://github.com/notedownorg/language-server)
- **Plugin load fails**: Check if lua/notedown/ files exist and are readable
- **Permission errors**: Ensure scripts/test is executable (`chmod +x scripts/test`)
- **Wrong directory**: Ensure you're running from the notedown.nvim directory

#### 4. Debug Individual Tests
```bash
# Test specific functionality
nvim -l tests/config_spec.lua
nvim -l tests/wikilink_spec.lua
nvim -l tests/folding_spec.lua
```

#### 5. Verify Project Structure
- Current directory should be `notedown.nvim/`
- Language-server should be a sibling directory at `../language-server/`
- Clone language-server from: https://github.com/notedownorg/language-server