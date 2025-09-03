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

-- Shared test utilities for notedown.nvim test suite

local M = {
	-- State tracking for automatic cleanup
	current_workspace = nil,
	cleanup_callbacks = {},
}

-- Formatted output functions
function M.print_spec_start(name)
	print("┌─ 📁 " .. name)
end

function M.print_spec_end(name)
	print("└─ SUCCESS: All " .. name .. " tests passed!")
end

function M.print_test(name)
	print("│  ├─ ⚡ " .. name)
end

function M.print_assertion(message)
	print("│  │    ✔️ " .. (message or "Assertion passed"))
end

function M.print_failure(message)
	print("FAIL: " .. (message or "Test failed"))
end

-- Wait for LSP to initialize with timeout
function M.wait_for_lsp(timeout_ms)
	timeout_ms = timeout_ms or 5000
	return vim.wait(timeout_ms, function()
		return #vim.lsp.get_clients() > 0
	end)
end

-- Get the notedown LSP client
function M.get_notedown_client()
	local clients = vim.lsp.get_clients()
	for _, client in ipairs(clients) do
		if client.name == "notedown" then
			return client
		end
	end
	return nil
end

-- Make a synchronous LSP request with proper error handling
function M.lsp_request_sync(method, params, timeout_ms)
	timeout_ms = timeout_ms or 3000
	local client = M.get_notedown_client()
	if not client then
		error("No notedown LSP client found")
	end

	local result, err = client.request_sync(method, params, timeout_ms)
	if err then
		error("LSP request failed: " .. vim.inspect(err))
	end

	return result and result.result
end

-- Ensure document is synchronized with LSP server
function M.sync_document_with_lsp(bufnr)
	bufnr = bufnr or 0
	local client = M.get_notedown_client()
	if not client then
		return false
	end

	-- Send didOpen notification to ensure document is known to server
	local uri = vim.uri_from_bufnr(bufnr)
	local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

	client.notify("textDocument/didOpen", {
		textDocument = {
			uri = uri,
			languageId = filetype,
			version = 1,
			text = content,
		},
	})

	-- Wait a moment for processing
	vim.wait(200)
	return true
end

-- Run a spec with a list of test functions
function M.run_spec(spec_name, test_functions)
	M.print_spec_start(spec_name)

	for _, test_func in ipairs(test_functions) do
		local success, err = pcall(test_func)
		if not success then
			M.print_failure("Test failed: " .. err)
			return false
		end
	end

	M.print_spec_end(spec_name)
	return true
end

-- Set the current workspace for automatic cleanup tracking
function M.set_workspace(workspace)
	M.current_workspace = workspace
	return workspace
end

-- Add a cleanup callback function
function M.add_cleanup_callback(callback)
	table.insert(M.cleanup_callbacks, callback)
end

-- Clear all state (called at start of each test)
function M.clear_test_state()
	M.current_workspace = nil
	M.cleanup_callbacks = {}
end

-- Perform all cleanup operations
function M.cleanup_all()
	-- Run custom cleanup callbacks first
	for _, callback in ipairs(M.cleanup_callbacks) do
		pcall(callback) -- Use pcall to prevent cleanup errors from breaking tests
	end

	-- Clean up tracked workspace
	if M.current_workspace then
		M.cleanup_test_workspace(M.current_workspace)
	end

	-- Clear state
	M.clear_test_state()
end

-- Critical test failure utility with automatic cleanup
function M.fail(message, context, workspace_override)
	context = context or {}

	-- Use provided workspace, or fall back to tracked workspace
	local workspace_to_clean = workspace_override or M.current_workspace

	-- Perform all cleanup
	M.cleanup_all()

	-- Format error message with context
	local error_msg = "CRITICAL: " .. message
	if context.expected then
		error_msg = error_msg .. " (expected: " .. tostring(context.expected) .. ")"
	end
	if context.actual then
		error_msg = error_msg .. " (actual: " .. tostring(context.actual) .. ")"
	end
	if context.details then
		error_msg = error_msg .. " - " .. context.details
	end

	error(error_msg)
end

-- Assertion with automatic workspace cleanup on failure
function M.assert_or_fail(condition, message, context)
	if not condition then
		M.fail(message, context)
	end
	-- Only print assertion message if explicitly requested
	if context and context.print_success then
		M.print_assertion(message or "Assertion passed")
	end
end

