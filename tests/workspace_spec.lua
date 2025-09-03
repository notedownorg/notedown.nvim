-- Simple tests for workspace initialization and status functionality
-- Running without a complex testing framework

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local fixtures = require("fixtures")
local test_utils = require("test_utils")
local assert_contains = test_utils.assert_contains
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec
local wait_for_lsp = test_utils.wait_for_lsp

local function test_workspace_status_command()
	print_test("workspace status command")

	-- Use inline approach like config_spec (which works)
	local workspace_path = vim.fn.tempname() .. "-workspace-test"
	vim.fn.mkdir(workspace_path, "p")

	-- Create .notedown directory
	vim.fn.mkdir(workspace_path .. "/.notedown", "p")

	-- Create a test file
	local handle = io.open(workspace_path .. "/index.md", "w")
	if handle then
		handle:write("# Test Workspace\n\nThis is a test file.\n")
		handle:close()
	end

	-- Change to workspace directory
	vim.cmd("cd " .. workspace_path)

	-- Open the file
	vim.cmd("edit index.md")

	-- Test the command
	local success, output = pcall(vim.fn.execute, "NotedownWorkspaceStatus")

	if not success then
		vim.fn.system({ "rm", "-rf", workspace_path })
		error("NotedownWorkspaceStatus command failed: " .. tostring(output))
	end

	-- Verify the workspace is detected correctly
	assert_contains(output, "In Notedown Workspace: Yes", "Should detect notedown workspace")
	assert_contains(output, "(.notedown directory)", "Should show auto-detection method")

	vim.fn.system({ "rm", "-rf", workspace_path })
end

local function test_lsp_client_detection()
	print_test("LSP client detection")

	-- Use inline approach for reliability
	local workspace = vim.fn.tempname() .. "-lsp-detection"
	vim.fn.mkdir(workspace, "p")

	-- Create .notedown directory
	vim.fn.mkdir(workspace .. "/.notedown", "p")

	-- Create a test file
	local handle = io.open(workspace .. "/index.md", "w")
	if handle then
		handle:write("# LSP Test\n\nThis is a test file for LSP detection.\n")
		handle:close()
	end

	-- Change to workspace directory
	vim.cmd("cd " .. workspace)

	-- Open a markdown file
	vim.cmd("edit index.md")

	-- Wait for LSP to initialize
	local lsp_ready = wait_for_lsp(5000)

	if not lsp_ready then
		vim.fn.system({ "rm", "-rf", workspace })
		error("LSP did not initialize within timeout")
	end

	-- Check that LSP client is active
	local clients = vim.lsp.get_clients()
	if #clients == 0 then
		vim.fn.system({ "rm", "-rf", workspace })
		error("No active LSP clients found")
	end

	local notedown_client = nil
	for _, client in ipairs(clients) do
		if client.name == "notedown" then
			notedown_client = client
			break
		end
	end

	if not notedown_client then
		vim.fn.system({ "rm", "-rf", workspace })
		error("Notedown LSP client not found among active clients")
	end

	vim.fn.system({ "rm", "-rf", workspace })
end

-- Execute tests
return run_spec("workspace", {
	test_workspace_status_command,
	test_lsp_client_detection,
})
