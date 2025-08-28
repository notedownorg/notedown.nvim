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

-- Test utilities for notedown.nvim

local MiniTest = require("mini.test")

local M = {}

-- Create a temporary test workspace
function M.create_test_workspace(path)
	path = path or "/tmp/notedown-test-workspace"

	-- Clean up existing workspace
	vim.fn.system({ "rm", "-rf", path })
	vim.fn.mkdir(path, "p")

	-- Create test files
	local test_files = {
		["README.md"] = "# Test Workspace\n\nThis is a test workspace for [[notes]].",
		["notes.md"] = "# Notes\n\nRefer back to [[README]].",
		["nested/deep.md"] = "# Deep Notes\n\nLink to [[../README]].",
	}

	for file, content in pairs(test_files) do
		local full_path = path .. "/" .. file
		local dir = vim.fn.fnamemodify(full_path, ":h")
		vim.fn.mkdir(dir, "p")

		local handle = io.open(full_path, "w")
		if handle then
			handle:write(content)
			handle:close()
		end
	end

	return path
end

-- Clean up test workspace
function M.cleanup_test_workspace(path)
	path = path or "/tmp/notedown-test-workspace"
	vim.fn.system({ "rm", "-rf", path })
end

-- Create a child Neovim process for testing
function M.new_child_neovim()
	local child = MiniTest.new_child_neovim()

	-- Start with our minimal init (now in helpers/)
	local script_path = debug.getinfo(1, "S").source:sub(2)
	local helpers_dir = vim.fn.fnamemodify(script_path, ":p:h")
	local minimal_init = helpers_dir .. "/minimal_init.lua"

	child.start({ "-u", minimal_init })

	return child
end

-- Helper to wait for condition with timeout
function M.wait_for_condition(condition, timeout)
	timeout = timeout or 3000
	local start_time = vim.loop.hrtime()

	while (vim.loop.hrtime() - start_time) / 1000000 < timeout do
		if condition() then
			return true
		end
		vim.loop.sleep(50)
	end

	return false
end

-- Expect that LSP client exists with given name
function M.expect_lsp_client(child, client_name)
	local clients = child.lua_get("vim.lsp.get_clients()")
	local found = false

	for _, client in ipairs(clients) do
		if client.name == client_name then
			found = true
			break
		end
	end

	MiniTest.expect.equality(found, true, string.format('Expected LSP client "%s" to be active', client_name))
end

-- Expect buffer filetype
function M.expect_buffer_filetype(child, expected_filetype)
	local actual_filetype = child.lua_get("vim.bo.filetype")
	MiniTest.expect.equality(actual_filetype, expected_filetype)
end

-- Write content to a file, creating directories as needed
function M.write_file(path, content)
	local dir = vim.fn.fnamemodify(path, ":h")
	vim.fn.mkdir(dir, "p")

	local handle = io.open(path, "w")
	if handle then
		handle:write(content)
		handle:close()
		return true
	end
	return false
end

return M
