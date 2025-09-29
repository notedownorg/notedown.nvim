if vim.g.loaded_notedown then
	return
end
vim.g.loaded_notedown = 1

-- Register treesitter language if treesitter is available
if vim.treesitter and vim.treesitter.language then
	vim.treesitter.language.register("markdown", "notedown")
else
	vim.notify("TreeSitter not available - syntax highlighting may be limited", vim.log.levels.WARN)
end

-- Initialize the plugin with default settings
require("notedown").setup()

-- Note: Filetype detection is now handled in init.lua based on workspace detection
-- This autocmd is kept for compatibility but may be overridden

vim.api.nvim_create_user_command("NotedownReload", function()
	-- Stop existing LSP clients
	vim.lsp.stop_client(vim.lsp.get_clients({ name = "notedown" }))

	-- Clear module cache
	package.loaded["notedown"] = nil
	package.loaded["notedown.config"] = nil
	package.loaded["notedown.init"] = nil

	-- Reload the plugin
	require("notedown").setup()

	-- If current buffer is markdown, trigger the autocmd
	if vim.bo.filetype == "markdown" then
		vim.api.nvim_exec_autocmds("FileType", { pattern = "markdown" })
	end

	vim.notify("Notedown plugin and LSP reloaded", vim.log.levels.INFO)
end, {
	desc = "Reload the Notedown plugin and restart LSP",
})

vim.api.nvim_create_user_command("NotedownWorkspaceStatus", function()
	local notedown = require("notedown")
	local status = notedown.get_workspace_status()

	local message = string.format(
		[[
Notedown Workspace Status:
  File: %s
  In Notedown Workspace: %s
  Should Use Notedown Parser: %s
  LSP Server Status: %s (%d clients)
  ]],
		status.file_path or "No file",
		status.is_notedown_workspace and "Yes" or "No",
		status.should_use_notedown and "Yes" or "No",
		status.lsp_status or "Unknown",
		status.lsp_client_count or 0
	)

	if status.workspace_path then
		message = message .. string.format("  Matched Workspace: %s\n", status.workspace_path)
	end

	if status.auto_detected then
		message = message .. "  Detection Method: Auto-detected (.notedown directory)\n"
	else
		message = message .. "  Detection Method: No .notedown directory found\n"
	end

	print(message)
end, {
	desc = "Show workspace status for current buffer",
})

vim.api.nvim_create_user_command("NotedownMoveUp", function()
	require("notedown").move_list_item_up()
end, {
	desc = "Move list item up",
})

vim.api.nvim_create_user_command("NotedownMoveDown", function()
	require("notedown").move_list_item_down()
end, {
	desc = "Move list item down",
})

vim.api.nvim_create_user_command("NotedownExecuteCode", function(opts)
	local language = opts.args ~= "" and opts.args or nil
	require("notedown").execute_code_blocks(language)
end, {
	desc = "Execute code blocks in current document",
	nargs = "?",
	complete = function()
		return { "go" } -- Will expand as more languages are supported
	end,
})
