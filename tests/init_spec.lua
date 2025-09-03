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

-- Tests for notedown plugin initialization

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec

local function test_plugin_setup()
	print_test("plugin setup")

	-- Verify the plugin can be loaded
	local success = pcall(require, "notedown")
	assert_equals(success, true, "Notedown plugin should load successfully")
end

local function test_autocmd_registration()
	print_test("autocmd registration")

	-- Set up notedown with mock server
	require("notedown").setup({
		server = { cmd = { "echo", "mock-server" } },
		parser = { mode = "auto" },
	})

	-- Check that setup completed successfully
	local setup_ok = package.loaded["notedown"] ~= nil
	assert_equals(setup_ok, true, "Notedown should be loaded after setup")
end

local function test_filetype_notedown_workspace()
	print_test("sets correct filetype for notedown workspace")

	local workspace_path = test_utils.create_wikilink_test_workspace("/tmp/test-filetype-workspace")

	-- Create .notedown directory to make it a notedown workspace
	vim.fn.mkdir(workspace_path .. "/.notedown", "p")

	-- Change to workspace and set up notedown
	vim.cmd("cd " .. workspace_path)
	require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })

	-- Open a markdown file
	vim.cmd("edit README.md")

	-- Wait for autocmd to fire
	vim.wait(200)

	-- Check filetype (should be notedown for notedown workspace)
	local filetype = vim.bo.filetype
	assert_equals(filetype, "notedown", "Filetype should be notedown in notedown workspace")

	test_utils.cleanup_test_workspace(workspace_path)
end

local function test_filetype_non_notedown_workspace()
	print_test("sets correct filetype for non-notedown workspace")

	local test_files = {
		["README.md"] = "# Test Workspace\n\nThis is a regular markdown workspace.",
		["notes.md"] = "# Notes\n\nJust regular markdown notes.",
	}
	local workspace_path = test_utils.create_non_notedown_workspace("/tmp/test-markdown-workspace", test_files)

	-- Change to workspace (no .notedown directory)
	vim.cmd("cd " .. workspace_path)
	require("notedown").setup({
		server = { cmd = { "echo", "mock-server" } },
		parser = { mode = "auto", notedown_workspaces = { "/tmp/different-workspace" } },
	})

	-- Open a markdown file
	vim.cmd("edit README.md")

	-- Wait for autocmd to fire
	vim.wait(200)

	-- Check filetype (should be markdown for non-notedown workspace)
	local filetype = vim.bo.filetype
	assert_equals(filetype, "markdown", "Filetype should be markdown in non-notedown workspace")

	test_utils.cleanup_test_workspace(workspace_path)
end

-- Execute tests
return run_spec("init", {
	test_plugin_setup,
	test_autocmd_registration,
	test_filetype_notedown_workspace,
	test_filetype_non_notedown_workspace,
})
