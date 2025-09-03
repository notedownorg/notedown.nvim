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

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local fixtures = require("fixtures")
local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec

local function test_config_defaults()
	print_test("config defaults")

	-- Test that config module loads
	local has_config = pcall(require, "notedown.config")
	assert_equals(has_config, true, "Config module should load")

	-- Test server defaults
	local config = require("notedown.config")
	assert_equals(config.defaults.server.name, "notedown", "Server name should be notedown")

	-- Test that server config exists
	assert_equals(type(config.defaults.server.cmd), "table", "Server cmd should be table")
end

local function test_workspace_detection_with_notedown_dir()
	print_test("workspace detection with .notedown directory")

	local workspace_path = fixtures.setup_workspace("basic", "notedown-workspace")

	-- Change to the test workspace
	vim.cmd("cd " .. workspace_path)

	-- Create a markdown buffer
	vim.cmd("edit index.md")

	-- Get workspace status
	local status = require("notedown").get_workspace_status()

	assert_equals(status.is_notedown_workspace, true, "Should detect notedown workspace")
	assert_equals(status.should_use_notedown, true, "Should use notedown")
	assert_equals(status.auto_detected, true, "Should be auto-detected")

	-- Check that workspace_path contains our test path (handle macOS /private/tmp vs /tmp)
	local expected_path = workspace_path:gsub("^/tmp", "/private/tmp")
	local actual_path = status.workspace_path or ""

	-- More flexible path matching to handle different temp directory resolutions
	local path_matches = (actual_path == workspace_path)
		or (actual_path == expected_path)
		or (actual_path:gsub("/private", "") == workspace_path:gsub("/private", ""))
	assert_equals(path_matches, true, "Workspace path should match")

	fixtures.cleanup_workspace(workspace_path)
end

local function test_workspace_detection_without_notedown_dir()
	print_test("workspace detection without .notedown directory")

	local workspace_path = fixtures.setup_workspace("empty", "other-workspace")

	-- Change to the test workspace (no .notedown directory created)
	vim.cmd("cd " .. workspace_path)

	-- Create a markdown buffer
	vim.cmd("edit README.md")

	-- Get workspace status
	local status = require("notedown").get_workspace_status()

	assert_equals(status.is_notedown_workspace, false, "Should not detect as notedown workspace")
	assert_equals(status.should_use_notedown, false, "Should not use notedown")
	assert_equals(status.auto_detected, false, "Should not be auto-detected")

	fixtures.cleanup_workspace(workspace_path)
end

local function test_workspace_detection_parent_directory()
	print_test("workspace detection finds .notedown in parent directory")

	-- Create workspace with inline approach (more reliable than fixture copying)
	local workspace_path = vim.fn.tempname() .. "-notedown-parent"
	vim.fn.mkdir(workspace_path, "p")

	-- Create .notedown directory at root
	vim.fn.mkdir(workspace_path .. "/.notedown", "p")

	-- Create subdirectory and change to it
	local subdir = workspace_path .. "/subdir"
	vim.fn.mkdir(subdir, "p")
	vim.cmd("cd " .. subdir)

	-- Create a markdown buffer
	vim.cmd("edit test.md")

	-- Get workspace status
	local status = require("notedown").get_workspace_status()

	assert_equals(status.is_notedown_workspace, true, "Should find .notedown in parent")
	assert_equals(status.should_use_notedown, true, "Should use notedown")
	assert_equals(status.auto_detected, true, "Should be auto-detected")

	-- Check that workspace_path points to parent directory
	local expected_path = workspace_path:gsub("^/tmp", "/private/tmp")
	local actual_path = status.workspace_path or ""

	-- More flexible path matching to handle different temp directory resolutions
	local path_matches = (actual_path == workspace_path)
		or (actual_path == expected_path)
		or (actual_path:gsub("/private", "") == workspace_path:gsub("/private", ""))
	assert_equals(path_matches, true, "Workspace path should point to parent")

	fixtures.cleanup_workspace(workspace_path)
end

-- Execute tests
return run_spec("config", {
	test_config_defaults,
	test_workspace_detection_with_notedown_dir,
	test_workspace_detection_without_notedown_dir,
	test_workspace_detection_parent_directory,
})
