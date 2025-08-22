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

-- Tests for task diagnostics functionality in Neovim

local MiniTest = require("mini.test")
local utils = require("helpers.utils")
local lsp = require("helpers.lsp_dedicated")

local T = MiniTest.new_set()

-- Test workspace setup for task diagnostics tests
local function setup_task_workspace(path)
	local workspace = utils.create_test_workspace(path)

	-- Create test file with valid and invalid task states
	utils.write_file(
		workspace .. "/tasks.md",
		[[# Task List

## Valid Tasks
- [ ] Todo task
- [x] Done task
- [X] Done task (uppercase alias)
- [completed] Completed task (alias)

## Invalid Tasks
- [invalid] This should generate a diagnostic
- [?] Question mark is invalid
- [wip] Work in progress (not in default config)
- [todo] Not a valid state value

## Mixed List
1. [x] Valid numbered task
2. [bad] Invalid numbered task
   - [x] Valid nested task
   - [error] Invalid nested task

## Non-task checkboxes (should be ignored)
This is a paragraph with [invalid] checkbox that should not generate diagnostics.

Regular list:
- This is a regular list item [invalid] in middle
- [wrong] This should generate diagnostic

Some text with [x] checkbox not in list.
]]
	)

	return workspace
end

T["task diagnostics"] = MiniTest.new_set()

