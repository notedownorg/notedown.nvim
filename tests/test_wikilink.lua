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

-- Tests for wikilink functionality in Neovim

local MiniTest = require("mini.test")
local utils = require("helpers.utils")
local lsp = require("helpers.lsp_dedicated")

local T = MiniTest.new_set()

-- Test workspace setup for wikilink tests
local function setup_wikilink_workspace(path)
	local workspace = utils.create_test_workspace(path)

	-- Create test files with wikilinks
	utils.write_file(
		workspace .. "/index.md",
		"# Main Index\n\nThis links to [[docs/api]] and [[notes/meeting]].\n\nAlso see [[non-existent-file]].\n"
	)
	utils.write_file(workspace .. "/docs/api.md", "# API Documentation\n\nBack to [[index]].\n")
	utils.write_file(workspace .. "/notes/meeting.md", "# Meeting Notes\n\nReference: [[docs/api]]\n")

	return workspace
end

T["wikilink navigation"] = MiniTest.new_set()

T["wikilink navigation"]["goes to existing file"] = function()
	local workspace = setup_wikilink_workspace("/tmp/test-wikilink-nav")
	local child = utils.new_child_neovim()

	-- Setup notedown with real LSP server
	lsp.setup(child, workspace)

	-- Open file and position cursor on wikilink
	child.lua('vim.cmd("edit ' .. workspace .. '/index.md")')

	-- Wait for LSP to initialize
	lsp.wait_for_ready(child)

	-- Position cursor on wikilink
	child.lua('vim.fn.search("docs/api")')

	-- Trigger go-to-definition
	child.lua("vim.lsp.buf.definition()")

	-- Wait for navigation
	utils.wait_for_condition(function()
		return child.lua_get('vim.fn.expand("%:t")') == "api.md"
	end, 3000)

	-- Verify we actually navigated to the api.md file
	local current_file = child.lua_get('vim.fn.expand("%:p")')
	local expected_api_file = workspace .. "/docs/api.md"

	-- Test should fail if we're still in index.md or any other file
	MiniTest.expect.equality(current_file, expected_api_file)

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["wikilink navigation"]["creates non-existent file"] = function()
	local workspace = setup_wikilink_workspace("/tmp/test-wikilink-create")
	local child = utils.new_child_neovim()

	-- Setup notedown with real LSP server
	lsp.setup(child, workspace)

	-- Open file and position cursor on non-existent wikilink
	child.lua('vim.cmd("edit ' .. workspace .. '/index.md")')

	-- Wait for LSP to initialize
	lsp.wait_for_ready(child)

	-- Position cursor on "non-existent-file" wikilink
	child.lua('vim.fn.search("non-existent-file")')

	-- Verify the target file doesn't exist yet
	local file_exists_before = vim.fn.filereadable(workspace .. "/non-existent-file.md") == 1
	MiniTest.expect.equality(file_exists_before, false)

	-- Trigger go-to-definition
	child.lua("vim.lsp.buf.definition()")

	-- Wait for file creation and navigation
	utils.wait_for_condition(function()
		return child.lua_get('vim.fn.expand("%:t")') == "non-existent-file.md"
	end, 3000)

	-- Verify we navigated to the new file
	local current_file = child.lua_get('vim.fn.expand("%:p")')
	local expected_new_file = workspace .. "/non-existent-file.md"
	MiniTest.expect.equality(current_file, expected_new_file)

	-- Verify the file was actually created on disk
	local file_exists_after = vim.fn.filereadable(workspace .. "/non-existent-file.md") == 1
	MiniTest.expect.equality(file_exists_after, true)

	-- Verify it has basic content
	local file_content = vim.fn.readfile(workspace .. "/non-existent-file.md")
	MiniTest.expect.equality(#file_content > 0, true)
	MiniTest.expect.equality(string.find(file_content[1], "non%-existent%-file") ~= nil, true)

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["wikilink completion"] = MiniTest.new_set()

T["wikilink completion"]["provides comprehensive suggestions"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-wikilink-completion-comprehensive")
	local child = utils.new_child_neovim()

	-- Create comprehensive test files for different completion scenarios
	-- 1. Existing files in root and subdirectories
	utils.write_file(workspace .. "/readme.md", "# README")
	utils.write_file(workspace .. "/docs/getting-started.md", "# Getting Started")
	utils.write_file(workspace .. "/docs/api.md", "# API Documentation")
	utils.write_file(workspace .. "/notes/meeting-notes.md", "# Meeting Notes")
	utils.write_file(workspace .. "/projects/alpha.md", "# Project Alpha")

	-- 2. File with wikilink to non-existent target (for referenced target completion)
	utils.write_file(workspace .. "/index.md", "# Main\n\nSee [[non-existent-target]] and [[future-doc]].")

	-- 3. Empty directories (for directory completion)
	vim.fn.mkdir(workspace .. "/empty-dir", "p")
	vim.fn.mkdir(workspace .. "/specs", "p")

	-- Setup with real LSP
	lsp.setup(child, workspace)

	-- Open index.md to ensure LSP indexes the wikilinks
	child.lua('vim.cmd("edit ' .. workspace .. '/index.md")')
	lsp.wait_for_ready(child)

	-- Wait for workspace file discovery to complete
	vim.loop.sleep(3000)

	-- Create test file with wikilink content and manually update buffer
	child.lua('vim.cmd("edit ' .. workspace .. '/test-completion.md")')

	-- Test completion by properly opening document and updating content
	child.lua([[
		_G.test_completion_result = nil
		_G.test_completion_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- First ensure document is opened in LSP
			client.notify('textDocument/didOpen', {
				textDocument = {
					uri = uri,
					languageId = 'markdown',
					version = 1,
					text = '# Test Completion\n\nLink to [['
				}
			})
			
			-- Wait for didOpen to be processed
			vim.wait(200)
			
			-- Create content with partial wikilink for completion context
			local new_content = "# Test Completion\n\nLink to [["
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(new_content, "\n"))
			
			-- Send didChange notification to update LSP server state
			client.notify('textDocument/didChange', {
				textDocument = { uri = uri, version = 2 },
				contentChanges = {{ text = new_content }}
			})
			
			-- Wait for the change to be processed
			vim.wait(500)
			
			-- Request completion at position inside wikilink (right after "[[")
			local params = {
				textDocument = { uri = uri },
				position = { line = 2, character = 10 }
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

	-- Extract completion labels
	local completion_labels = {}
	for _, item in ipairs(items) do
		table.insert(completion_labels, item.label)
	end

	-- Verify we got actual completions and they make sense
	MiniTest.expect.equality(#completion_labels > 0, true, "Should have at least one completion")

	-- Test different types of completions
	local found = {
		existing_root = false, -- README, readme
		existing_subdir = false, -- docs/api, notes/meeting-notes, etc.
		referenced_nonexistent = false, -- non-existent-target, future-doc
		directories = false, -- docs/, notes/, projects/
	}

	for _, label in ipairs(completion_labels) do
		-- Existing files in root (could be README or readme)
		if label == "readme" or label == "README" then
			found.existing_root = true
		end

		-- Existing files in subdirectories
		if string.match(label, "docs/") or string.match(label, "notes/") or string.match(label, "projects/") then
			found.existing_subdir = true
		end

		-- Non-existent but referenced targets
		if label == "non-existent-target" or label == "future-doc" then
			found.referenced_nonexistent = true
		end

		-- Directory paths (various patterns)
		if string.match(label, "/$") or label == "docs" or label == "notes" or label == "projects" then
			found.directories = true
		end
	end

	-- Verify that the core completion functionality is working
	local has_lsp_clients = child.lua_get("#vim.lsp.get_active_clients() > 0")
	MiniTest.expect.equality(has_lsp_clients, true)

	-- Verify we got all expected completion types
	MiniTest.expect.equality(found.existing_root, true, "Should find existing root files")
	MiniTest.expect.equality(found.existing_subdir, true, "Should find existing subdirectory files")
	MiniTest.expect.equality(found.directories, true, "Should find directory completions")
	MiniTest.expect.equality(found.referenced_nonexistent, true, "Should find non-existent referenced targets")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["wikilink diagnostics"] = MiniTest.new_set()

T["wikilink diagnostics"]["shows conflicts for ambiguous links"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-wikilink-conflicts")
	local child = utils.new_child_neovim()

	-- Create conflicting files that will make [[api]] ambiguous
	utils.write_file(workspace .. "/api.md", "# API v1")
	utils.write_file(workspace .. "/docs/api.md", "# API v2")
	utils.write_file(workspace .. "/conflict-test.md", "# Conflict Test\n\nLink to [[api]] here.")

	-- Setup LSP
	lsp.setup(child, workspace)

	-- Wait for workspace file discovery
	vim.loop.sleep(3000)

	-- Open the file with ambiguous wikilink
	child.lua('vim.cmd("edit ' .. workspace .. '/conflict-test.md")')
	lsp.wait_for_ready(child)

	-- Ensure document is properly opened in LSP and indexed
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
					text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
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
	MiniTest.expect.equality(#diagnostics > 0, true, "Should have at least one diagnostic for ambiguous wikilink")

	-- Find the ambiguous wikilink diagnostic
	local found_ambiguous_diagnostic = false
	local ambiguous_message = ""

	for _, diag in ipairs(diagnostics) do
		local message = diag.message or ""
		if string.find(message, "Ambiguous wikilink") and string.find(message, "api") then
			found_ambiguous_diagnostic = true
			ambiguous_message = message

			-- Verify diagnostic properties
			MiniTest.expect.equality(diag.severity, 2, "Should be Warning severity (2)")
			MiniTest.expect.equality(diag.source, "notedown", "Should be from notedown source")
			-- Note: range might be nil due to LSP serialization, focus on the diagnostic content
			break
		end
	end

	MiniTest.expect.equality(found_ambiguous_diagnostic, true, "Should find ambiguous wikilink diagnostic")
	-- Verify message mentions both conflicting files
	MiniTest.expect.equality(string.find(ambiguous_message, "api.md") ~= nil, true, "Should mention api.md")
	MiniTest.expect.equality(string.find(ambiguous_message, "docs/api.md") ~= nil, true, "Should mention docs/api.md")

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

T["wikilink code actions"] = MiniTest.new_set()

T["wikilink code actions"]["resolves ambiguous wikilink to root level file"] = function()
	local workspace = utils.create_test_workspace("/tmp/test-wikilink-codeactions")
	local child = utils.new_child_neovim()

	-- Create conflicting files with same base name to create ambiguity
	utils.write_file(workspace .. "/config.md", "# Root Config\n\nThis is the root configuration file.")
	utils.write_file(workspace .. "/docs/config.md", "# Docs Config\n\nThis is the documentation configuration.")
	utils.write_file(workspace .. "/project/config.md", "# Project Config\n\nThis is the project configuration.")

	-- Create additional conflicting files for a second test
	utils.write_file(workspace .. "/guide.md", "# Root Guide\n\nThis is the root guide file.")
	utils.write_file(workspace .. "/docs/guide.md", "# Docs Guide\n\nThis is the documentation guide.")

	-- Create test file with two ambiguous wikilinks
	utils.write_file(
		workspace .. "/main.md",
		"# Main\n\nThis links to [[config]] which is ambiguous.\n\nAlso see [[guide]] for more info."
	)

	-- Setup LSP
	lsp.setup(child, workspace)

	-- Wait for workspace file discovery
	vim.loop.sleep(3000)

	-- Open the file with ambiguous wikilink
	child.lua('vim.cmd("edit ' .. workspace .. '/main.md")')
	lsp.wait_for_ready(child)

	-- Position cursor on the ambiguous wikilink
	child.lua('vim.fn.search("config")')

	-- Ensure document is properly opened in LSP and indexed
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
					text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
				}
			})
		end
	]])

	-- Wait for diagnostics and indexing to complete
	vim.loop.sleep(2000)

	-- Request code actions for the ambiguous wikilink
	child.lua([[
		_G.test_code_actions_result = nil
		_G.test_code_actions_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Get current cursor position (should be on "config")
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line = cursor[1] - 1  -- Convert to 0-based
			local character = cursor[2]
			
			-- Get diagnostics for this buffer to include in context
			local diagnostics = vim.diagnostic.get(0)
			local lsp_diagnostics = {}
			for _, diag in ipairs(diagnostics) do
				table.insert(lsp_diagnostics, {
					range = diag.range or {
						start = { line = diag.lnum or line, character = diag.col or character },
						['end'] = { line = diag.end_lnum or line, character = diag.end_col or (character + 6) }
					},
					message = diag.message or "",
					code = diag.code or "ambiguous-wikilink",
					severity = diag.severity or 2,
					source = diag.source or "notedown"
				})
			end
			
			-- Request code actions for the range containing the ambiguous wikilink
			local params = {
				textDocument = { uri = uri },
				range = {
					start = { line = line, character = character },
					['end'] = { line = line, character = character + 6 }  -- length of "config"
				},
				context = {
					diagnostics = lsp_diagnostics
				}
			}
			
			local result, err = client.request_sync('textDocument/codeAction', params, 5000)
			if err then
				_G.test_code_actions_error = tostring(err)
			elseif result then
				_G.test_code_actions_result = result.result
			end
		end
	]])

	-- Check for code action errors
	local code_actions_error = child.lua_get("_G.test_code_actions_error")
	if code_actions_error and code_actions_error ~= vim.NIL then
		MiniTest.expect.equality(
			code_actions_error,
			nil,
			"Code action request should not have errors: " .. tostring(code_actions_error)
		)
	end

	-- Get code action results
	local code_actions_result = child.lua_get("_G.test_code_actions_result")
	MiniTest.expect.equality(type(code_actions_result), "table", "Should get code actions result")
	MiniTest.expect.equality(#code_actions_result > 0, true, "Should have at least one code action")

	-- Find code action for root level config file (should have "./config" in title or edit)
	local found_root_action = false
	local root_action = nil

	for _, action in ipairs(code_actions_result) do
		local title = action.title or ""
		if
			string.find(title, "config.md")
			and not string.find(title, "docs/")
			and not string.find(title, "project/")
		then
			found_root_action = true
			root_action = action
			break
		end
	end

	MiniTest.expect.equality(found_root_action, true, "Should find code action for root config file")
	MiniTest.expect.equality(root_action.kind, "quickfix", "Should be a quickfix code action")

	-- Verify the edit would transform [[config]] to [[./config|config]]
	if root_action and root_action.edit and root_action.edit.changes then
		local uri = vim.uri_from_fname(workspace .. "/main.md")
		local changes = root_action.edit.changes[uri]
		if changes and #changes > 0 then
			local new_text = changes[1].newText
			MiniTest.expect.equality(
				new_text,
				"[[./config|config]]",
				"Should transform to qualified path with display text"
			)
		end
	end

	-- Verify we have multiple code actions (one for each matching file)
	MiniTest.expect.equality(#code_actions_result >= 3, true, "Should have code actions for all three config files")

	-- Apply the root level code action
	if root_action and root_action.edit then
		child.lua(string.format('vim.lsp.util.apply_workspace_edit(%s, "utf-8")', vim.inspect(root_action.edit)))

		-- Wait for the edit to be applied
		vim.loop.sleep(500)

		-- Verify the content was updated
		local updated_content = child.lua_get('table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\\n")')
		MiniTest.expect.equality(
			string.find(updated_content, "%[%[%.%/config%|config%]%]") ~= nil,
			true,
			"Content should contain [[./config|config]]"
		)
		MiniTest.expect.equality(
			string.find(updated_content, "%[%[config%]%]") == nil,
			true,
			"Original [[config]] should be replaced"
		)
	end

	-- Now test resolving the second ambiguous wikilink (guide) to subdirectory file
	-- Position cursor on the "guide" wikilink
	child.lua('vim.fn.search("guide")')

	-- Request code actions for the guide wikilink
	child.lua([[
		_G.test_guide_actions_result = nil
		_G.test_guide_actions_error = nil
		
		local client = vim.lsp.get_active_clients()[1]
		if client then
			local uri = vim.uri_from_bufnr(0)
			
			-- Get current cursor position (should be on "guide")
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line = cursor[1] - 1  -- Convert to 0-based
			local character = cursor[2]
			
			-- Get diagnostics for this buffer to include in context
			local diagnostics = vim.diagnostic.get(0)
			local lsp_diagnostics = {}
			for _, diag in ipairs(diagnostics) do
				table.insert(lsp_diagnostics, {
					range = diag.range or {
						start = { line = diag.lnum or line, character = diag.col or character },
						['end'] = { line = diag.end_lnum or line, character = diag.end_col or (character + 5) }
					},
					message = diag.message or "",
					code = diag.code or "ambiguous-wikilink",
					severity = diag.severity or 2,
					source = diag.source or "notedown"
				})
			end
			
			-- Request code actions for the range containing the ambiguous guide wikilink
			local params = {
				textDocument = { uri = uri },
				range = {
					start = { line = line, character = character },
					['end'] = { line = line, character = character + 5 }  -- length of "guide"
				},
				context = {
					diagnostics = lsp_diagnostics
				}
			}
			
			local result, err = client.request_sync('textDocument/codeAction', params, 5000)
			if err then
				_G.test_guide_actions_error = tostring(err)
			elseif result then
				_G.test_guide_actions_result = result.result
			end
		end
	]])

	-- Check for code action errors
	local guide_actions_error = child.lua_get("_G.test_guide_actions_error")
	if guide_actions_error and guide_actions_error ~= vim.NIL then
		MiniTest.expect.equality(
			guide_actions_error,
			nil,
			"Guide code action request should not have errors: " .. tostring(guide_actions_error)
		)
	end

	-- Get code action results for guide
	local guide_actions_result = child.lua_get("_G.test_guide_actions_result")
	MiniTest.expect.equality(type(guide_actions_result), "table", "Should get guide code actions result")
	MiniTest.expect.equality(#guide_actions_result > 0, true, "Should have at least one guide code action")

	-- Find code action for docs subdirectory guide file (should contain "docs/guide.md")
	local found_docs_action = false
	local docs_action = nil

	for _, action in ipairs(guide_actions_result) do
		local title = action.title or ""
		if string.find(title, "docs/guide.md") then
			found_docs_action = true
			docs_action = action
			break
		end
	end

	MiniTest.expect.equality(found_docs_action, true, "Should find code action for docs guide file")
	MiniTest.expect.equality(docs_action.kind, "quickfix", "Should be a quickfix code action")

	-- Verify the edit would transform [[guide]] to [[docs/guide|guide]]
	if docs_action and docs_action.edit and docs_action.edit.changes then
		local uri = vim.uri_from_fname(workspace .. "/main.md")
		local changes = docs_action.edit.changes[uri]
		if changes and #changes > 0 then
			local new_text = changes[1].newText
			MiniTest.expect.equality(
				new_text,
				"[[docs/guide|guide]]",
				"Should transform to subdirectory qualified path with display text"
			)
		end
	end

	-- Apply the docs subdirectory code action
	if docs_action and docs_action.edit then
		child.lua(string.format('vim.lsp.util.apply_workspace_edit(%s, "utf-8")', vim.inspect(docs_action.edit)))

		-- Wait for the edit to be applied
		vim.loop.sleep(500)

		-- Verify the content was updated to include both transformations
		local final_content = child.lua_get('table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\\n")')
		MiniTest.expect.equality(
			string.find(final_content, "%[%[docs%/guide%|guide%]%]") ~= nil,
			true,
			"Content should contain [[docs/guide|guide]]"
		)
		MiniTest.expect.equality(
			string.find(final_content, "%[%[%.%/config%|config%]%]") ~= nil,
			true,
			"Content should still contain [[./config|config]] from first transformation"
		)
		MiniTest.expect.equality(
			string.find(final_content, "%[%[guide%]%]") == nil,
			true,
			"Original [[guide]] should be replaced"
		)
	end

	child.stop()
	utils.cleanup_test_workspace(workspace)
	lsp.cleanup_binary()
end

return T
