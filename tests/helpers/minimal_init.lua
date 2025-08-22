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

-- Minimal init file for testing notedown.nvim with mini.test

-- Add current directory to package path for testing
local current_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.rtp:prepend(current_dir)

-- Add tests directory to Lua package path
local tests_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

-- Set up dependency paths
local deps_path = vim.fn.stdpath("data") .. "/test-deps"
vim.fn.mkdir(deps_path, "p")

-- Function to ensure mini.nvim is available
local function ensure_mini_nvim()
	local mini_path = deps_path .. "/mini.nvim"

	if vim.fn.isdirectory(mini_path) == 0 then
		print("Downloading mini.nvim for testing...")
		vim.fn.system({
			"git",
			"clone",
			"--depth",
			"1",
			"https://github.com/echasnovski/mini.nvim",
			mini_path,
		})
	end

	vim.opt.rtp:prepend(mini_path)
end

-- Ensure dependencies and set up mini.test
ensure_mini_nvim()
require("mini.test").setup()

-- Disable unnecessary providers for testing
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
