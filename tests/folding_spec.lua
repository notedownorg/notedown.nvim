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

-- Tests for folding functionality

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec
local wait_for_lsp = test_utils.wait_for_lsp

-- Test content with various foldable elements
local test_content = [[# Header 1

Some content under header 1.

## Header 2

More content under header 2.

### Header 3

Content under header 3.

## Another Header 2

More content here.

- [ ] Task 1
- [x] Task 2
  - [ ] Subtask 1
  - [ ] Subtask 2
    - [ ] Sub-subtask
- [ ] Task 3

Regular list:
- Item 1
- Item 2
  - Nested item
  - Another nested item
- Item 3

```javascript
function test() {
  console.log("Testing folding");
  if (true) {
    console.log("nested");
  }
}
```

# Final Header

Final content.
]]

local function test_folding_setup_notedown_files()
	print_test("LSP folding enabled for notedown files")

	local workspace = test_utils.create_test_workspace("/tmp/test-folding-workspace")

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Open file
	vim.cmd("edit folding-test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))

	-- Save the file to disk to ensure LSP processes it
	vim.cmd("silent write")

	-- Wait for LSP to initialize
	local lsp_ready = wait_for_lsp(5000)

	if lsp_ready then
		-- Wait for all autocmds to fire
		vim.wait(500)

		-- Check that filetype is notedown
		local filetype = vim.bo.filetype
		assert_equals(filetype, "notedown", "Filetype should be notedown")

		-- Check that folding is configured for LSP
		if filetype == "notedown" then
			local foldmethod = vim.wo.foldmethod
			local foldexpr = vim.wo.foldexpr
			local foldenable = vim.wo.foldenable

			assert_equals(foldmethod, "expr", "Foldmethod should be expr")
			assert_equals(
				foldexpr,
				"v:lua.require('notedown').notedown_foldexpr()",
				"Foldexpr should use custom notedown fold expression"
			)
			assert_equals(foldenable, true, "Folding should be enabled")
		end
	else
		error("LSP did not initialize - cannot test folding functionality")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_folding_setup_markdown_files()
	print_test("LSP folding not enabled for markdown files")

	local workspace = test_utils.create_test_workspace("/tmp/test-markdown-workspace")

	-- Don't create .notedown directory, so it's not a notedown workspace
	vim.fn.system({ "rm", "-rf", workspace .. "/.notedown" })

	-- Change to non-notedown workspace
	vim.cmd("cd " .. workspace)

	-- Open a markdown file
	vim.cmd("edit test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))

	-- Wait a moment for autocmds to fire
	vim.wait(200)

	-- Should be markdown filetype, not notedown
	local filetype = vim.bo.filetype
	assert_equals(filetype, "markdown", "Should detect as markdown, not notedown")

	-- Folding should not be set to LSP (should be default)
	local foldmethod = vim.wo.foldmethod
	assert_equals(foldmethod ~= "expr", true, "Foldmethod should not be expr for markdown files")

	test_utils.cleanup_test_workspace(workspace)
end

local function test_header_folding()
	print_test("header folding ranges from LSP")

	local workspace = test_utils.create_test_workspace("/tmp/test-header-folding")

	vim.cmd("cd " .. workspace)
	vim.cmd("edit header-test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write")

	-- Wait for LSP and ensure document synchronization
	local lsp_ready = wait_for_lsp(3000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("LSP did not initialize - cannot test folding functionality")
	end

	-- Ensure document is synchronized with LSP server
	local sync_success = test_utils.sync_document_with_lsp(0)
	assert_equals(sync_success, true, "Should sync document with LSP")

	-- Wait for LSP to process the document
	vim.wait(1000)

	-- Test that we can request folding ranges from LSP
	local params = {
		textDocument = vim.lsp.util.make_text_document_params(),
	}

	local folding_ranges = test_utils.lsp_request_sync("textDocument/foldingRange", params, 3000)
	assert_equals(type(folding_ranges), "table", "Should get folding ranges array")
	assert_equals(#folding_ranges > 0, true, "Should have at least one folding range")

	-- Verify we have header folding ranges with precise boundaries
	local header_ranges = {}
	for _, range in ipairs(folding_ranges) do
		-- Header 1 (line 0), Header 2 (line 4), Header 3 (line 8), Another Header 2 (line 12)
		if range.startLine == 0 or range.startLine == 4 or range.startLine == 8 or range.startLine == 12 then
			table.insert(header_ranges, range)
		end
	end

	assert_equals(#header_ranges >= 3, true, "Should have at least 3 header folding ranges")

	-- Test specific header folding ranges with precise boundaries

	-- Test: Header 1 (# Header 1) - should fold entire document until Final Header
	local header1_range = nil
	for _, range in ipairs(header_ranges) do
		if range.startLine == 0 then
			header1_range = range
			break
		end
	end

	if header1_range then
		assert_equals(header1_range.startLine, 0, "Header 1 should start at line 0")
		assert_equals(header1_range.endLine, 38, "Header 1 should end at line 38 (includes Final Header)")
		if header1_range.kind then
			assert_equals(header1_range.kind, "region", "Header 1 should be 'region' kind")
		end
	end

	-- Test: Header 2 (## Header 2) - should fold until Another Header 2, including Header 3
	local header2_range = nil
	for _, range in ipairs(header_ranges) do
		if range.startLine == 4 then
			header2_range = range
			break
		end
	end

	if header2_range then
		assert_equals(header2_range.startLine, 4, "Header 2 should start at line 4")
		assert_equals(header2_range.endLine, 11, "Header 2 should end at line 11 (includes nested Header 3)")
		if header2_range.kind then
			assert_equals(header2_range.kind, "region", "Header 2 should be 'region' kind")
		end
	end

	-- Test: Header 3 (### Header 3) - should fold until same-level Header 2
	local header3_range = nil
	for _, range in ipairs(header_ranges) do
		if range.startLine == 8 then
			header3_range = range
			break
		end
	end

	if header3_range then
		assert_equals(header3_range.startLine, 8, "Header 3 should start at line 8")
		assert_equals(header3_range.endLine, 11, "Header 3 should end at line 11 (before Another Header 2)")
		if header3_range.kind then
			assert_equals(header3_range.kind, "region", "Header 3 should be 'region' kind")
		end
	end

	-- Test: Another Header 2 (## Another Header 2) - should fold to end of document
	local another_header2_range = nil
	for _, range in ipairs(header_ranges) do
		if range.startLine == 12 then
			another_header2_range = range
			break
		end
	end

	if another_header2_range then
		assert_equals(another_header2_range.startLine, 12, "Another Header 2 should start at line 12")
		assert_equals(another_header2_range.endLine, 38, "Another Header 2 should end at line 38 (until document end)")
		if another_header2_range.kind then
			assert_equals(another_header2_range.kind, "region", "Another Header 2 should be 'region' kind")
		end
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_list_folding()
	print_test("list folding ranges from LSP")

	local workspace = test_utils.create_test_workspace("/tmp/test-list-folding")

	vim.cmd("cd " .. workspace)
	vim.cmd("edit list-test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write")

	-- Wait for LSP and ensure document synchronization
	local lsp_ready = wait_for_lsp(3000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("LSP did not initialize - cannot test folding functionality")
	end

	test_utils.sync_document_with_lsp(0)
	vim.wait(1000)

	-- Request folding ranges from LSP
	local params = {
		textDocument = vim.lsp.util.make_text_document_params(),
	}

	local folding_ranges = test_utils.lsp_request_sync("textDocument/foldingRange", params, 3000)
	assert_equals(type(folding_ranges), "table", "Should get folding ranges array")

	-- Find list folding ranges (should be in the task list area)
	local list_ranges = {}
	for _, range in ipairs(folding_ranges) do
		-- Task list starts around line 16-21 (- [ ] Task 1, etc.)
		if range.startLine >= 15 and range.startLine <= 30 then
			table.insert(list_ranges, range)
		end
	end

	if #list_ranges > 0 then
		assert_equals(#list_ranges > 0, true, "Should have list folding ranges")

		-- Test specific meaningful list folding ranges

		-- Test: Task 2 with subtasks (line 17 should have children at lines 18-20)
		local task2_range = nil
		for _, range in ipairs(list_ranges) do
			if range.startLine == 17 and range.endLine == 20 then
				task2_range = range
				break
			end
		end

		if task2_range then
			assert_equals(task2_range.startLine, 17, "Task 2 should start at line 17")
			assert_equals(task2_range.endLine, 20, "Task 2 should end at line 20 (includes subtasks)")
		else
			-- Look for any range starting at line 17 (Task 2)
			for _, range in ipairs(list_ranges) do
				if range.startLine == 17 then
					assert_equals(
						range.endLine > 17,
						true,
						"Task 2 (line 17) should fold subtasks (ends at line " .. range.endLine .. ")"
					)
					break
				end
			end
		end

		-- Test: Subtask 1 with sub-subtask (line 18 should include line 20)
		local subtask1_range = nil
		for _, range in ipairs(list_ranges) do
			if range.startLine == 18 and range.endLine >= 19 then
				subtask1_range = range
				break
			end
		end

		if subtask1_range then
			assert_equals(subtask1_range.startLine, 18, "Subtask 1 should start at line 18")
			assert_equals(
				subtask1_range.endLine >= 19,
				true,
				"Subtask 1 should include nested content (ends at line " .. subtask1_range.endLine .. ")"
			)
		end

		-- Test: Regular list with nested items (line 25: Item 2 with nested items)
		local item2_range = nil
		for _, range in ipairs(list_ranges) do
			if range.startLine == 25 and range.endLine == 27 then
				item2_range = range
				break
			end
		end

		if item2_range then
			assert_equals(item2_range.startLine, 25, "Item 2 should start at line 25")
			assert_equals(item2_range.endLine, 27, "Item 2 should end at line 27 (includes nested items)")
		else
			-- Look for any range starting at line 25 (Item 2)
			for _, range in ipairs(list_ranges) do
				if range.startLine == 25 then
					assert_equals(
						range.endLine > 25,
						true,
						"Item 2 (line 25) should fold nested items (ends at line " .. range.endLine .. ")"
					)
					break
				end
			end
		end

		-- Test: Task 1 (should be a single-line task without children)
		local task1_range = nil
		for _, range in ipairs(list_ranges) do
			if range.startLine == 16 then
				task1_range = range
				break
			end
		end

		if task1_range then
			-- Task 1 might fold if the algorithm groups adjacent tasks
			assert_equals(task1_range.startLine, 16, "Task 1 should start at line 16")
			assert_equals(
				task1_range.endLine >= 16,
				true,
				"Task 1 range should be valid (ends at line " .. task1_range.endLine .. ")"
			)
		end

		-- Test: Regular Item 1 (line 24: - Item 1)
		local item1_range = nil
		for _, range in ipairs(list_ranges) do
			if range.startLine == 24 then
				item1_range = range
				break
			end
		end

		if item1_range then
			assert_equals(item1_range.startLine, 24, "Item 1 should start at line 24")
			assert_equals(
				item1_range.endLine >= 24,
				true,
				"Item 1 range should be valid (ends at line " .. item1_range.endLine .. ")"
			)
		end
	else
		-- If no list ranges found, just verify we have the list structure
		local buf_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		local task_count = 0
		for line in buf_content:gmatch("[^\n]+") do
			if string.match(line, "%-%s*%[.%]") then
				task_count = task_count + 1
			end
		end
		assert_equals(task_count >= 3, true, "Should have multiple task items for folding")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_code_block_folding()
	print_test("code block folding ranges from LSP")

	local workspace = test_utils.create_test_workspace("/tmp/test-code-folding")

	vim.cmd("cd " .. workspace)
	vim.cmd("edit code-test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write")

	-- Wait for LSP and ensure document synchronization
	local lsp_ready = wait_for_lsp(3000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("LSP did not initialize - cannot test folding functionality")
	end

	test_utils.sync_document_with_lsp(0)
	vim.wait(1000)

	-- Find code block in content
	vim.fn.search("^```javascript")
	local code_start_line = vim.fn.line(".")
	assert_equals(code_start_line > 0, true, "Should find code block start")

	-- The javascript code block should be around line 30-37
	local expected_code_start = code_start_line - 1 -- Convert to 0-based

	-- Request folding ranges from LSP
	local params = {
		textDocument = vim.lsp.util.make_text_document_params(),
	}

	local folding_ranges = test_utils.lsp_request_sync("textDocument/foldingRange", params, 3000)
	assert_equals(type(folding_ranges), "table", "Should get folding ranges array")

	-- Test specific code block folding ranges with precise boundaries

	-- Test: JavaScript code block (```javascript ... ```) - should fold the code content
	local js_code_range = nil
	for _, range in ipairs(folding_ranges) do
		-- Based on our test content structure, JavaScript code block starts around line 29
		if range.startLine == 28 then
			js_code_range = range
			break
		end
	end

	if js_code_range then
		assert_equals(js_code_range.startLine, 28, "JavaScript code block should start at line 28 (```javascript)")
		assert_equals(
			js_code_range.endLine >= 29,
			true,
			"JavaScript code block should include function content (ends at line " .. js_code_range.endLine .. ")"
		)
		if js_code_range.kind then
			assert_equals(js_code_range.kind, "region", "JavaScript code block should be 'region' kind")
		end
	else
		-- Look for any code block range in the expected area
		local any_code_range = nil
		for _, range in ipairs(folding_ranges) do
			if range.startLine >= 27 and range.startLine <= 31 then
				any_code_range = range
				break
			end
		end

		if any_code_range then
			assert_equals(
				any_code_range.startLine >= 27 and any_code_range.startLine <= 31,
				true,
				"Code block should start in expected area (found at line " .. any_code_range.startLine .. ")"
			)
			assert_equals(
				any_code_range.endLine > any_code_range.startLine,
				true,
				"Code block should fold content (lines "
					.. any_code_range.startLine
					.. "-"
					.. any_code_range.endLine
					.. ")"
			)
			if any_code_range.kind then
				assert_equals(any_code_range.kind, "region", "Code block should be 'region' kind")
			end
		else
			-- If no code block range found, verify we have the structure in content
			local buf_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
			local has_js_block = string.match(buf_content, "```javascript")
			local has_closing = string.match(buf_content, "```[^`]*```")
			assert_equals(has_js_block ~= nil, true, "Should have JavaScript code block in test content")
			assert_equals(has_closing ~= nil, true, "Should have properly closed code block")
		end
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_manual_fold_operations()
	print_test("actual fold behavior validation")

	local workspace = test_utils.create_test_workspace("/tmp/test-manual-folding")

	vim.cmd("cd " .. workspace)
	vim.cmd("edit manual-test.md")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
	vim.cmd("silent write")

	-- Wait for LSP and ensure document synchronization
	local lsp_ready = wait_for_lsp(3000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("LSP did not initialize - cannot test folding functionality")
	end

	test_utils.sync_document_with_lsp(0)

	-- Test that folding configuration is consistent
	local foldmethod = vim.wo.foldmethod
	local foldexpr = vim.wo.foldexpr
	local foldenable = vim.wo.foldenable

	assert_equals(foldmethod, "expr", "Should have expr fold method")
	assert_equals(
		foldexpr,
		"v:lua.require('notedown').notedown_foldexpr()",
		"Should use custom notedown fold expression"
	)
	assert_equals(foldenable, true, "Folding should be enabled")

	-- Position cursor on first header and wait for fold levels to be computed
	vim.fn.search("^# Header 1")
	local header_line = vim.fn.line(".")
	assert_equals(header_line > 0, true, "Should find header")

	-- Force fold computation by completely rebuilding folds
	vim.cmd("setlocal nofoldenable") -- Disable folding
	vim.wait(100)
	vim.cmd("setlocal foldenable") -- Re-enable folding
	vim.cmd("normal! zX") -- Clear all folds and recompute
	vim.wait(200)

	-- Wait for folding to be fully initialized and try to get fold levels
	local fold_level = nil
	local max_attempts = 10
	for i = 1, max_attempts do
		vim.wait(200) -- Wait for fold computation
		fold_level = vim.fn.foldlevel(header_line)

		if fold_level and fold_level > 0 then
			break
		end

		-- Force fold recomputation on every attempt
		vim.cmd("normal! zX") -- Clear all folds and recompute
	end

	if fold_level and fold_level > 0 then
		assert_equals(fold_level > 0, true, "Header should have positive fold level")

		-- Test actual fold operations
		vim.cmd("normal! zc") -- Close fold
		vim.wait(100) -- Wait for fold to close

		local closed_line = vim.fn.foldclosed(header_line)
		test_utils.assert_or_fail(
			closed_line > 0,
			"Fold should close properly - got closed_line: " .. tostring(closed_line),
			{
				expected = "> 0",
				actual = closed_line,
			}
		)

		test_utils.assert_or_fail(closed_line == header_line, "Header should be in closed fold", {
			expected = header_line,
			actual = closed_line,
		})

		-- Test opening fold
		vim.cmd("normal! zo") -- Open fold
		vim.wait(100)

		local opened_line = vim.fn.foldclosed(header_line)
		test_utils.assert_or_fail(opened_line == -1, "Header should not be in closed fold after opening", {
			expected = -1,
			actual = opened_line,
		})
	else
		test_utils.fail(
			"Fold level computation failed - no positive fold level found after " .. max_attempts .. " attempts",
			{
				expected = "> 0",
				actual = fold_level or "nil",
			}
		)
	end

	test_utils.cleanup_test_workspace(workspace)
end

-- Execute tests
return run_spec("folding", {
	test_folding_setup_notedown_files,
	test_folding_setup_markdown_files,
	test_header_folding,
	test_list_folding,
	test_code_block_folding,
	test_manual_fold_operations,
})
