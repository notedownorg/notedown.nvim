local M = {}
local config = require("notedown.config")

-- Store the final config for use in other functions
local final_config = {}

-- Find the .notedown directory by walking up the directory tree from the given path
local function find_notedown_workspace(start_path)
	-- Convert to absolute path to ensure consistent behavior
	local current_path = vim.fn.resolve(vim.fn.fnamemodify(start_path, ":p:h"))

	-- Walk up the directory tree
	while current_path do
		local notedown_dir = current_path .. "/.notedown"

		-- Check if .notedown directory exists
		if vim.fn.isdirectory(notedown_dir) == 1 then
			return current_path
		end

		-- Move to parent directory
		local parent_path = vim.fn.fnamemodify(current_path, ":h")

		-- If we've reached the root and haven't found .notedown, stop
		if parent_path == current_path then
			break
		end

		current_path = parent_path
	end

	return nil
end

-- Check if the given file is in a notedown workspace
local function is_notedown_workspace(file_path)
	local workspace_root = find_notedown_workspace(file_path or vim.fn.getcwd())
	return workspace_root ~= nil, workspace_root
end

-- Determine if notedown parser should be used for a buffer
local function should_use_notedown_parser(bufnr)
	local file_path = vim.api.nvim_buf_get_name(bufnr)

	-- If no file path, default to markdown
	if file_path == "" then
		return false
	end

	-- Always use workspace detection (automatic mode)
	return is_notedown_workspace(file_path)
end

-- Get current workspace status for a buffer
function M.get_workspace_status(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)

	local is_workspace, workspace_path = is_notedown_workspace(file_path)
	local should_use_notedown = should_use_notedown_parser(bufnr)

	return {
		file_path = file_path,
		cwd = vim.fn.getcwd(),
		is_notedown_workspace = is_workspace,
		workspace_path = workspace_path,
		should_use_notedown = should_use_notedown,
		auto_detected = is_workspace, -- Indicates automatic .notedown detection
		parser_mode = is_workspace and "notedown" or "markdown",
	}
end

function M.setup(opts)
	opts = opts or {}

	final_config = vim.tbl_deep_extend("force", config.defaults, opts)

	-- Check if we're in a notedown workspace and start LSP early if so
	local workspace_root = find_notedown_workspace(vim.fn.getcwd())
	if workspace_root then
		-- We're in a notedown workspace, start the LSP server immediately
		vim.lsp.start({
			name = final_config.server.name,
			cmd = final_config.server.cmd,
			root_dir = workspace_root,
			capabilities = final_config.server.capabilities,
			workspace_folders = {
				{
					uri = vim.uri_from_fname(workspace_root),
					name = vim.fs.basename(workspace_root),
				},
			},
		})
	end

	-- Set up parser selection based on workspace detection
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		pattern = "*.md",
		callback = function(args)
			local bufnr = args.buf

			-- Determine which filetype to use
			if should_use_notedown_parser(bufnr) then
				vim.bo[bufnr].filetype = "notedown"
			else
				vim.bo[bufnr].filetype = "markdown"
			end
		end,
	})

	-- Set up LSP attachment and features for both markdown and notedown filetypes
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "markdown", "notedown" },
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			local file_path = vim.api.nvim_buf_get_name(bufnr)

			-- Ensure LSP is attached to this buffer (start if not already started)
			local workspace_root = find_notedown_workspace(file_path) or final_config.server.root_dir()

			vim.lsp.start({
				name = final_config.server.name,
				cmd = final_config.server.cmd,
				root_dir = workspace_root,
				capabilities = final_config.server.capabilities,
				workspace_folders = {
					{
						uri = vim.uri_from_fname(workspace_root),
						name = vim.fs.basename(workspace_root),
					},
				},
			})

			-- Enable LSP-based folding for notedown files
			if vim.bo.filetype == "notedown" then
				vim.opt_local.foldmethod = "expr"
				vim.opt_local.foldexpr = "v:lua.vim.lsp.foldexpr()"
				vim.opt_local.foldenable = true
				vim.opt_local.foldlevel = 99 -- Start with all folds open

				-- Set up wikilink concealment for notedown files
				M.setup_wikilink_concealment(bufnr)
			end

			-- Set up text object for list items
			M.setup_list_text_object()
		end,
	})
