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

-- Tests for notedown configuration and workspace detection

local MiniTest = require("mini.test")
local utils = require("helpers.utils")

local T = MiniTest.new_set()

T["config defaults"] = function()
	local child = utils.new_child_neovim()

	-- Test that config module loads
	local has_config = child.lua_get('pcall(require, "notedown.config")')
	MiniTest.expect.equality(has_config, true)

	-- Test server defaults
	local server_name = child.lua_get('require("notedown.config").defaults.server.name')
	MiniTest.expect.equality(server_name, "notedown")

	-- Test that server config exists
	local server_cmd = child.lua_get('require("notedown.config").defaults.server.cmd')
	MiniTest.expect.equality(type(server_cmd), "table")

	child.stop()
end

T["workspace detection"] = MiniTest.new_set()

T["workspace detection"]["detects .notedown directory"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-notedown-workspace")
	local child = utils.new_child_neovim()

	-- Create .notedown directory to mark this as a notedown workspace
	child.lua('vim.fn.mkdir("' .. workspace_path .. '/.notedown", "p")')

	-- Change to the test workspace
	child.lua('vim.fn.chdir("' .. workspace_path .. '")')

	-- Set up notedown (automatic detection, no configuration needed)
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Create a markdown buffer
	child.lua('vim.cmd("edit README.md")')

	-- Get workspace status
	local status = child.lua_get('require("notedown").get_workspace_status()')

	MiniTest.expect.equality(status.is_notedown_workspace, true)
	MiniTest.expect.equality(status.should_use_notedown, true)
	MiniTest.expect.equality(status.auto_detected, true)
	-- Check that workspace_path contains our test path (handle macOS /private/tmp vs /tmp)
	local expected_path = workspace_path:gsub("^/tmp", "/private/tmp")
	local actual_path = status.workspace_path or ""
	local path_matches = (actual_path == workspace_path) or (actual_path == expected_path)
	MiniTest.expect.equality(path_matches, true)

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

T["workspace detection"]["ignores directory without .notedown"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-other-workspace")
	local child = utils.new_child_neovim()

	-- Change to the test workspace (no .notedown directory created)
	child.lua('vim.fn.chdir("' .. workspace_path .. '")')

	-- Set up notedown (automatic detection)
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Create a markdown buffer
	child.lua('vim.cmd("edit README.md")')

	-- Get workspace status
	local status = child.lua_get('require("notedown").get_workspace_status()')

	MiniTest.expect.equality(status.is_notedown_workspace, false)
	MiniTest.expect.equality(status.should_use_notedown, false)
	MiniTest.expect.equality(status.auto_detected, false)

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

T["workspace detection"]["finds .notedown in parent directory"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-notedown-parent")
	local child = utils.new_child_neovim()

	-- Create .notedown directory in workspace root
	child.lua('vim.fn.mkdir("' .. workspace_path .. '/.notedown", "p")')

	-- Create nested directory structure
	local nested_path = workspace_path .. "/docs/nested"
	child.lua('vim.fn.mkdir("' .. nested_path .. '", "p")')

	-- Change to the nested directory
	child.lua('vim.fn.chdir("' .. nested_path .. '")')

	-- Set up notedown (automatic detection)
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Create a markdown buffer in the nested directory
	child.lua('vim.cmd("edit nested-doc.md")')

	-- Get workspace status
	local status = child.lua_get('require("notedown").get_workspace_status()')

	MiniTest.expect.equality(status.is_notedown_workspace, true)
	MiniTest.expect.equality(status.should_use_notedown, true)
	MiniTest.expect.equality(status.auto_detected, true)
	-- Should find the workspace root, not the nested directory
	local expected_path = workspace_path:gsub("^/tmp", "/private/tmp")
	local actual_path = status.workspace_path or ""
	local path_matches = (actual_path == workspace_path) or (actual_path == expected_path)
	MiniTest.expect.equality(path_matches, true)

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

return T
