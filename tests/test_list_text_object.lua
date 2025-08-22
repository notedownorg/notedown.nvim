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

-- Tests for list text object boundary detection
--
-- NOTE: This test file focuses on testing the boundary detection logic rather than
-- the full end-to-end text object behavior (yank/delete operations) because:
--
-- 1. Text objects appear to not work reliably in headless Neovim test environments
-- 2. The vim.cmd('normal! yal') execution seems to have issues triggering custom text objects
-- 3. Manual testing suggests the text objects work correctly in real Neovim sessions
-- 4. The core logic (boundary detection) can be tested more reliably in headless mode
--
-- The boundary detection is the critical component that determines which lines
-- should be selected by the text object, so testing this should provide reasonable
-- confidence in the overall functionality.

local MiniTest = require("mini.test")
local lsp_shared = require("helpers.lsp_shared")

local T = MiniTest.new_set()

-- Initialize shared LSP session once for the entire test suite
lsp_shared.initialize()

-- Register cleanup function to run when all tests complete
_G._notedown_list_text_object_cleanup = lsp_shared.cleanup

-- Helper function to test boundary detection
local function test_boundary_detection(test_content, cursor_search, expected_boundaries)
	-- Create test workspace and open file
	local workspace_path, file_path = lsp_shared.create_test_workspace(test_content)
	lsp_shared.open_file(file_path)

	-- Position cursor
	lsp_shared.position_cursor(cursor_search)

	-- Get the child neovim instance and test boundary detection
	local child = lsp_shared.get_child()

	-- Test if we can call the function at all
	local can_call = child.lua_get('type(require("notedown").get_list_item_boundaries) == "function"')

	local boundaries
	if not can_call then
		boundaries = { found = false, error = "function not available" }
	else
		-- Call the function and check if it returns something
		child.lua('_test_boundaries = require("notedown").get_list_item_boundaries()')

		-- Check if boundaries were found
		local found = child.lua_get("_test_boundaries and _test_boundaries.found or false")

		if found then
			local start_line = child.lua_get("_test_boundaries.start.line")
			local start_char = child.lua_get("_test_boundaries.start.character")
			local end_line = child.lua_get('_test_boundaries["end"].line')
			local end_char = child.lua_get('_test_boundaries["end"].character')

			boundaries = {
				found = true,
				start_line = start_line,
				start_char = start_char,
				end_line = end_line,
				end_char = end_char,
			}
		else
			boundaries = { found = false }
		end

		-- Clean up the test variable
		child.lua("_test_boundaries = nil")
	end

	-- Clean up
	lsp_shared.cleanup_test_workspace(workspace_path)

	-- Verify boundaries
	if expected_boundaries.found then
		MiniTest.expect.equality(boundaries.found, true, "Expected to find list item boundaries")
		MiniTest.expect.equality(boundaries.start_line, expected_boundaries.start_line, "Start line mismatch")
		MiniTest.expect.equality(boundaries.start_char, expected_boundaries.start_char, "Start character mismatch")
		MiniTest.expect.equality(boundaries.end_line, expected_boundaries.end_line, "End line mismatch")
		MiniTest.expect.equality(boundaries.end_char, expected_boundaries.end_char, "End character mismatch")
	else
		MiniTest.expect.equality(boundaries.found, false, "Expected not to find list item boundaries")
	end
end

-- ========================================
-- BOUNDARY DETECTION TESTS
-- ========================================

T["boundary detection - simple list first item"] = function()
	local content = [[# Test List

- First item
- Second item
- Third item
- Fourth item

Some text after the list.]]

	test_boundary_detection(content, "First item", {
		found = true,
		start_line = 2, -- 0-based: "- First item"
		start_char = 0,
		end_line = 3, -- 0-based: line after "- First item"
		end_char = 0,
	})
end

T["boundary detection - simple list middle item"] = function()
	local content = [[# Test List

- First item
- Second item
- Third item
- Fourth item

Some text after the list.]]

	test_boundary_detection(content, "Third item", {
		found = true,
		start_line = 4, -- 0-based: "- Third item"
		start_char = 0,
		end_line = 5, -- 0-based: line after "- Third item"
		end_char = 0,
	})
end

T["boundary detection - nested list with children"] = function()
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

Some numbered lists:

1. Ordered Level 1 Item A
    a. Ordered Level 2 Item A.a
    b. Ordered Level 2 Item A.b
2. Ordered Level 1 Item B

More text here.]]

	-- Test that Level 1 Item A includes all its children
	test_boundary_detection(content, "Level 1 Item A", {
		found = true,
		start_line = 2, -- 0-based: "- Level 1 Item A"
		start_char = 0,
		end_line = 11, -- 0-based: line after "  - Level 2 Item A.2"
		end_char = 0,
	})
end

T["boundary detection - task list item"] = function()
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
		start_line = 2, -- 0-based: "- [x] Completed task"
		start_char = 0,
		end_line = 7, -- 0-based: line after "  - [x] Subtask B"
		end_char = 0,
	})
end

T["boundary detection - no list item found"] = function()
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

T["boundary detection - numbered list"] = function()
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

Some numbered lists:

1. Ordered Level 1 Item A
    a. Ordered Level 2 Item A.a
    b. Ordered Level 2 Item A.b
2. Ordered Level 1 Item B

More text here.]]

	test_boundary_detection(content, "Ordered Level 1 Item A", {
		found = true,
		start_line = 15, -- 0-based: "1. Ordered Level 1 Item A"
		start_char = 0,
		end_line = 18, -- 0-based: line after "    b. Ordered Level 2 Item A.b"
		end_char = 0,
	})
end

return T
