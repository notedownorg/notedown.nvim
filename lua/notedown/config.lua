local M = {}

M.defaults = {
	server = {
		name = "notedown",
		cmd = { "notedown-language-server", "serve", "--log-level", "debug", "--log-file", "/tmp/notedown.log" },
		root_dir = function()
			return vim.fn.getcwd()
		end,
		capabilities = vim.lsp.protocol.make_client_capabilities(),
	},
	-- No additional configuration needed - the 'al' text object is automatically available
}

return M