T["task diagnostics"]["detects invalid task states"] = function()
	local workspace = setup_task_workspace("/tmp/test-task-diagnostics")
	local child = utils.new_child_neovim()

	-- Setup LSP
	lsp.setup(child, workspace)

	-- Open the file with invalid task states
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Ensure document is properly opened in LSP
	child.lua([[
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
				}
			})
		end
	]])

	-- Wait for diagnostics to be computed and published
	vim.loop.sleep(2000)

	-- Get diagnostics for the current buffer
	local diagnostics = child.lua_get("vim.diagnostic.get(0)")

	-- Verify we got diagnostics
	MiniTest.expect.equality(type(diagnostics), "table")
	MiniTest.expect.equality(#diagnostics > 0, true, "Should have diagnostics for invalid task states")

	-- Expected invalid states and their count
	local expected_invalid_states = {
		"invalid",
		"?",
		"wip",
		"todo",
		"bad",
		"error",
		"wrong",
	}

	-- Count task diagnostics (from notedown-task source)
	local task_diagnostics = {}
	local task_diag_count = 0

	for _, diag in ipairs(diagnostics) do
		if diag.source == "notedown-task" then
			task_diag_count = task_diag_count + 1
			table.insert(task_diagnostics, diag)
		end
	end

	-- Should find exactly the expected number of invalid task states
	MiniTest.expect.equality(
		task_diag_count,
		#expected_invalid_states,
		"Should find " .. #expected_invalid_states .. " invalid task states"
	)

	-- Verify each diagnostic has correct properties
	for _, diag in ipairs(task_diagnostics) do
		-- Should be warning severity
		MiniTest.expect.equality(diag.severity, 2, "Should be Warning severity (2)")

		-- Should be from notedown-task source
		MiniTest.expect.equality(diag.source, "notedown-task", "Should be from notedown-task source")

		-- Should have the invalid-task-state code
		MiniTest.expect.equality(diag.code, "invalid-task-state", "Should have invalid-task-state code")

		-- Message should contain error description
		local message = diag.message or ""
		MiniTest.expect.equality(
			string.find(message, "Invalid task state") ~= nil,
			true,
			"Should contain 'Invalid task state' in message"
		)
		MiniTest.expect.equality(
			string.find(message, "Valid states:") ~= nil,
			true,
			"Should list valid states in message"
		)

		-- Should mention default valid states
		MiniTest.expect.equality(string.find(message, " ") ~= nil, true, "Should mention space (empty) as valid state")
		MiniTest.expect.equality(string.find(message, "x") ~= nil, true, "Should mention 'x' as valid state")
	end

	-- Verify that specific invalid states are detected
	local detected_states = {}
	for _, diag in ipairs(task_diagnostics) do
		local message = diag.message or ""
		-- Extract state from message: "Invalid task state 'STATE'..."
		local state_start = string.find(message, "'")
		if state_start then
			local state_end = string.find(message, "'", state_start + 1)
			if state_end then
				local state = string.sub(message, state_start + 1, state_end - 1)
				table.insert(detected_states, state)
			end
		end
	end

	-- Check that all expected invalid states were detected
	for _, expected_state in ipairs(expected_invalid_states) do
		local found = false
		for _, detected_state in ipairs(detected_states) do
			if detected_state == expected_state then
				found = true
				break
			end
		end
		MiniTest.expect.equality(found, true, "Should detect invalid state: '" .. expected_state .. "'")
	end

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task diagnostics"]["ignores valid task states"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-valid-tasks")
	local child = utils.new_child_neovim()

	-- Create file with only valid task states
	utils.write_file(
		workspace .. "/valid-tasks.md",
		[[# Valid Task List

- [ ] Todo task
- [x] Done task
- [X] Done task (uppercase)
- [completed] Completed task

1. [ ] Numbered todo
2. [x] Numbered done

## Regular content
This is regular text with no tasks.

- Regular list item
- Another regular item
]]
	)

	-- Setup LSP
	lsp.setup(child, workspace)

	-- Open the file with only valid tasks
	child.lua('vim.cmd("edit ' .. workspace .. '/valid-tasks.md")')
	lsp.wait_for_ready(child)

	-- Ensure document is properly opened in LSP
	child.lua([[
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
				}
			})
		end
	]])

	-- Wait for diagnostics processing
	vim.loop.sleep(2000)

	-- Get diagnostics for the current buffer
	local diagnostics = child.lua_get("vim.diagnostic.get(0)")

	-- Count task diagnostics (should be zero)
	local task_diag_count = 0
	for _, diag in ipairs(diagnostics) do
		if diag.source == "notedown-task" then
			task_diag_count = task_diag_count + 1
		end
	end

	-- Should have no task diagnostics for valid tasks
	MiniTest.expect.equality(task_diag_count, 0, "Should have no task diagnostics for valid tasks")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task diagnostics"]["respects workspace configuration"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-task-config")
	local child = utils.new_child_neovim()

	-- Create custom workspace configuration with additional task states
	utils.write_file(
		workspace .. "/.notedown.yaml",
		[[tasks:
  states:
    - value: " "
      name: "todo"
      description: "A task that needs to be completed"
    - value: "x"
      name: "done"
      description: "A completed task"
      aliases: ["X", "completed"]
    - value: "wip"
      name: "in-progress"
      description: "Work in progress"
      aliases: ["~", "working"]
    - value: "blocked"
      name: "blocked"
      description: "Blocked task"
]]
	)

	-- Create test file with states that should always be invalid regardless of config
	utils.write_file(
		workspace .. "/custom-tasks.md",
		[[# Configuration Test

## Core functionality test
- [ ] Todo task
- [x] Done task
- [invalid] This should always be invalid
- [?] Question mark should always be invalid

## Regular content
This is regular text with no tasks.
]]
	)

	-- Wait a bit for file system to settle
	vim.loop.sleep(500)

	-- Setup LSP
	lsp.setup(child, workspace)

	-- Open the file
	child.lua('vim.cmd("edit ' .. workspace .. '/custom-tasks.md")')
	lsp.wait_for_ready(child)

	-- Ensure document is opened in LSP
	child.lua([[
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
				}
			})
		end
	]])

	-- Wait for diagnostics
	vim.loop.sleep(3000)

	-- Get diagnostics
	local diagnostics = child.lua_get("vim.diagnostic.get(0)")

	-- Count task diagnostics
	local task_diagnostics = {}
	for _, diag in ipairs(diagnostics) do
		if diag.source == "notedown-task" then
			table.insert(task_diagnostics, diag)
		end
	end

	-- Should have diagnostics for the invalid states
	MiniTest.expect.equality(#task_diagnostics >= 2, true, "Should have at least 2 task diagnostics for invalid states")

	-- Verify diagnostics have correct properties and detect the expected invalid states
	local detected_invalid_states = {}
	for _, diag in ipairs(task_diagnostics) do
		-- Should be warning severity
		MiniTest.expect.equality(diag.severity, 2, "Should be Warning severity (2)")

		-- Should be from notedown-task source
		MiniTest.expect.equality(diag.source, "notedown-task", "Should be from notedown-task source")

		-- Should have the invalid-task-state code
		MiniTest.expect.equality(diag.code, "invalid-task-state", "Should have invalid-task-state code")

		-- Extract state from message for verification
		local message = diag.message or ""
		local state_start = string.find(message, "'")
		if state_start then
			local state_end = string.find(message, "'", state_start + 1)
			if state_end then
				local state = string.sub(message, state_start + 1, state_end - 1)
				table.insert(detected_invalid_states, state)
			end
		end
	end

	-- Should detect both 'invalid' and '?' as invalid states
	local expected_invalid = { "invalid", "?" }
	for _, expected in ipairs(expected_invalid) do
		local found = false
		for _, detected in ipairs(detected_invalid_states) do
			if detected == expected then
				found = true
				break
			end
		end
		MiniTest.expect.equality(found, true, "Should detect invalid state: '" .. expected .. "'")
	end

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

return T
