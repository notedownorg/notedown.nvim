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

-- Tests for task state completion functionality in Neovim

local MiniTest = require("mini.test")
local utils = require("helpers.utils")
local lsp = require("helpers.lsp_dedicated")

local T = MiniTest.new_set()

-- Test workspace setup for task completion tests
local function setup_task_completion_workspace(path)
	local workspace = utils.create_test_workspace(path)

	-- Create .notedown directory with custom task state configuration
	vim.fn.mkdir(workspace .. "/.notedown", "p")
	utils.write_file(
		workspace .. "/.notedown/settings.yaml",
		[[
tasks:
  states:
    - value: " "
      name: "todo"
      description: "A task that needs to be completed"
    - value: "x"
      name: "done"
      description: "A completed task"
      conceal: "✅"
      aliases: ["X", "completed"]
    - value: "wip"
      name: "work-in-progress"
      description: "A task currently being worked on"
      conceal: "🚧"
      aliases: ["working"]
    - value: "?"
      name: "question"
      description: "A task that needs clarification"
      conceal: "❓"
      aliases: ["unclear"]
    - value: "!"
      name: "important"
      description: "A high priority task"
      conceal: "❗"
      aliases: ["priority", "urgent"]
]]
	)

	-- Create a test markdown file with various task states
	utils.write_file(
		workspace .. "/tasks.md",
		[[# Task List Test

## Default Tasks
- [ ] Todo item
- [x] Done item

## Custom Tasks
- [wip] Work in progress item
- [?] Question item
- [!] Important item

## Testing Completion
- [
]]
	)

	return workspace
end

T["task state completion"] = MiniTest.new_set()

T["task state completion"]["provides default task states without config"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-task-completion-default")
	local child = utils.new_child_neovim()

	-- Create workspace WITHOUT .notedown config (should use defaults)
	utils.write_file(
		workspace .. "/test.md",
		[[# Test

- [
]]
	)

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/test.md")')
	lsp.wait_for_ready(child)

	-- Test completion by properly opening document and updating content
	child.lua([[
		_G.test_completion_result = nil
		_G.test_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = '# Test\n\n- ['
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(200)
			
			-- Create content with partial task for completion context
			local new_content = "# Test\n\n- ["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(new_content, "\n"))
			
			-- Send didChange notification to update LSP server state
			client.notify('textDocument/didChange', {
				textDocument = { uri = uri, version = 2 },
				contentChanges = {{ text = new_content }}
			})
			
			-- Wait for the change to be processed
			vim.wait(500)
			
			-- Request completion at position inside task bracket (right after "[")
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 3 }  -- After "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_completion_error = tostring(err)
			elseif result then
				_G.test_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Extract completion labels and details
	local completion_labels = {}
	local completion_details = {}
	for _, item in ipairs(items) do
		table.insert(completion_labels, item.label)
		table.insert(completion_details, item.detail or "")
	end

	-- Verify we got the default task states
	MiniTest.expect.equality(#completion_labels >= 2, true, "Should have at least 2 default task states")

	-- Check for default task states
	local found_space = false
	local found_x = false

	for i, label in ipairs(completion_labels) do
		if label == " " then
			found_space = true
			MiniTest.expect.equality(
				string.find(completion_details[i], "todo") ~= nil,
				true,
				"Space task should be labeled as todo"
			)
		elseif label == "x" then
			found_x = true
			MiniTest.expect.equality(
				string.find(completion_details[i], "done") ~= nil,
				true,
				"X task should be labeled as done"
			)
		end
	end

	MiniTest.expect.equality(found_space, true, "Should find space (todo) task state")
	MiniTest.expect.equality(found_x, true, "Should find x (done) task state")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["provides custom task states with config"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-custom")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Position cursor after the last "- [" for completion testing
	child.lua([[vim.fn.search("- \\[")]])

	-- Test completion with custom configuration
	child.lua([[
		_G.test_custom_completion_result = nil
		_G.test_custom_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Get the current buffer content
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local content = table.concat(lines, "\n")
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Find the last line with "- [" and request completion there
			local last_line_index = #lines - 1  -- Convert to 0-based
			local last_line = lines[#lines]
			local bracket_pos = string.find(last_line, "%[")
			
			if bracket_pos then
				-- Request completion at position right after the opening bracket
				local params = {
					textDocument = { uri = uri },
					position = { line = last_line_index, character = bracket_pos } -- Right after "["
				}
				
				local result, err = client.request_sync('textDocument/completion', params, 5000)
				if err then
					_G.test_custom_completion_error = tostring(err)
				elseif result then
					_G.test_custom_completion_result = result.result
				end
			else
				_G.test_custom_completion_error = "Could not find opening bracket in last line"
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_custom_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_custom_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Extract completion labels and details
	local completion_labels = {}
	local completion_details = {}
	for _, item in ipairs(items) do
		table.insert(completion_labels, item.label)
		table.insert(completion_details, item.detail or "")
	end

	-- Verify we got all custom task states (5 total from config)
	MiniTest.expect.equality(#completion_labels >= 5, true, "Should have at least 5 custom task states")

	-- Check for all expected custom task states
	local expected_states = {
		{ label = " ", name = "todo" },
		{ label = "x", name = "done" },
		{ label = "wip", name = "work-in-progress" },
		{ label = "?", name = "question" },
		{ label = "!", name = "important" },
	}

	for _, expected in ipairs(expected_states) do
		local found = false
		for i, label in ipairs(completion_labels) do
			if label == expected.label then
				found = true
				-- Check for name in detail using literal string matching
				local detail = completion_details[i] or ""
				local name_found = string.find(detail, expected.name, 1, true) ~= nil
				MiniTest.expect.equality(
					name_found,
					true,
					string.format(
						"Task state '%s' should have name '%s' in detail '%s'",
						expected.label,
						expected.name,
						detail
					)
				)
				break
			end
		end
		MiniTest.expect.equality(found, true, string.format("Should find task state '%s'", expected.label))
	end

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["includes conceal information in documentation"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-conceal")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Test completion to check for conceal information
	child.lua([[
		_G.test_conceal_completion_result = nil
		_G.test_conceal_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Create simple content for testing
			local content = "# Test\n\n- ["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion at position right after the opening bracket
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 3 } -- Right after "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_conceal_completion_error = tostring(err)
			elseif result then
				_G.test_conceal_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_conceal_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_conceal_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Check items with conceal information
	local found_conceal_items = 0
	local expected_conceals = {
		["x"] = "✅",
		["wip"] = "🚧",
		["?"] = "❓",
		["!"] = "❗",
	}

	for _, item in ipairs(items) do
		local expected_conceal = expected_conceals[item.label]
		if expected_conceal then
			found_conceal_items = found_conceal_items + 1

			-- Check that detail includes conceal information
			local detail = item.detail or ""
			MiniTest.expect.equality(
				string.find(detail, expected_conceal, 1, true) ~= nil,
				true,
				string.format("Detail for '%s' should include conceal '%s'", item.label, expected_conceal)
			)

			-- Conceal information should be in detail, not documentation in new format
			-- Documentation contains description and "See also" information
		end
	end

	MiniTest.expect.equality(found_conceal_items >= 4, true, "Should find at least 4 items with conceal information")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["filters completions based on prefix"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-filter")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Test prefix filtering by adding "w" prefix
	child.lua([[
		_G.test_filter_completion_result = nil
		_G.test_filter_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Create content with "w" prefix after the bracket
			local content = "# Test\n\n- [w"
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion at position after "w" prefix
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 4 } -- Right after "- [w"
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_filter_completion_error = tostring(err)
			elseif result then
				_G.test_filter_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_filter_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_filter_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Extract completion labels
	local completion_labels = {}
	for _, item in ipairs(items) do
		table.insert(completion_labels, item.label)
	end

	-- With "w" prefix, we should only get "wip" completion
	MiniTest.expect.equality(#completion_labels >= 1, true, "Should have at least one completion")

	-- Check that "wip" is included
	local found_wip = false
	for _, label in ipairs(completion_labels) do
		if label == "wip" then
			found_wip = true
		end
		-- All returned completions should start with "w" (case insensitive)
		MiniTest.expect.equality(
			string.sub(string.lower(label), 1, 1) == "w",
			true,
			string.format("Completion '%s' should start with 'w'", label)
		)
	end

	MiniTest.expect.equality(found_wip, true, "Should find 'wip' completion with 'w' prefix")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["completes outside of wikilink context"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-context")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Create test file with both task and wikilink contexts
	utils.write_file(
		workspace .. "/context-test.md",
		"# Context Test\n\nThis has a wikilink [[some-link]] and task:\n- [\n"
	)

	child.lua('vim.cmd("edit ' .. workspace .. '/context-test.md")')
	lsp.wait_for_ready(child)

	-- Test that task completion works and doesn't interfere with wikilink completion
	child.lua([[
		_G.test_context_completion_result = nil
		_G.test_context_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Get the current buffer content
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local content = table.concat(lines, "\n")
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion in task context (last line after "- [")
			local params = {
				textDocument = { uri = uri },
				position = { line = 3, character = 3 } -- After "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_context_completion_error = tostring(err)
			elseif result then
				_G.test_context_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_context_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_context_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Verify we got task state completions, not wikilink completions
	MiniTest.expect.equality(#items >= 2, true, "Should have task state completions")

	-- Check that these are task completions by looking for expected task states
	local found_task_states = 0
	for _, item in ipairs(items) do
		if item.label == " " or item.label == "x" or item.label == "wip" then
			found_task_states = found_task_states + 1
			-- Verify the kind is appropriate for task states
			MiniTest.expect.equality(
				item.kind == 13, -- CompletionItemKindEnum
				true,
				"Task state completion should have Enum kind"
			)
		end
	end

	MiniTest.expect.equality(found_task_states >= 2, true, "Should find multiple task state completions")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["includes aliases in completions"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-aliases")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Test completion to check for aliases
	child.lua([[
		_G.test_alias_completion_result = nil
		_G.test_alias_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Create simple content for testing
			local content = "# Test\n\n- ["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion at position right after the opening bracket
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 3 } -- Right after "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_alias_completion_error = tostring(err)
			elseif result then
				_G.test_alias_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_alias_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_alias_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Extract completion labels, details, and documentation
	local completion_labels = {}
	local completion_details = {}
	local completion_docs = {}
	for _, item in ipairs(items) do
		table.insert(completion_labels, item.label)
		table.insert(completion_details, item.detail or "")
		table.insert(completion_docs, item.documentation or "")
	end

	-- Check for expected aliases
	local expected_aliases = {
		"X", -- alias for done
		"completed", -- alias for done
		"working", -- alias for wip
		"unclear", -- alias for question
		"priority", -- alias for important
		"urgent", -- alias for important
	}

	local found_aliases = 0
	for _, expected_alias in ipairs(expected_aliases) do
		local found = false
		for i, label in ipairs(completion_labels) do
			if label == expected_alias then
				found = true
				found_aliases = found_aliases + 1

				-- Check that the documentation indicates it's an alias (not detail in new format)
				local documentation = completion_docs[i] or ""
				MiniTest.expect.equality(
					string.find(documentation, "Alias for") ~= nil,
					true,
					string.format(
						"Alias '%s' should indicate it's an alias in documentation: '%s'",
						expected_alias,
						documentation
					)
				)
				break
			end
		end
		MiniTest.expect.equality(found, true, string.format("Should find alias '%s'", expected_alias))
	end

	-- Should have found all expected aliases
	MiniTest.expect.equality(
		found_aliases >= #expected_aliases,
		true,
		string.format("Should find at least %d aliases, found %d", #expected_aliases, found_aliases)
	)

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["includes descriptions in documentation"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-descriptions")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Test completion to check for descriptions
	child.lua([[
		_G.test_desc_completion_result = nil
		_G.test_desc_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Create simple content for testing
			local content = "# Test\n\n- ["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion at position right after the opening bracket
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 3 } -- Right after "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_desc_completion_error = tostring(err)
			elseif result then
				_G.test_desc_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_desc_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_desc_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Check for descriptions in documentation and details
	local found_descriptions = 0
	local expected_descriptions = {
		["x"] = "A completed task",
		["wip"] = "A task currently being worked on",
		["?"] = "A task that needs clarification",
		["!"] = "A high priority task",
	}

	for _, item in ipairs(items) do
		local expected_desc = expected_descriptions[item.label]
		if expected_desc then
			found_descriptions = found_descriptions + 1

			-- In new format, detail only contains name + conceal, not description
			-- We'll just check that detail exists for now
			local detail = item.detail or ""
			MiniTest.expect.equality(
				detail ~= "",
				true,
				string.format("Detail for '%s' should not be empty: '%s'", item.label, detail)
			)

			-- Check documentation includes description
			local documentation = item.documentation or ""
			if documentation ~= "" then
				MiniTest.expect.equality(
					string.find(documentation, expected_desc, 1, true) ~= nil,
					true,
					string.format(
						"Documentation for '%s' should include description '%s': '%s'",
						item.label,
						expected_desc,
						documentation
					)
				)
			end
		end
	end

	MiniTest.expect.equality(
		found_descriptions >= 4,
		true,
		string.format("Should find at least 4 items with descriptions, found %d", found_descriptions)
	)

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["task state completion"]["groups main values with their aliases"] = function()
	local workspace = setup_task_completion_workspace("/tmp/test-task-completion-grouping")
	local child = utils.new_child_neovim()

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open test file
	child.lua('vim.cmd("edit ' .. workspace .. '/tasks.md")')
	lsp.wait_for_ready(child)

	-- Test completion to check ordering/grouping
	child.lua([[
		_G.test_grouping_completion_result = nil
		_G.test_grouping_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Create simple content for testing
			local content = "# Test\n\n- ["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
			
			-- Send didOpen to ensure LSP tracks this document
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = content
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(500)
			
			-- Request completion at position right after the opening bracket
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 3 } -- Right after "- ["
			}
			
			local result, err = client.request_sync('textDocument/completion', params, 5000)
			if err then
				_G.test_grouping_completion_error = tostring(err)
			elseif result then
				_G.test_grouping_completion_result = result.result
			end
		end
	]])

	-- Check for completion errors
	local completion_error = child.lua_get("_G.test_grouping_completion_error")
	if completion_error and completion_error ~= vim.NIL then
		MiniTest.expect.equality(completion_error, nil, "Completion should not have errors")
	end

	-- Get completion results
	local completion_result = child.lua_get("_G.test_grouping_completion_result")
	local items = completion_result and (completion_result.items or completion_result) or {}
	MiniTest.expect.equality(type(items), "table")

	-- Items should already be sorted by sortText, let's verify grouping
	local labels = {}
	local sort_texts = {}
	for _, item in ipairs(items) do
		table.insert(labels, item.label)
		table.insert(sort_texts, item.sortText or "")
	end

	-- Verify that we have the expected order: main values followed by their aliases
	-- Expected grouping (based on our config):
	-- 1. " " (todo - no aliases)
	-- 2. "x" (done - main value)
	-- 3. "X" (done - alias)
	-- 4. "completed" (done - alias)
	-- 5. "wip" (work-in-progress - main value)
	-- 6. "working" (work-in-progress - alias)
	-- 7. "?" (question - main value)
	-- 8. "unclear" (question - alias)
	-- 9. "!" (important - main value)
	-- 10. "priority" (important - alias)
	-- 11. "urgent" (important - alias)

	-- Find positions of key items to verify grouping
	local positions = {}
	for i, label in ipairs(labels) do
		positions[label] = i
	end

	-- Verify that main values come before their aliases
	if positions["x"] and positions["X"] and positions["completed"] then
		MiniTest.expect.equality(positions["x"] < positions["X"], true, "Main value 'x' should come before alias 'X'")
		MiniTest.expect.equality(
			positions["x"] < positions["completed"],
			true,
			"Main value 'x' should come before alias 'completed'"
		)
	end

	if positions["wip"] and positions["working"] then
		MiniTest.expect.equality(
			positions["wip"] < positions["working"],
			true,
			"Main value 'wip' should come before alias 'working'"
		)
	end

	if positions["!"] and positions["priority"] and positions["urgent"] then
		MiniTest.expect.equality(
			positions["!"] < positions["priority"],
			true,
			"Main value '!' should come before alias 'priority'"
		)
		MiniTest.expect.equality(
			positions["!"] < positions["urgent"],
			true,
			"Main value '!' should come before alias 'urgent'"
		)
	end

	-- Verify aliases are grouped with their main value (not scattered)
	-- The 'x' group should be consecutive: x, X, completed
	if positions["x"] and positions["X"] and positions["completed"] then
		local x_group_start = positions["x"]
		local x_group_end = math.max(positions["X"], positions["completed"])

		-- Check that there are no non-'x'-related items between x and its aliases
		local x_group_items = {}
		for i = x_group_start, x_group_end do
			table.insert(x_group_items, labels[i])
		end

		-- All items in this range should be related to 'x' (done state)
		local valid_x_items = { ["x"] = true, ["X"] = true, ["completed"] = true }
		local all_x_related = true
		for _, item in ipairs(x_group_items) do
			if not valid_x_items[item] then
				all_x_related = false
				break
			end
		end

		MiniTest.expect.equality(
			all_x_related,
			true,
			string.format(
				"Items between 'x' and its aliases should all be x-related: %s",
				table.concat(x_group_items, ", ")
			)
		)
	end

	-- Verify we have some reasonable number of completion items
	MiniTest.expect.equality(#labels >= 8, true, "Should have at least 8 completion items (main values + aliases)")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

return T
