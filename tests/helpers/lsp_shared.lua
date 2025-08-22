-- Copyright 2024 Notedown Authors
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

-- Shared LSP session management for optimized test performance
--
-- This helper provides a SHARED LSP session - one LSP server instance and
-- Neovim child process is reused across multiple tests. Use this when:
-- - Running many tests that don't interfere with each other
-- - Tests only read/query LSP state without modifying it
-- - Performance is important (faster test execution)
-- - Tests work with isolated workspace directories
--
-- Each test gets its own temporary workspace directory but shares the same
-- LSP server and Neovim instance. For complete test isolation, use
-- helpers.lsp_dedicated instead.

local utils = require("helpers.utils")
local lsp = require("helpers.lsp_dedicated")

local M = {}

-- Global state for the shared LSP session
local shared_session = {
	child = nil,
	workspace_base = nil,
	binary_path = nil,
	is_initialized = false,
}

-- Initialize shared LSP session for the entire test suite
function M.initialize()
	if shared_session.is_initialized then
		return shared_session
	end

	-- Create base workspace directory
	local timestamp = os.time()
	shared_session.workspace_base = "/tmp/notedown-shared-test-" .. timestamp
	vim.fn.system({ "rm", "-rf", shared_session.workspace_base })
	vim.fn.mkdir(shared_session.workspace_base, "p")

	-- Build LSP binary
	shared_session.binary_path = lsp.get_binary_path()

	-- Create child neovim instance
	shared_session.child = utils.new_child_neovim()

	-- Setup notedown with LSP server pointing to base workspace

	-- Execute setup in the child process
	shared_session.child.lua(
		string.format(
			[[
		require('notedown').setup({
			server = {
				name = "notedown",
				cmd = { %q, 'serve' },
				root_dir = function() return %q end
			},
			parser = {
				mode = "notedown",
				notedown_workspaces = { %q }
			}
		})
		
		-- Create a buffer and set filetype to trigger LSP
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, %q .. "/test.md")
		vim.api.nvim_set_current_buf(buf)
		vim.bo.filetype = "notedown"
	]],
			shared_session.binary_path,
			shared_session.workspace_base,
			shared_session.workspace_base,
			shared_session.workspace_base
		)
	)

	-- Wait for LSP to initialize using shared logic
	lsp.wait_for_lsp_clients(shared_session.child)

	shared_session.is_initialized = true
	return shared_session
end

-- Create an isolated workspace directory for a single test
function M.create_test_workspace(content)
	if not shared_session.is_initialized then
		-- Auto-initialize if not already done
		M.initialize()
	end

	-- Generate random test ID
	local random_id = math.random(10000, 99999)
	local test_workspace = shared_session.workspace_base .. "/test-" .. random_id

	-- Clean up any existing workspace
	vim.fn.system({ "rm", "-rf", test_workspace })
	vim.fn.mkdir(test_workspace, "p")

	-- Create test file
	local file_path = test_workspace .. "/test.md"
	utils.write_file(file_path, content)

	return test_workspace, file_path
end

-- Get the shared child neovim instance
function M.get_child()
	if not shared_session.is_initialized then
		-- Auto-initialize if not already done
		M.initialize()
	end
	return shared_session.child
end

-- Open a file in the shared neovim instance
function M.open_file(file_path)
	local child = M.get_child()

	-- Close any existing buffers to avoid state contamination
	child.lua(
		"for _, buf in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_is_loaded(buf) then vim.api.nvim_buf_delete(buf, {force = true}) end end"
	)

	-- Create new buffer and edit the file
	child.lua('vim.cmd("edit ' .. file_path .. '")')

	-- Ensure filetype is set to notedown for proper command registration
	child.lua('vim.bo.filetype = "notedown"')

	-- Explicitly set up the text object for testing
	child.lua('require("notedown").setup_list_text_object()')

	-- Verify the text object was set up
	local al_exists = child.lua_get('vim.fn.mapcheck("al", "o") ~= ""')
	if not al_exists then
		error("Text object 'al' was not set up properly in test environment")
	end

	-- Ensure document is properly opened in LSP
	child.lua(string.format(
		[[
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_fname(%q)
			local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
			
			-- Send didOpen notification
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
		end
	]],
		file_path
	))

	-- Wait for document opening and command registration
	vim.loop.sleep(500)
end

-- Execute a command in the shared neovim instance
function M.execute_command(command)
	local child = M.get_child()

	-- Execute the command
	child.lua('vim.cmd("' .. command .. '")')

	-- Wait for LSP command to complete
	vim.loop.sleep(200)
end

-- Position cursor using search pattern
function M.position_cursor(search_pattern, line, character)
	local child = M.get_child()

	if search_pattern then
		child.lua('vim.fn.search("' .. search_pattern .. '")')
	elseif line and character then
		child.lua(string.format("vim.api.nvim_win_set_cursor(0, {%d, %d})", line, character))
	else
		error("Must specify either search_pattern or line+character for cursor positioning")
	end
end

-- Get buffer content from shared neovim instance
function M.get_buffer_content()
	local child = M.get_child()
	return child.lua_get('table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\\n")')
end

-- Get cursor position from shared neovim instance
function M.get_cursor_position()
	local child = M.get_child()
	return child.lua_get("vim.api.nvim_win_get_cursor(0)")
end

-- Execute a vim command or key sequence in shared neovim instance
function M.execute_vim_command(command)
	local child = M.get_child()

	-- Handle text object operations (like yal, dal) as normal mode key sequences
	if command:match("^[ydcv]al$") then
		-- These are operator + text object combinations, execute as normal mode keys
		child.lua(string.format("vim.cmd('normal! %s')", command))
	else
		-- Regular commands
		child.cmd(command)
	end
end

-- Get register content from shared neovim instance
function M.get_register_content()
	local child = M.get_child()
	return child.lua_get('vim.fn.getreg("")')
end

-- Clean up a test workspace directory
function M.cleanup_test_workspace(workspace_path)
	vim.fn.system({ "rm", "-rf", workspace_path })
end

-- Cleanup the entire shared LSP session
function M.cleanup()
	if not shared_session.is_initialized then
		return
	end

	-- Stop child neovim
	if shared_session.child then
		shared_session.child.stop()
	end

	-- Clean up workspace
	if shared_session.workspace_base then
		vim.fn.system({ "rm", "-rf", shared_session.workspace_base })
	end

	-- Clean up LSP binary
	lsp.cleanup_binary()

	-- Reset state
	shared_session = {
		child = nil,
		workspace_base = nil,
		binary_path = nil,
		is_initialized = false,
	}
end

return M