-- Standard assertion function with formatted output
function M.assert_equals(actual, expected, message)
	if actual ~= expected then
		error((message or "Assertion failed") .. ": expected " .. tostring(expected) .. " but got " .. tostring(actual))
	end
	M.print_assertion(message)
end

-- Assertion for checking if text contains a pattern
function M.assert_contains(text, pattern, message)
	if not string.match(text, pattern) then
		error((message or "Assertion failed") .. ": expected '" .. text .. "' to contain '" .. pattern .. "'")
	end
	M.print_assertion(message)
end

-- Workspace creation and cleanup utilities

-- Create a test workspace with optional test files
function M.create_test_workspace(path, test_files)
	path = path or "/tmp/notedown-test-workspace"
	vim.fn.system({ "rm", "-rf", path })
	vim.fn.mkdir(path, "p")

	-- Create .notedown directory to make it a notedown workspace
	vim.fn.mkdir(path .. "/.notedown", "p")

	-- Create test files if provided
	if test_files then
		for file, content in pairs(test_files) do
			local full_path = path .. "/" .. file
			local handle = io.open(full_path, "w")
			if handle then
				handle:write(content)
				handle:close()
			end
		end
	end

	-- Automatically track this workspace for cleanup
	return M.set_workspace(path)
end

-- Clean up test workspace
function M.cleanup_test_workspace(path)
	vim.fn.system({ "rm", "-rf", path })
end

-- Create a standard test workspace with common wikilink test files
function M.create_wikilink_test_workspace(path)
	path = path or "/tmp/notedown-wikilink-test"
	local test_files = {
		["README.md"] = "# Test Workspace\n\nThis is a test workspace for [[notes]].",
		["notes.md"] = "# Notes\n\nRefer back to [[README]].",
	}
	return M.create_test_workspace(path, test_files) -- Already tracks workspace
end

-- Create a test workspace with a single markdown file and open it
function M.create_content_test_workspace(content, path, filename)
	path = path or "/tmp/notedown-content-test"
	filename = filename or "test.md"
	vim.fn.system({ "rm", "-rf", path })
	vim.fn.mkdir(path, "p")

	-- Create .notedown directory to make it a notedown workspace
	vim.fn.mkdir(path .. "/.notedown", "p")

	-- Write content to file
	local file_path = path .. "/" .. filename
	local handle = io.open(file_path, "w")
	if handle then
		handle:write(content)
		handle:close()
	end

	-- Change to workspace and open file
	vim.cmd("cd " .. path)
	vim.cmd("edit " .. file_path)

	return path
end

-- Create a regular workspace WITHOUT .notedown directory (for testing non-notedown behavior)
function M.create_non_notedown_workspace(path, test_files)
	path = path or "/tmp/non-notedown-workspace"
	vim.fn.system({ "rm", "-rf", path })
	vim.fn.mkdir(path, "p")

	-- Don't create .notedown directory - this is not a notedown workspace

	-- Create test files if provided
	if test_files then
		for file, content in pairs(test_files) do
			local full_path = path .. "/" .. file
			local handle = io.open(full_path, "w")
			if handle then
				handle:write(content)
				handle:close()
			end
		end
	end

	return path
end

-- Create a task workspace with settings.yaml and task content
function M.create_task_workspace(path)
	path = path or "/tmp/task-test-workspace"
	vim.fn.system({ "rm", "-rf", path })
	vim.fn.mkdir(path, "p")

	-- Create .notedown directory
	vim.fn.mkdir(path .. "/.notedown", "p")

	-- Create basic task settings
	local settings = [[
tasks:
  states:
    - value: " "
      name: "todo"
      description: "A task that needs to be completed"
    - value: "x"
      name: "done" 
      description: "A completed task"
      conceal: "✅"
]]

	local handle = io.open(path .. "/.notedown/settings.yaml", "w")
	if handle then
		handle:write(settings)
		handle:close()
	end

	-- Create test file with tasks
	local task_content = [[# Task List

- [ ] First todo task
- [x] Completed task
- [ ] Second todo task
  - [ ] Nested task
  - [x] Nested completed

## More Tasks

- [ ] Another task
]]

	handle = io.open(path .. "/tasks.md", "w")
	if handle then
		handle:write(task_content)
		handle:close()
	end

	-- Automatically track this workspace for cleanup
	return M.set_workspace(path)
end

return M
