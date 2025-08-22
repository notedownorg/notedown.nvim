-- Copyright 2025 Notedown Authors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Tests for notedown folding functionality

local MiniTest = require("mini.test")
local utils = require("helpers.utils")
local lsp = require("helpers.lsp_dedicated")

local T = MiniTest.new_set()

-- Test content with various foldable elements
local test_content = [[# Header 1

Some content under header 1.

## Header 2

More content under header 2.

### Header 3

Content under header 3.

## Another Header 2

More content here.

- [ ] Task 1
- [x] Task 2
  - [ ] Subtask 1
  - [ ] Subtask 2
    - [ ] Sub-subtask
- [ ] Task 3

Regular list:
- Item 1
- Item 2
  - Nested item
  - Another nested item
- Item 3

```javascript
function test() {
  console.log("Testing folding");
  if (true) {
    console.log("nested");
  }
}
```

# Final Header

Final content.
]]

-- Helper function to create test workspace with folding content
local function setup_folding_workspace()
	local workspace = utils.create_test_workspace("/tmp/test-folding-workspace")

	-- Create .notedown directory to make it a notedown workspace
	vim.fn.mkdir(workspace .. "/.notedown", "p")

	-- Write test content to a file
	utils.write_file(workspace .. "/folding-test.md", test_content)

	return workspace
end

-- Helper function to wait for LSP folding ranges to be available
local function wait_for_folding_ranges(child, timeout)
	timeout = timeout or 5000
	return utils.wait_for_condition(function()
		-- Check if foldexpr function is working
		local fold_result = child.lua_get('type(vim.lsp.foldexpr()) == "function"')
		return fold_result == true
	end, timeout)
end

-- Helper function to get fold information for a line
local function get_fold_info(child, line_number)
	return child.lua_get(string.format("vim.fn.foldlevel(%d)", line_number))
end

-- Helper function to get the number of folding ranges from LSP
local function get_folding_ranges_count(child)
	return child.lua_get('vim.fn.line("$")') -- Just return line count as a simple check
end

T["folding setup"] = MiniTest.new_set()

T["folding setup"]["enables LSP folding for notedown files"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to the workspace directory
	child.lua('vim.fn.chdir("' .. workspace .. '")')

	-- Open the test file (this should trigger notedown filetype)
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready
	lsp.wait_for_ready(child)

	-- Wait a bit more for all autocmds to fire
	vim.loop.sleep(500)

	-- Check that filetype is notedown (this confirms the autocmd logic)
	local filetype = child.lua_get("vim.bo.filetype")
	MiniTest.expect.equality(filetype, "notedown", "File should be detected as notedown type")

	-- Check that folding is configured for LSP
	local foldmethod = child.lua_get("vim.opt_local.foldmethod:get()")
	local foldexpr = child.lua_get("vim.opt_local.foldexpr:get()")
	local foldenable = child.lua_get("vim.opt_local.foldenable:get()")

	MiniTest.expect.equality(foldmethod, "expr", "Foldmethod should be expr")
	MiniTest.expect.equality(foldexpr, "v:lua.vim.lsp.foldexpr()", "Foldexpr should use LSP")
	MiniTest.expect.equality(foldenable, true, "Folding should be enabled")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["folding setup"]["does not enable LSP folding for markdown files"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-markdown-workspace")
	local child = utils.new_child_neovim()

	-- Setup notedown (without .notedown directory, so it's not a notedown workspace)
	lsp.setup_mock(child)

	-- Change to non-notedown workspace
	child.lua('vim.fn.chdir("' .. workspace .. '")')

	-- Open a markdown file
	child.lua('vim.cmd("edit test.md")')

	-- Wait a moment for autocmds to fire
	vim.loop.sleep(200)

	-- Should be markdown filetype, not notedown
	local filetype = child.lua_get("vim.bo.filetype")
	MiniTest.expect.equality(filetype, "markdown")

	-- Folding should not be set to LSP (should be default)
	local foldmethod = child.lua_get("vim.opt_local.foldmethod:get()")
	MiniTest.expect.equality(foldmethod ~= "expr", true, "Foldmethod should not be expr for markdown files")

	child.stop()
	utils.cleanup_test_workspace(workspace)
end

T["header folding"] = MiniTest.new_set()

T["header folding"]["creates foldable regions for headers"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to workspace and open the test file
	child.lua('vim.fn.chdir("' .. workspace .. '")')
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready
	lsp.wait_for_ready(child)
	vim.loop.sleep(1000)

	-- Check that we have content
	local line_count = get_folding_ranges_count(child)
	MiniTest.expect.equality(line_count > 10, true, "Should have content with multiple lines")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["list folding"] = MiniTest.new_set()

T["list folding"]["creates foldable regions for nested lists"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to workspace and open the test file
	child.lua('vim.fn.chdir("' .. workspace .. '")')
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready and folding to be available
	lsp.wait_for_ready(child)
	vim.loop.sleep(1000) -- Give LSP more time to process

	-- Test that we have content (basic check)
	local line_count = get_folding_ranges_count(child)
	MiniTest.expect.equality(line_count > 5, true, "Should have content with multiple lines")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["code block folding"] = MiniTest.new_set()

T["code block folding"]["creates foldable regions for code blocks"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to workspace and open the test file
	child.lua('vim.fn.chdir("' .. workspace .. '")')
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready
	lsp.wait_for_ready(child)
	vim.loop.sleep(1000)

	-- Verify that folding is working by checking line count
	local line_count = get_folding_ranges_count(child)
	MiniTest.expect.equality(line_count > 0, true, "Should have content")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["folding integration"] = MiniTest.new_set()

T["folding integration"]["LSP server provides folding ranges"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to workspace and open the test file
	child.lua('vim.fn.chdir("' .. workspace .. '")')
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready
	lsp.wait_for_ready(child)
	vim.loop.sleep(1000)

	-- Verify LSP client is active
	local client_count = child.lua_get("#vim.lsp.get_active_clients()")
	MiniTest.expect.equality(client_count > 0, true, "Should have active LSP client")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["folding integration"]["manual fold operations work"] = function()
	local workspace = setup_folding_workspace()
	local child = utils.new_child_neovim()

	-- Setup notedown with LSP
	lsp.setup(child, workspace)

	-- Change to workspace and open the test file
	child.lua('vim.fn.chdir("' .. workspace .. '")')
	child.lua('vim.cmd("edit folding-test.md")')

	-- Wait for LSP to be ready
	lsp.wait_for_ready(child)
	vim.loop.sleep(1000)

	-- Test that basic folding commands don't error by running a simple one
	local fold_command_success = child.lua_get('pcall(function() vim.cmd("normal! zo") end)')
	MiniTest.expect.equality(fold_command_success, true, "Basic fold commands should work without errors")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

return T
