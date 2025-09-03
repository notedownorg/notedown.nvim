-- Shared fixture utilities for tests
local M = {}

-- Available fixture types
M.fixtures = {
	basic = "workspaces/basic", -- Notedown workspace with .notedown directory
	empty = "workspaces/empty", -- Regular workspace without .notedown directory
	parent_detection = "workspaces/parent-detection", -- Workspace with .notedown in parent
}

-- Setup a test workspace by copying from fixtures
function M.setup_workspace(fixture_name, test_name)
	local fixture_path = vim.fn.getcwd() .. "/tests/fixtures/" .. M.fixtures[fixture_name]

	if not vim.fn.isdirectory(fixture_path) then
		error("Fixture not found: " .. fixture_path)
	end

	-- Create temporary workspace
	local workspace_path = vim.fn.tempname() .. "-" .. test_name
	vim.fn.mkdir(workspace_path, "p")

	-- Copy fixture files to temporary workspace (including hidden files)
	vim.fn.system({
		"bash",
		"-c",
		"cp -r " .. vim.fn.shellescape(fixture_path) .. "/. " .. vim.fn.shellescape(workspace_path),
	})

	return workspace_path
end

-- Setup a workspace in a subdirectory (for parent detection tests)
function M.setup_workspace_subdir(fixture_name, test_name, subdir)
	local workspace_path = M.setup_workspace(fixture_name, test_name)
	local subdir_path = workspace_path .. "/" .. subdir

	-- Ensure the subdirectory actually exists
	if not vim.fn.isdirectory(subdir_path) then
		error("Subdirectory not found in fixture: " .. subdir_path)
	end

	return subdir_path
end

-- Cleanup a test workspace
function M.cleanup_workspace(workspace_path)
	vim.fn.system({ "rm", "-rf", workspace_path })
end

return M
