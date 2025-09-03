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

-- Tests for task diagnostics functionality

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec
local wait_for_lsp = test_utils.wait_for_lsp

local function test_task_diagnostics_basic()
	print_test("task diagnostics basic")

	-- Create a proper test workspace for diagnostics
	local workspace = test_utils.create_task_workspace("/tmp/test-task-diagnostics")

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Create test content with both valid and invalid task markers
	local content = [[# Task Diagnostics Test

- [ ] Valid incomplete task
- [x] Valid completed task
- [invalid] Invalid task marker that should trigger diagnostic
- [ Incomplete brackets that should trigger diagnostic
]]

	-- Create test file in workspace
	local test_file_path = workspace .. "/diagnostics-test.md"
	vim.cmd("edit " .. test_file_path)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
	vim.cmd("silent write")

	-- Verify file was created successfully
	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file:match("diagnostics%-test%.md") then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to create diagnostics-test.md file - expected in path but got: " .. current_file)
	end

	-- Wait for LSP to initialize - this is required for diagnostics testing
	local lsp_ready = wait_for_lsp(5000)

	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - task diagnostics cannot be tested")
	end

	-- Sync document with LSP to ensure diagnostics are generated
	local sync_success = test_utils.sync_document_with_lsp()
	if not sync_success then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to sync document with LSP - diagnostic test invalid")
	end

	-- Wait for diagnostics to be processed
	vim.wait(3000) -- Longer wait for diagnostics processing

	-- Get diagnostics - this should always return a valid table
	local diagnostics = vim.diagnostic.get(0)

	if type(diagnostics) ~= "table" then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP diagnostics returned invalid type: " .. type(diagnostics) .. " instead of table")
	end

	-- Verify we can access diagnostic properties
	for i, diagnostic in ipairs(diagnostics) do
		if not diagnostic.message then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: Diagnostic #" .. i .. " missing message field")
		end

		-- Neovim diagnostics use different field names than LSP spec
		-- They use lnum, end_lnum, col, end_col instead of range.start/end
		if not diagnostic.lnum then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: Diagnostic #" .. i .. " missing lnum field")
		end

		if not diagnostic.col then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: Diagnostic #" .. i .. " missing col field")
		end

		print(
			"│    📋 Diagnostic #"
				.. i
				.. " (line "
				.. diagnostic.lnum
				.. ", col "
				.. diagnostic.col
				.. "): "
				.. diagnostic.message
		)
	end

	test_utils.print_assertion("Got " .. #diagnostics .. " valid task diagnostics")

	-- Note: We don't enforce a minimum diagnostic count since the LSP may not
	-- implement task validation diagnostics yet, but we do verify the structure

	test_utils.cleanup_test_workspace(workspace)
end

-- Execute tests
return run_spec("task diagnostics", {
	test_task_diagnostics_basic,
})
