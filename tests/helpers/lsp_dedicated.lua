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

-- Dedicated LSP session management for notedown.nvim tests
--
-- This helper provides ISOLATED LSP sessions - each test gets its own fresh
-- LSP server instance and Neovim child process. Use this when:
-- - Tests need complete isolation from each other
-- - Testing LSP initialization/shutdown behavior
-- - Tests modify LSP server state that could affect other tests
-- - Debugging individual test failures in isolation
--
-- For better performance when running many tests that don't need isolation,
-- consider using helpers.lsp_shared instead.

local M = {}

-- Get path to the built LSP server binary (builds local binary for testing)
function M.get_binary_path()
	-- Find the project root (notedown repo root)
	local script_path = debug.getinfo(1, "S").source:sub(2)
	local helpers_dir = vim.fn.fnamemodify(script_path, ":p:h")
	local project_root = vim.fn.fnamemodify(helpers_dir, ":h:h:h") -- Go up 3 levels from helpers/

	local binary_name = "notedown-lsp-test"
	local binary_path = project_root .. "/" .. binary_name
	local lsp_source = project_root .. "/language-server/"

	-- Build the LSP server from local source
	local build_cmd = string.format("cd %s && go build -o %s %s", project_root, binary_path, lsp_source)
	local result = vim.fn.system(build_cmd)
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		error(string.format("Failed to build LSP server: %s", result))
	end

	return binary_path
end

-- Wait for LSP client to be ready and initialized
function M.wait_for_ready(child, timeout)
	return M.wait_for_lsp_clients(child, timeout)
end

-- Shared function to wait for LSP clients to be available
function M.wait_for_lsp_clients(child, timeout)
	timeout = timeout or 10000 -- 10 second default timeout
	local start_time = vim.loop.now()

	while vim.loop.now() - start_time < timeout do
		local client_count = child.lua_get("#vim.lsp.get_clients()")
		if client_count > 0 then
			-- LSP client found, wait a bit more for it to be fully ready
			vim.loop.sleep(1000)
			return true
		end
		vim.loop.sleep(500)
	end

	print("LSP server did not start within timeout of", timeout, "ms")
	error("LSP server did not start within timeout")
	return false
end

-- Clean up locally built LSP binary
function M.cleanup_binary()
	-- Find the project root (same logic as get_binary_path)
	local script_path = debug.getinfo(1, "S").source:sub(2)
	local helpers_dir = vim.fn.fnamemodify(script_path, ":p:h")
	local project_root = vim.fn.fnamemodify(helpers_dir, ":h:h:h")

	local binary_path = project_root .. "/notedown-lsp-test"

	-- Remove the binary if it exists
	if vim.fn.filereadable(binary_path) == 1 then
		vim.fn.delete(binary_path)
	end
end

-- Setup notedown with mock server for unit testing (no real LSP)
-- @param child: MiniTest child neovim instance
-- @param opts: table (optional) - configuration options
--   - parser_mode: string (default: 'auto') - parser mode to use
--   - notedown_workspaces: table (optional) - list of workspace paths
function M.setup_mock(child, opts)
	opts = opts or {}
	local parser_mode = opts.parser_mode or "auto"
	local workspaces = opts.notedown_workspaces or {}

	local lua_code = string.format(
		[[
		require('notedown').setup({
			server = { cmd = { 'echo', 'mock-server' } },
			parser = {
				mode = %q,
				notedown_workspaces = %s
			}
		})
	]],
		parser_mode,
		vim.inspect(workspaces)
	)

	child.lua(lua_code)
end

-- Setup notedown with LSP server for testing
-- @param child: MiniTest child neovim instance
-- @param workspace: string - workspace path to use as root_dir and notedown_workspace
-- @param opts: table (optional) - additional configuration options
--   - parser_mode: string (default: 'notedown') - parser mode to use
--   - server_name: string (default: 'notedown') - LSP server name
function M.setup(child, workspace, opts)
	opts = opts or {}
	local parser_mode = opts.parser_mode or "notedown"
	local server_name = opts.server_name or "notedown"

	local binary_path = M.get_binary_path()

	-- Use a more structured approach with proper escaping
	local setup_config = {
		server = {
			name = server_name,
			cmd = { binary_path, "serve" },
			root_dir = workspace,
		},
		parser = {
			mode = parser_mode,
			notedown_workspaces = { workspace },
		},
	}

	-- Merge any additional options
	if opts.server then
		setup_config.server = vim.tbl_deep_extend("force", setup_config.server, opts.server)
	end
	if opts.parser then
		setup_config.parser = vim.tbl_deep_extend("force", setup_config.parser, opts.parser)
	end

	-- Build the lua code to execute
	local lua_code = string.format(
		[[
		require('notedown').setup({
			server = {
				name = %q,
				cmd = { %q, 'serve' },
				root_dir = function() return %q end
			},
			parser = {
				mode = %q,
				notedown_workspaces = { %q }
			}
		})
	]],
		server_name,
		binary_path,
		workspace,
		parser_mode,
		workspace
	)

	child.lua(lua_code)
end

return M
