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

-- Tests for task state completion functionality

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec
local wait_for_lsp = test_utils.wait_for_lsp

local function test_task_state_completion_suggestions()
	print_test("task state completion suggestions")

	test_utils.clear_test_state() -- Initialize clean state
	local workspace = test_utils.create_task_workspace("/tmp/test-task-completion")

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Create test file with partial task state
	local test_content = [[# Test Task States

- [ ] Complete task
- [  ] Partial task for completion testing
- [x] Already completed
]]

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write test-completion.md")

	-- Wait for LSP to initialize
	local lsp_ready = wait_for_lsp(5000)
	test_utils.assert_or_fail(lsp_ready, "LSP did not initialize within timeout - task completion cannot be tested")

	-- Sync document with LSP
	local sync_success = test_utils.sync_document_with_lsp()
	test_utils.assert_or_fail(sync_success, "Failed to sync document with LSP - completion test invalid")

	-- Position cursor inside task brackets for completion
	local search_result = vim.fn.search("Partial task")
	test_utils.assert_or_fail(search_result > 0, "Could not find 'Partial task' in test content - test setup failed")

	vim.api.nvim_win_set_cursor(0, { 4, 3 }) -- Position cursor inside [  ]

	-- Request completion at cursor position
	local completion_params = {
		textDocument = { uri = vim.uri_from_bufnr(0) },
		position = { line = 3, character = 3 }, -- Inside the brackets [|  ]
	}

	local success, completion_result =
		pcall(test_utils.lsp_request_sync, "textDocument/completion", completion_params, 3000)

	test_utils.assert_or_fail(success, "LSP completion request failed", {
		details = tostring(completion_result),
	})

	test_utils.assert_or_fail(completion_result ~= nil, "LSP returned nil completion result")

	local items = completion_result.items or {}
	test_utils.assert_or_fail(#items > 0, "LSP returned no completion items - task state completion not working", {
		actual = #items,
		expected = "> 0",
	})

	test_utils.print_assertion("Got " .. #items .. " task state completion items")

	-- Look for essential task states
	local found_states = {}
	for _, item in ipairs(items) do
		test_utils.assert_or_fail(item.label ~= nil, "Completion item missing label field")
		found_states[item.label] = true
		test_utils.print_assertion("Found completion: " .. item.label)
	end

	-- Must have at least basic todo and done states
	local required_states = { " ", "x" } -- todo and done states
	for _, state in ipairs(required_states) do
		test_utils.assert_or_fail(found_states[state], "Missing required task state '" .. state .. "' in completions", {
			actual = "not found",
			expected = "present",
		})
	end

	test_utils.print_assertion("Found all required task state completions")
	test_utils.cleanup_all() -- Clean up automatically tracked workspace
end

local function test_task_state_recognition()
	print_test("task state recognition")

	local workspace = test_utils.create_task_workspace("/tmp/test-task-states")

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Open file with tasks
	vim.cmd("edit tasks.md")
	if not vim.api.nvim_buf_get_name(0):match("tasks%.md") then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to open tasks.md file for task recognition test")
	end

	-- Wait for LSP to initialize
	local lsp_ready = wait_for_lsp(5000)

	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - task recognition cannot be tested")
	end

	-- Sync document with LSP
	local sync_success = test_utils.sync_document_with_lsp()
	if not sync_success then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to sync document with LSP - recognition test invalid")
	end

	-- Check that both todo and completed tasks are present
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines == 0 then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Buffer is empty - task workspace creation failed")
	end

	local content = table.concat(lines, "\n")

	-- Must find both uncompleted and completed tasks
	local has_todo = string.match(content, "%- %[ %]") ~= nil
	local has_done = string.match(content, "%- %[x%]") ~= nil

	if not has_todo then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: No uncompleted tasks found in test workspace - workspace creation failed")
	end

	if not has_done then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: No completed tasks found in test workspace - workspace creation failed")
	end

	assert_equals(has_todo, true, "Should find uncompleted tasks")
	assert_equals(has_done, true, "Should find completed tasks")

	-- Test diagnostics for task validation
	vim.wait(2000) -- Wait for diagnostics to be processed
	local diagnostics = vim.diagnostic.get(0)

	-- Diagnostics should be a valid array (even if empty)
	if type(diagnostics) ~= "table" then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP diagnostics returned invalid type: " .. type(diagnostics))
	end

	test_utils.print_assertion("Got " .. #diagnostics .. " task diagnostics")

	test_utils.cleanup_test_workspace(workspace)
end

local function test_task_completion_filtering()
	print_test("task completion filtering")

	local workspace = test_utils.create_task_workspace("/tmp/test-task-filtering")

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Create test content with partial input
	local test_content = [[# Task Completion Filtering

- [x] Already done
- [ ] Need to complete
]]

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))

	-- Create the file in the workspace
	local test_file_path = workspace .. "/filtering-test.md"
	vim.cmd("edit " .. test_file_path)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write")

	-- Verify file was created successfully
	local current_file = vim.api.nvim_buf_get_name(0)
	if not current_file:match("filtering%-test%.md") then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to create filtering-test.md file - expected in path but got: " .. current_file)
	end

	-- Wait for LSP to initialize
	local lsp_ready = wait_for_lsp(5000)

	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - filtering test cannot proceed")
	end

	-- Sync document with LSP
	local sync_success = test_utils.sync_document_with_lsp()
	if not sync_success then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: Failed to sync document with LSP - filtering test invalid")
	end

	-- Test completion when cursor is in different task contexts
	local test_positions = {
		{ line = 2, char = 3, desc = "inside completed task brackets" },
		{ line = 3, char = 3, desc = "inside todo task brackets" },
	}

	for i, pos in ipairs(test_positions) do
		-- Verify the line exists and has expected content
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		if pos.line + 1 > #lines then
			test_utils.cleanup_test_workspace(workspace)
			error(
				"CRITICAL: Test position line " .. pos.line .. " doesn't exist in buffer (only " .. #lines .. " lines)"
			)
		end

		local line_content = lines[pos.line + 1] -- Lua is 1-based
		if not line_content:match("^%- %[.%]") then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: Line " .. pos.line .. " does not contain task format: '" .. line_content .. "'")
		end

		-- Position cursor inside task brackets
		vim.api.nvim_win_set_cursor(0, { pos.line + 1, pos.char }) -- Lua uses 1-based line numbers

		local completion_params = {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = pos.line, character = pos.char },
		}

		local success, completion_result =
			pcall(test_utils.lsp_request_sync, "textDocument/completion", completion_params, 3000)

		if not success then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: LSP completion request failed for " .. pos.desc .. ": " .. tostring(completion_result))
		end

		if not completion_result then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: LSP returned nil completion result for " .. pos.desc)
		end

		local items = completion_result.items or {}
		if #items == 0 then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: No completions found for " .. pos.desc .. " - task completion filtering failed")
		end

		test_utils.print_assertion("Got " .. #items .. " completions for " .. pos.desc)

		-- Verify completion items have proper structure
		local valid_completions = 0
		for _, item in ipairs(items) do
			if not item.label then
				test_utils.cleanup_test_workspace(workspace)
				error("CRITICAL: Completion item missing label field for " .. pos.desc)
			end

			if not item.kind then
				test_utils.cleanup_test_workspace(workspace)
				error("CRITICAL: Completion item '" .. item.label .. "' missing kind field for " .. pos.desc)
			end

			valid_completions = valid_completions + 1
			test_utils.print_assertion("Completion '" .. item.label .. "' has proper structure")
		end

		if valid_completions == 0 then
			test_utils.cleanup_test_workspace(workspace)
			error("CRITICAL: No valid completion items found for " .. pos.desc)
		end

		-- Both positions should return the same completion count for consistency
		if i == 1 then
			first_completion_count = #items
		elseif #items ~= first_completion_count then
			test_utils.cleanup_test_workspace(workspace)
			error(
				"CRITICAL: Inconsistent completion count - first position had "
					.. first_completion_count
					.. " items, second position had "
					.. #items
					.. " items"
			)
		end
	end

	test_utils.print_assertion("Task completion filtering works consistently across different task states")
	test_utils.cleanup_test_workspace(workspace)
end

-- Execute tests
return run_spec("task completion", {
	test_task_state_completion_suggestions,
	test_task_state_recognition,
	test_task_completion_filtering,
})
