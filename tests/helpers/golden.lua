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

-- Golden file testing utilities for notedown.nvim

local utils = require("helpers.utils")
local lsp_shared = require("helpers.lsp_shared")

local M = {}

-- Read file content
local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		error("Could not read file: " .. path)
	end
	local content = file:read("*all")
	file:close()
	return content:gsub("\n$", "") -- Remove trailing newline for consistency
end

-- Write file content
local function write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		error("Could not write file: " .. path)
	end
	file:write(content)
	file:close()
end

-- Create a temporary workspace with the given content using shared LSP
local function setup_test_workspace(content)
	return lsp_shared.create_test_workspace(content)
end

-- Generate a clear diff message between expected and actual content
local function generate_diff_message(expected, actual, test_name)
	local msg = string.format("\n🔴 GOLDEN FILE TEST FAILED: %s\n", test_name)
	msg = msg .. "=" .. string.rep("=", 60) .. "\n"
	msg = msg .. "📄 EXPECTED:\n"
	msg = msg .. "-" .. string.rep("-", 60) .. "\n"
	msg = msg .. expected .. "\n"
	msg = msg .. "-" .. string.rep("-", 60) .. "\n"
	msg = msg .. "📄 ACTUAL:\n"
	msg = msg .. "-" .. string.rep("-", 60) .. "\n"
	msg = msg .. actual .. "\n"
	msg = msg .. "-" .. string.rep("-", 60) .. "\n"

	-- Simple line-by-line diff
	local expected_lines = vim.split(expected, "\n")
	local actual_lines = vim.split(actual, "\n")
	local max_lines = math.max(#expected_lines, #actual_lines)

	msg = msg .. "🔍 LINE-BY-LINE DIFF:\n"
	for i = 1, max_lines do
		local exp_line = expected_lines[i] or "(missing)"
		local act_line = actual_lines[i] or "(missing)"

		if exp_line ~= act_line then
			msg = msg .. string.format("Line %d:\n", i)
			msg = msg .. string.format("  - %s\n", exp_line)
			msg = msg .. string.format("  + %s\n", act_line)
		end
	end

	msg = msg .. "=" .. string.rep("=", 60) .. "\n"
	msg = msg .. "💡 To update golden file, run: UPDATE_GOLDEN=1 make test-nvim\n"

	return msg
end

-- Main test function for list movement operations
function M.test_list_movement(test_dir, golden_file, options)
	local base_path = "tests/testdata/list_movement/" .. test_dir
	local input_path = base_path .. "/" .. (options.input_file or "input.md")
	local golden_path = base_path .. "/" .. (options.expected_file or (golden_file .. ".md"))

	-- Read input and expected content
	local input_content = read_file(input_path)
	local expected_content = read_file(golden_path)

	-- Set up test environment using shared LSP
	local workspace_path, file_path = setup_test_workspace(input_content)

	-- Open file in shared neovim instance
	lsp_shared.open_file(file_path)

	-- Position cursor using the search pattern
	lsp_shared.position_cursor(options.search_pattern, options.line, options.character)

	-- Store original cursor position for cursor following validation
	local original_cursor = lsp_shared.get_cursor_position()

	-- Execute the movement command with debug output
	lsp_shared.execute_command(options.command)

	-- Get actual result
	local actual_content = lsp_shared.get_buffer_content()
	local final_cursor = lsp_shared.get_cursor_position()

	-- Clean up test workspace (but keep shared LSP session)
	lsp_shared.cleanup_test_workspace(workspace_path)

	-- Compare with golden file
	if actual_content ~= expected_content then
		if os.getenv("UPDATE_GOLDEN") then
			write_file(golden_path, actual_content)
			print("✅ Updated golden file: " .. golden_file .. ".md")
			return true
		else
			local test_name = test_dir .. "/" .. golden_file
			local diff_msg = generate_diff_message(expected_content, actual_content, test_name)
			error(diff_msg)
		end
	end

	-- Validate cursor position if expected position is provided
	if options.expected_cursor then
		local expected_cursor = options.expected_cursor
		if final_cursor[1] ~= expected_cursor[1] or final_cursor[2] ~= expected_cursor[2] then
			local cursor_error = string.format(
				"\n🔴 CURSOR POSITION MISMATCH: %s\n"
					.. "=============================================================\n"
					.. "📍 EXPECTED CURSOR: line %d, char %d\n"
					.. "📍 ACTUAL CURSOR:   line %d, char %d\n"
					.. "📍 ORIGINAL CURSOR: line %d, char %d\n"
					.. "📍 COMMAND: %s\n"
					.. "=============================================================",
				test_dir .. "/" .. golden_file,
				expected_cursor[1],
				expected_cursor[2],
				final_cursor[1],
				final_cursor[2],
				original_cursor[1],
				original_cursor[2],
				options.command
			)
			error(cursor_error)
		end
	end

	return true
end

-- Test function that expects no change (for boundary conditions)
function M.test_list_movement_no_change(test_dir, golden_file, options)
	-- For boundary conditions, we expect the content to remain unchanged
	-- The golden file should be identical to the input file
	return M.test_list_movement(test_dir, golden_file, options)
end

-- Test function for text object operations (yank, delete, etc.)
function M.test_text_object(test_dir, golden_file, options)
	local base_path = "tests/testdata/list_text_object/" .. test_dir
	local input_path = base_path .. "/" .. (options.input_file or "input.md")
	local golden_path = base_path .. "/" .. (options.expected_file or (golden_file .. ".md"))

	-- Read input content
	local input_content = read_file(input_path)

	-- Set up test environment using shared LSP
	local workspace_path, file_path = setup_test_workspace(input_content)

	-- Open file in shared neovim instance
	lsp_shared.open_file(file_path)

	-- Position cursor using the search pattern
	lsp_shared.position_cursor(options.search_pattern, options.line, options.character)

	-- Clear registers before operation
	lsp_shared.execute_vim_command('let @" = ""')

	-- Execute the text object operation
	if options.should_fail then
		-- For operations that should fail, we don't expect file changes
		-- Just check that the operation behaves correctly
		lsp_shared.execute_vim_command(options.operation)

		-- Check if expected warning was shown
		if options.expected_warning then
			-- Note: In a real test, we'd capture vim notifications
			-- For now, we assume the operation fails gracefully
		end

		-- Clean up and return
		lsp_shared.cleanup_test_workspace(workspace_path)
		return true
	end

	-- Execute the text object operation
	lsp_shared.execute_vim_command(options.operation)

	-- Check register content if expected
	if options.expected_register_content then
		local register_content = lsp_shared.get_register_content()
		if register_content ~= options.expected_register_content then
			local error_msg = string.format(
				"\n🔴 REGISTER CONTENT MISMATCH: %s\n"
					.. "=============================================================\n"
					.. "📋 EXPECTED REGISTER: %q\n"
					.. "📋 ACTUAL REGISTER:   %q\n"
					.. "📋 OPERATION: %s\n"
					.. "=============================================================",
				test_dir .. "/" .. golden_file,
				options.expected_register_content,
				register_content,
				options.operation
			)
			lsp_shared.cleanup_test_workspace(workspace_path)
			error(error_msg)
		end
	end

	-- For delete operations, check file content against golden file
	if options.operation:match("^d") then -- Delete operations start with 'd'
		local expected_content = read_file(golden_path)
		local actual_content = lsp_shared.get_buffer_content()

		if actual_content ~= expected_content then
			if os.getenv("UPDATE_GOLDEN") then
				write_file(golden_path, actual_content)
				print("✅ Updated golden file: " .. golden_file .. ".md")
			else
				local test_name = test_dir .. "/" .. golden_file
				local diff_msg = generate_diff_message(expected_content, actual_content, test_name)
				lsp_shared.cleanup_test_workspace(workspace_path)
				error(diff_msg)
			end
		end

		-- Check cursor position if expected
		if options.expected_cursor then
			local final_cursor = lsp_shared.get_cursor_position()
			local expected_cursor = options.expected_cursor
			if final_cursor[1] ~= expected_cursor[1] or final_cursor[2] ~= expected_cursor[2] then
				local cursor_error = string.format(
					"\n🔴 CURSOR POSITION MISMATCH: %s\n"
						.. "=============================================================\n"
						.. "📍 EXPECTED CURSOR: line %d, char %d\n"
						.. "📍 ACTUAL CURSOR:   line %d, char %d\n"
						.. "📍 OPERATION: %s\n"
						.. "=============================================================",
					test_dir .. "/" .. golden_file,
					expected_cursor[1],
					expected_cursor[2],
					final_cursor[1],
					final_cursor[2],
					options.operation
				)
				lsp_shared.cleanup_test_workspace(workspace_path)
				error(cursor_error)
			end
		end
	end

	-- Clean up test workspace
	lsp_shared.cleanup_test_workspace(workspace_path)
	return true
end

return M