end

-- Get the appropriate notedown LSP client for command execution
local function get_notedown_command_client()
	local clients = vim.lsp.get_active_clients({ name = "notedown" })
	if #clients == 0 then
		vim.notify("Notedown LSP server not active", vim.log.levels.WARN)
		return nil
	end

	-- Find the client that supports executeCommand
	for _, client in ipairs(clients) do
		if client.server_capabilities and client.server_capabilities.executeCommandProvider then
			return client
		end
	end

	vim.notify("No notedown client supports executeCommand", vim.log.levels.WARN)
	return nil
end

-- Get list item boundaries via LSP command
function M.get_list_item_boundaries()
	local client = get_notedown_command_client()
	if not client then
		return nil
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local position = {
		line = cursor[1] - 1, -- Convert to 0-based
		character = cursor[2],
	}

	local params = {
		command = "notedown.getListItemBoundaries",
		arguments = {
			vim.uri_from_bufnr(0),
			position,
		},
	}

	-- Synchronous request to get boundaries
	local result, err = client.request_sync("workspace/executeCommand", params, 1000)
	if err then
		vim.notify("Error getting list item boundaries: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end

	if result and result.result and result.result.found then
		return result.result
	end

	return nil
end

-- Text object for "around list" (al)
function M.setup_list_text_object()
	vim.keymap.set({ "o", "x" }, "al", function()
		local boundaries = M.get_list_item_boundaries()
		if boundaries and boundaries.found then
			local start_line = boundaries.start.line + 1
			local finish_line = boundaries["end"].line

			vim.api.nvim_win_set_cursor(0, { start_line, 0 })
			vim.cmd("normal! V")

			if finish_line > start_line then
				vim.api.nvim_win_set_cursor(0, { finish_line, 0 })
			end
		else
			vim.notify("No list item found at cursor", vim.log.levels.WARN)
		end
	end, { buffer = true, silent = true, desc = "list item" })
end

-- Set up wikilink concealment using LSP
function M.setup_wikilink_concealment(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	-- Configure concealment settings (window-local options)
	vim.api.nvim_set_option_value("conceallevel", 2, { win = 0 })
	vim.api.nvim_set_option_value("concealcursor", "nc", { win = 0 })

	-- Function to apply conceal ranges from LSP
	local function apply_conceal_ranges()
		local client = get_notedown_command_client()
		if not client then
			return
		end

		local params = {
			command = "notedown.getConcealRanges",
			arguments = { vim.uri_from_bufnr(bufnr) },
		}

		-- Request conceal ranges from LSP
		client.request("workspace/executeCommand", params, function(err, result)
			if err then
				vim.notify("Error getting conceal ranges: " .. tostring(err), vim.log.levels.ERROR)
				return
			end

			if not result or not result.ranges then
				return
			end

			-- Clear existing syntax matches for wikilink concealment
			vim.fn.clearmatches()

			-- Apply each conceal range
			for _, range in ipairs(result.ranges) do
				if range.concealType == "wikilinkTarget" then
					-- Convert LSP positions to Vim positions (1-based)
					local start_line = range.start.line + 1
					local start_col = range.start.character + 1
					local end_line = range["end"].line + 1
					local end_col = range["end"].character + 1

					-- Create a match pattern for this specific range
					-- Use matchaddpos for precise character range concealment
					vim.fn.matchaddpos("Conceal", {
						{ start_line, start_col, end_col - start_col + 1 },
					})
				end
			end
		end)
	end

	-- Apply concealment when buffer is loaded
	vim.defer_fn(apply_conceal_ranges, 100)

	-- Re-apply concealment when buffer content changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = bufnr,
		callback = function()
			-- Debounce the conceal range updates
			vim.defer_fn(apply_conceal_ranges, 300)
		end,
	})

	-- Re-apply concealment when LSP client attaches
	vim.api.nvim_create_autocmd("LspAttach", {
		buffer = bufnr,
		callback = function()
			vim.defer_fn(apply_conceal_ranges, 500)
		end,
	})
end

return M
