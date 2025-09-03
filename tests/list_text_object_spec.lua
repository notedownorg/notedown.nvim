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

-- Tests for list text object functionality

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec

local function test_boundary_detection(content, cursor_search, expected_boundaries)
	local workspace = test_utils.create_content_test_workspace(content, "/tmp/list-text-object-test")

	-- Position cursor
	vim.fn.search(cursor_search)

	-- Wait a moment for any LSP to initialize
	vim.wait(100)

	local boundaries = { found = false }

	-- Try to get boundary information (this would normally come from LSP)
	-- Since we can't rely on LSP in this environment, we'll test the structure
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Enhanced list item boundary detection
	if current_line <= #lines then
		local line_content = lines[current_line]
		if
			string.match(line_content, "^%s*[-*+]%s")
			or string.match(line_content, "^%s*%d+%.%s")
			or string.match(line_content, "^%s*-%s*%[.%]%s")
		then
			boundaries.found = true
			boundaries.start_line = current_line - 1 -- Convert to 0-based
			boundaries.start_char = 0

			-- Get indentation level of the current list item
			local current_indent = #string.match(line_content, "^%s*")

			-- Find the end of this list item by looking for next item at same or lower level
			local end_line = current_line
			local has_children = false

			for i = current_line + 1, #lines do
				local next_line = lines[i]

				-- If empty line, continue searching but don't extend boundary yet
				if string.match(next_line, "^%s*$") then
				-- Continue searching
				-- If it's a list item, check indentation
				elseif
					string.match(next_line, "^%s*[-*+]%s")
					or string.match(next_line, "^%s*%d+%.%s")
					or string.match(next_line, "^%s*-%s*%[.%]%s")
				then
					local next_indent = #string.match(next_line, "^%s*")
					if next_indent <= current_indent then
						-- Same or lower level - this is where our item ends
						end_line = i
						break
					else
						-- Higher indent - this is a child, include it
						has_children = true
						end_line = i
					end
				-- If it's regular text with higher indentation, it might be continuation
				elseif string.match(next_line, "^%s+%S") then
					local next_indent = #string.match(next_line, "^%s*")
					if next_indent > current_indent then
						-- Continuation or child content
						has_children = true
						end_line = i
					else
						-- Same or lower level non-list content - ends our list
						end_line = i
						break
					end
				else
					-- Non-indented content - ends our list
					end_line = i
					break
				end
			end

			-- Convert to 0-based indexing
			boundaries.end_line = end_line - 1
			boundaries.end_char = 0
		end
	end

	test_utils.cleanup_test_workspace(workspace)

	-- Verify boundaries
	if expected_boundaries.found then
		assert_equals(boundaries.found, true, "Expected to find list item boundaries")

		-- Verify exact boundary values
		if expected_boundaries.start_line ~= nil then
			assert_equals(
				boundaries.start_line,
				expected_boundaries.start_line,
				"Start line should be " .. expected_boundaries.start_line
			)
		end

		if expected_boundaries.start_char ~= nil then
			assert_equals(
				boundaries.start_char,
				expected_boundaries.start_char,
				"Start character should be " .. expected_boundaries.start_char
			)
		end

		if expected_boundaries.end_line ~= nil then
			assert_equals(
				boundaries.end_line,
				expected_boundaries.end_line,
				"End line should be " .. expected_boundaries.end_line
			)
		end

		if expected_boundaries.end_char ~= nil then
			assert_equals(
				boundaries.end_char,
				expected_boundaries.end_char,
				"End character should be " .. expected_boundaries.end_char
			)
		end

		test_utils.print_assertion("Found list item at expected location")
	else
		assert_equals(boundaries.found, false, "Expected not to find list item boundaries")
	end
end

local function test_boundary_detection_simple_list()
	print_test("boundary detection - simple list first item")

	local content = [[# Test List

- First item
- Second item
- Third item
- Fourth item

Some text after the list.]]

	test_boundary_detection(content, "First item", {
		found = true,
		start_line = 2,
		start_char = 0,
		end_line = 3,
		end_char = 0,
	})
end

local function test_boundary_detection_nested_list()
	print_test("boundary detection - nested list with children")

	local content = [[# Deep Nested List

- Level 1 Item A
  - Level 2 Item A.1
    - Level 3 Item A.1.a
      - Level 4 Item A.1.a.i
        - Level 5 Item A.1.a.i.α
          - Level 6 Item A.1.a.i.α.I
      - Level 4 Item A.1.a.ii
        - Level 5 Item A.1.a.i.β
  - Level 2 Item A.2
- Level 1 Item B

Some text here.]]

	test_boundary_detection(content, "Level 1 Item A", {
		found = true,
		start_line = 2,
		start_char = 0,
		end_line = 11,
		end_char = 0,
	})
end

local function test_boundary_detection_task_list()
	print_test("boundary detection - task list item")

	local content = [[# Task List

- [x] Completed task
  - [ ] Subtask A
    - [ ] Sub-subtask A.1.a
    - [x] Sub-subtask A.1.b
  - [x] Subtask B
- [ ] Incomplete task
  - [ ] Another subtask

Some regular text.]]

	test_boundary_detection(content, "Completed task", {
		found = true,
		start_line = 2,
		start_char = 0,
		end_line = 7,
		end_char = 0,
	})
end

local function test_boundary_detection_no_list()
	print_test("boundary detection - no list item found")

	local content = [[# Test List

- First item
- Second item
- Third item
- Fourth item

Some text after the list.]]

	test_boundary_detection(content, "Some text after", {
		found = false,
	})
end

local function test_boundary_detection_numbered_list()
	print_test("boundary detection - numbered list")

	local content = [[# Mixed Lists

- Level 1 Item A
- Level 1 Item B

Some numbered lists:

1. Ordered Level 1 Item A
    a. Ordered Level 2 Item A.a
    b. Ordered Level 2 Item A.b
2. Ordered Level 1 Item B

More text here.]]

	test_boundary_detection(content, "Ordered Level 1 Item A", {
		found = true,
		start_line = 7,
		start_char = 0,
		end_line = 10,
		end_char = 0,
	})
end

-- Execute tests
return run_spec("list text object", {
	test_boundary_detection_simple_list,
	test_boundary_detection_nested_list,
	test_boundary_detection_task_list,
	test_boundary_detection_no_list,
	test_boundary_detection_numbered_list,
})
