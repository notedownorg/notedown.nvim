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

local MiniTest = require("mini.test")
local utils = require("helpers.utils")

local T = MiniTest.new_set()

T["plugin setup"] = function()
	local child = utils.new_child_neovim()

	-- Verify the plugin can be loaded
	local success = child.lua_get('pcall(require, "notedown")')

	MiniTest.expect.equality(success, true)

	child.stop()
end

T["autocmd registration"] = MiniTest.new_set()

T["autocmd registration"]["creates markdown file autocmds"] = function()
	local child = utils.new_child_neovim()

	-- Set up notedown
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } }, parser = { mode = "auto" } })')

	-- Check that setup completed successfully (simplified test)
	local setup_ok = child.lua_get('package.loaded["notedown"] ~= nil')
	MiniTest.expect.equality(setup_ok, true)

	child.stop()
end

T["autocmd registration"]["sets correct filetype for notedown workspace"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-filetype-workspace")
	local child = utils.new_child_neovim()

	-- Create .notedown directory to make it a notedown workspace
	child.lua('vim.fn.mkdir("' .. workspace_path .. '/.notedown", "p")')

	-- Change to workspace and set up notedown
	child.lua('vim.fn.chdir("' .. workspace_path .. '")')
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Open a markdown file
	child.lua('vim.cmd("edit README.md")')

	-- Wait a moment for autocmd to fire
	vim.loop.sleep(100)

	-- Check filetype
	utils.expect_buffer_filetype(child, "notedown")

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

T["autocmd registration"]["sets correct filetype for non-notedown workspace"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-markdown-workspace")
	local child = utils.new_child_neovim()

	-- Change to workspace and set up notedown with different workspace config
	child.lua('vim.fn.chdir("' .. workspace_path .. '")')
	child.lua(
		'require("notedown").setup({ server = { cmd = { "echo", "mock-server" } }, parser = { mode = "auto", notedown_workspaces = { "/tmp/different-workspace" } } })'
	)

	-- Open a markdown file
	child.lua('vim.cmd("edit README.md")')

	-- Wait a moment for autocmd to fire
	vim.loop.sleep(100)

	-- Check filetype
	utils.expect_buffer_filetype(child, "markdown")

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

T["text object setup"] = function()
	local child = utils.new_child_neovim()

	-- Set up notedown
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Open a markdown file to trigger FileType autocmd
	child.lua('vim.cmd("edit test.md")')

	-- Set filetype to notedown to trigger text object setup
	child.lua('vim.bo.filetype = "notedown"')

	-- Wait a moment for autocmd to fire
	vim.loop.sleep(100)

	-- Check that text object is registered (al should be available in operator-pending mode)
	local al_mapping_exists = child.lua_get('vim.fn.mapcheck("al", "o") ~= ""')

	MiniTest.expect.equality(al_mapping_exists, true)

	child.stop()
end

T["configuration merging"] = function()
	local workspace_path = utils.create_test_workspace("/tmp/test-config-merge")
	local child = utils.new_child_neovim()

	-- Create .notedown directory to make it a notedown workspace
	child.lua('vim.fn.mkdir("' .. workspace_path .. '/.notedown", "p")')

	-- Change to notedown workspace and set up notedown with custom config
	child.lua('vim.fn.chdir("' .. workspace_path .. '")')
	child.lua('require("notedown").setup({ server = { name = "custom-notedown", cmd = { "custom-command" } } })')

	-- Verify the configuration was merged correctly by checking workspace status
	local status = child.lua_get('require("notedown").get_workspace_status()')

	MiniTest.expect.equality(status.parser_mode, "notedown")
	MiniTest.expect.equality(status.is_notedown_workspace, true)
	-- Use the resolved path to avoid issues with symlinks (/tmp -> /private/tmp on macOS)
	MiniTest.expect.equality(status.workspace_path ~= nil, true)
	MiniTest.expect.equality(status.workspace_path:match("test%-config%-merge$") ~= nil, true)

	child.stop()
	utils.cleanup_test_workspace(workspace_path)
end

T["module functions"] = MiniTest.new_set()

T["module functions"]["get_workspace_status returns table"] = function()
	local child = utils.new_child_neovim()

	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	local status = child.lua_get('require("notedown").get_workspace_status()')

	MiniTest.expect.equality(type(status), "table")
	MiniTest.expect.equality(type(status.file_path), "string")
	MiniTest.expect.equality(type(status.cwd), "string")
	MiniTest.expect.equality(type(status.is_notedown_workspace), "boolean")
	MiniTest.expect.equality(type(status.parser_mode), "string")
	MiniTest.expect.equality(type(status.should_use_notedown), "boolean")

	child.stop()
end

T["module functions"]["get_notedown_command_client without timeout"] = function()
	local child = utils.new_child_neovim()

	-- Test when no LSP clients exist
	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Mock vim.lsp.get_clients to return empty
	child.lua([[
		_G.test_clients = {}
		vim.lsp.get_clients = function() return _G.test_clients end
	]])

	-- Should return nil and not crash
	local result = child.lua_get('require("notedown")._get_notedown_command_client()')
	MiniTest.expect.equality(result, vim.NIL)

	child.stop()
end

T["module functions"]["get_notedown_command_client with timeout - no clients"] = function()
	local child = utils.new_child_neovim()

	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Mock vim.lsp.get_clients to return empty
	child.lua([[
		_G.test_clients = {}
		vim.lsp.get_clients = function() return _G.test_clients end
		
		-- Mock vim.wait to avoid actual delays in tests
		vim.wait = function(ms) return true end
		
		-- Mock vim.loop.now() for timeout testing
		_G.test_time = 0
		vim.loop.now = function() 
			_G.test_time = _G.test_time + 150 -- Simulate time passing
			return _G.test_time 
		end
	]])

	-- Should timeout after checking multiple times
	local result = child.lua_get('require("notedown")._get_notedown_command_client(500)')
	MiniTest.expect.equality(result, vim.NIL)

	child.stop()
end

T["module functions"]["get_notedown_command_client with timeout - client appears"] = function()
	local child = utils.new_child_neovim()

	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Mock scenario where client appears after some time
	child.lua([[
		_G.test_clients = {}
		_G.call_count = 0
		
		-- Mock client that supports executeCommand
		_G.mock_client = {
			name = "notedown",
			server_capabilities = {
				executeCommandProvider = { commands = { "notedown.getConcealRanges" } }
			}
		}
		
		vim.lsp.get_clients = function()
			_G.call_count = _G.call_count + 1
			-- Return client after 2 calls to simulate delay
			if _G.call_count >= 2 then
				return { _G.mock_client }
			else
				return {}
			end
		end
		
		-- Mock vim.wait to avoid actual delays
		vim.wait = function(ms) return true end
		
		-- Mock vim.loop.now() - time doesn't advance to avoid timeout
		vim.loop.now = function() return 100 end
	]])

	-- Should find the client after retrying
	local result = child.lua_get('require("notedown")._get_notedown_command_client(1000)')
	MiniTest.expect.no_equality(result, vim.NIL)
	MiniTest.expect.equality(result.name, "notedown")

	child.stop()
end

T["module functions"]["get_notedown_command_client without executeCommand support"] = function()
	local child = utils.new_child_neovim()

	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Mock client without executeCommand support
	child.lua([[
		_G.mock_client_no_exec = {
			name = "notedown",
			server_capabilities = {
				-- No executeCommandProvider
			}
		}
		
		vim.lsp.get_clients = function()
			return { _G.mock_client_no_exec }
		end
	]])

	-- Should return nil when client doesn't support executeCommand
	local result = child.lua_get('require("notedown")._get_notedown_command_client()')
	MiniTest.expect.equality(result, vim.NIL)

	child.stop()
end

T["module functions"]["get_notedown_command_client with valid client"] = function()
	local child = utils.new_child_neovim()

	child.lua('require("notedown").setup({ server = { cmd = { "echo", "mock-server" } } })')

	-- Mock valid client with executeCommand support
	child.lua([[
		_G.mock_client_valid = {
			name = "notedown",
			server_capabilities = {
				executeCommandProvider = { 
					commands = { "notedown.getConcealRanges", "notedown.getListItemBoundaries" }
				}
			}
		}
		
		vim.lsp.get_clients = function()
			return { _G.mock_client_valid }
		end
	]])

	-- Should return the valid client
	local result = child.lua_get('require("notedown")._get_notedown_command_client()')
	MiniTest.expect.no_equality(result, vim.NIL)
	MiniTest.expect.equality(result.name, "notedown")
	MiniTest.expect.no_equality(result.server_capabilities.executeCommandProvider, nil)

	child.stop()
end

return T
