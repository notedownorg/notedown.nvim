-- Simple init for feature tests without lazy.nvim complexity
-- Based on the existing neovim/tests/helpers/minimal_init.lua approach

-- Get project root - go up 1 level from neovim directory to project root
local project_root = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
local neovim_plugin_path = vim.fn.getcwd()

-- Add notedown plugin to runtime path
vim.opt.rtp:prepend(neovim_plugin_path)

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

print("🧪 notedown.nvim test suite")
print("├─ 📁 " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"))
print("├─ 🏠 " .. vim.fn.fnamemodify(project_root, ":t"))

-- Build LSP server binary
local function build_lsp_binary()
	print("├─ 🔨 Building LSP server")

	-- Verify language-server directory exists
	local language_server_dir = project_root .. "/language-server"

	if not vim.fn.isdirectory(language_server_dir) then
		error("❌ Could not find language-server directory")
	end

	-- Build LSP binary to temporary location
	local lsp_binary = vim.fn.tempname() .. "-notedown-language-server"

	-- Change to project root and build
	local old_cwd = vim.fn.getcwd()
	vim.cmd("cd " .. project_root)

	local build_cmd = {
		"go",
		"build",
		"-ldflags",
		"-w -s -X github.com/notedownorg/notedown/pkg/version.version=test",
		"-o",
		lsp_binary,
		"./language-server/",
	}

	local result = vim.fn.system(build_cmd)
	vim.cmd("cd " .. old_cwd)

	if vim.v.shell_error ~= 0 then
		error("❌ Build failed: " .. (result or ""))
	end

	-- Make binary executable
	vim.fn.system({ "chmod", "+x", lsp_binary })

	print("│  └─ ✅ Binary ready")
	return lsp_binary
end

-- Build LSP binary
local lsp_binary = build_lsp_binary()

print("├─ ⚙️  Setting up plugin")
-- Configure notedown plugin with test LSP binary
local notedown_config = require("notedown.config")
notedown_config.defaults.server.cmd = { lsp_binary, "serve", "--log-level", "error" }

require("notedown").setup({
	server = {
		cmd = { lsp_binary, "serve", "--log-level", "error" },
	},
})

-- Load plugin commands (normally done by Neovim's plugin system)
vim.cmd("runtime plugin/notedown.lua")

print("│  └─ ✅ Plugin ready")

-- Basic vim settings for tests
vim.opt.compatible = false
vim.opt.number = true

-- List of all spec files to run
local spec_files = {
	"config_spec",
	"init_spec",
	"workspace_spec",
	"task_completion_spec",
	"task_diagnostics_spec",
	"folding_spec",
	"list_text_object_spec",
}

-- Run all spec files
local function run_all_tests()
	print("└─ Setup complete, running specs...")
	print(" ")
	local total_passed = 0
	local total_failed = 0

	for i, spec_file in ipairs(spec_files) do
		local is_last = (i == #spec_files)
		local prefix = is_last and "└─" or "├─"
		local spec_name = spec_file:gsub("_spec$", "")

		-- Clear any previous modules to ensure fresh state
		package.loaded[spec_file] = nil

		local success, result = pcall(require, spec_file)
		if success and result == true then
			total_passed = total_passed + 1
		else
			local error_msg = tostring(result or "failed")
			if error_msg:len() > 50 then
				error_msg = error_msg:sub(1, 47) .. "..."
			end
			print(prefix .. " ❌ " .. spec_name .. " (" .. error_msg .. ")")
			total_failed = total_failed + 1
		end

		-- Add vertical spacing between specs (except after last one)
		if not is_last then
			print(" ")
		end
	end

	print(" ")
	if total_failed == 0 then
		print("✅ " .. total_passed .. " specs passed")
		vim.cmd("qall!")
	else
		print("❌ " .. total_failed .. " specs failed, " .. total_passed .. " passed")
		print("")
		vim.cmd("cquit!")
	end
end

-- Execute all tests
run_all_tests()
