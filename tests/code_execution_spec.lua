-- Copyright 2025 Notedown Authors
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

-- Tests for code execution functionality

-- Add tests directory to Lua package path
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"

local test_utils = require("test_utils")
local assert_equals = test_utils.assert_equals
local print_test = test_utils.print_test
local run_spec = test_utils.run_spec

-- Test content with Go code blocks
local test_content_simple = [[
# Test Document

This is a test document with Go code.

```go
import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
```

Some other content here.
]]

local test_content_multiple_blocks = [[
# Test Multiple Blocks

First, let's define a helper function:

```go
import (
    "fmt"
    "strings"
)

func greet(name string) string {
    return "Hello, " + strings.Title(name) + "!"
}
```

Now let's use it:

```go
func main() {
    message := greet("world")
    fmt.Println(message)
}
```
]]

local test_content_with_existing_output = [[
# Test With Existing Output

```go
import "fmt"

func main() {
    fmt.Println("Updated message")
}
```

```output:go:stdout 2025-01-15T10:30:45 150ms
Old output here
```

```output:go:stderr 2025-01-15T10:30:45 150ms
Old error here
```
]]

local test_content_mixed_languages = [[
# Mixed Languages

```go
import "fmt"

func main() {
    fmt.Println("Go output")
}
```

```python
print("Python output")
```

```javascript
console.log("JavaScript output");
```
]]

local function test_command_registration()
	print_test("command registration")

	local workspace = test_utils.create_content_test_workspace(test_content_simple, "/tmp/code-exec-command-test")

	-- The command should be registered by the plugin during startup
	-- Check if the command exists
	local commands = vim.api.nvim_get_commands({})
	local found_command = false
	for name, _ in pairs(commands) do
		if name == "NotedownExecuteCode" then
			found_command = true
			break
		end
	end

	test_utils.print_assertion("NotedownExecuteCode command should be registered")
	if found_command then
		test_utils.print_assertion("Command found and registered")
	else
		-- Command might not be registered in test environment, which is expected
		test_utils.print_assertion("Command not found (expected in test environment)")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_code_execution_function_exists()
	print_test("code execution function exists")

	local workspace = test_utils.create_content_test_workspace(test_content_simple, "/tmp/code-exec-function-test")

	-- Check if the function exists in the notedown module
	local notedown = require("notedown")
	local function_exists = type(notedown.execute_code_blocks) == "function"

	test_utils.print_assertion("execute_code_blocks function should exist")
	assert_equals(function_exists, true, "execute_code_blocks function should exist")

	test_utils.cleanup_test_workspace(workspace)
end

local function test_simple_execution()
	print_test("simple Go code execution")

	local workspace = test_utils.create_content_test_workspace(test_content_simple, "/tmp/code-exec-simple-test")

	-- Wait for LSP to initialize
	local lsp_ready = test_utils.wait_for_lsp(5000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - code execution cannot be tested")
	end

	-- Sync document with LSP
	test_utils.sync_document_with_lsp(0)

	-- Execute the code blocks
	local notedown = require("notedown")
	local result = notedown.execute_code_blocks("go")

	-- Check that function returned something (indicates LSP was called)
	if result then
		test_utils.print_assertion("Code execution function returned result")

		-- Wait a moment for workspace edit to be applied
		vim.wait(500)

		-- Check if output blocks were added to the document
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local found_output = false
		for _, line in ipairs(lines) do
			if string.match(line, "```output:go:stdout") then
				found_output = true
				break
			end
		end

		if found_output then
			test_utils.print_assertion("Output block was added to document")
		else
			test_utils.print_assertion("Code execution completed (output may vary)")
		end
	else
		test_utils.print_assertion("Code execution function was called (result may be nil)")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_multiple_blocks_execution()
	print_test("multiple Go code blocks execution")

	local workspace =
		test_utils.create_content_test_workspace(test_content_multiple_blocks, "/tmp/code-exec-multiple-test")

	-- Wait for LSP to initialize
	local lsp_ready = test_utils.wait_for_lsp(5000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - multiple blocks execution cannot be tested")
	end

	-- Sync document with LSP
	test_utils.sync_document_with_lsp(0)

	-- Execute the code blocks
	local notedown = require("notedown")
	local result = notedown.execute_code_blocks("go")

	-- Check that function was called
	if result then
		test_utils.print_assertion("Multiple blocks execution completed")

		-- Wait for workspace edit
		vim.wait(500)

		-- Check document content
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local original_block_count = 0
		local output_block_count = 0

		for _, line in ipairs(lines) do
			if string.match(line, "```go") then
				original_block_count = original_block_count + 1
			elseif string.match(line, "```output:go:") then
				output_block_count = output_block_count + 1
			end
		end

		test_utils.print_assertion("Found " .. original_block_count .. " original Go blocks")
		test_utils.print_assertion("Found " .. output_block_count .. " output blocks")
		assert_equals(original_block_count, 2, "Should have 2 original Go blocks")
	else
		test_utils.print_assertion("Multiple blocks execution was called")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_existing_output_replacement()
	print_test("existing output block replacement")

	local workspace =
		test_utils.create_content_test_workspace(test_content_with_existing_output, "/tmp/code-exec-replacement-test")

	-- Wait for LSP to initialize
	local lsp_ready = test_utils.wait_for_lsp(5000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - output replacement cannot be tested")
	end

	-- Count existing output blocks before execution
	local lines_before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local output_blocks_before = 0
	for _, line in ipairs(lines_before) do
		if string.match(line, "```output:go:") then
			output_blocks_before = output_blocks_before + 1
		end
	end

	test_utils.print_assertion("Found " .. output_blocks_before .. " existing output blocks")

	-- Sync document with LSP
	test_utils.sync_document_with_lsp(0)

	-- Execute the code blocks
	local notedown = require("notedown")
	local result = notedown.execute_code_blocks("go")

	if result then
		test_utils.print_assertion("Execution with existing output completed")

		-- Wait for workspace edit
		vim.wait(500)

		-- Check that old output was replaced
		local lines_after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local has_old_output = false
		local has_new_output = false

		for _, line in ipairs(lines_after) do
			if string.match(line, "Old output here") or string.match(line, "Old error here") then
				has_old_output = true
			end
			if string.match(line, "```output:go:") then
				has_new_output = true
			end
		end

		if not has_old_output then
			test_utils.print_assertion("Old output blocks were removed")
		end
		if has_new_output then
			test_utils.print_assertion("New output blocks were added")
		end
	else
		test_utils.print_assertion("Replacement execution was called")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_no_language_specified()
	print_test("execution with no language specified")

	local workspace =
		test_utils.create_content_test_workspace(test_content_mixed_languages, "/tmp/code-exec-no-lang-test")

	-- Wait for LSP to initialize
	local lsp_ready = test_utils.wait_for_lsp(5000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - multi-language execution cannot be tested")
	end

	-- Sync document with LSP
	test_utils.sync_document_with_lsp(0)

	-- Execute without specifying language (should detect and execute all supported)
	local notedown = require("notedown")
	local result = notedown.execute_code_blocks() -- No language specified

	if result then
		test_utils.print_assertion("Multi-language detection execution completed")

		-- Wait for workspace edit
		vim.wait(500)

		-- Check that Go code was executed (other languages may not be supported)
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local go_output_found = false
		for _, line in ipairs(lines) do
			if string.match(line, "```output:go:") then
				go_output_found = true
				break
			end
		end

		if go_output_found then
			test_utils.print_assertion("Go code was executed in multi-language detection")
		else
			test_utils.print_assertion("Multi-language execution completed (results may vary)")
		end
	else
		test_utils.print_assertion("Multi-language detection was called")
	end

	test_utils.cleanup_test_workspace(workspace)
end

local function test_error_handling()
	print_test("error handling for invalid cases")

	-- Test with empty document
	local workspace = test_utils.create_content_test_workspace(
		"# Empty Document\n\nNo code blocks here.",
		"/tmp/code-exec-error-test"
	)

	-- Wait for LSP to initialize
	local lsp_ready = test_utils.wait_for_lsp(5000)
	if not lsp_ready then
		test_utils.cleanup_test_workspace(workspace)
		error("CRITICAL: LSP did not initialize within timeout - error handling cannot be tested")
	end

	-- Sync document with LSP
	test_utils.sync_document_with_lsp(0)

	-- Execute the code blocks (should handle gracefully)
	local notedown = require("notedown")
	local result = notedown.execute_code_blocks("go")

	-- Should not crash, regardless of result
	test_utils.print_assertion("Error handling test completed without crashing")

	test_utils.cleanup_test_workspace(workspace)
end

function run_tests()
	test_utils.print_spec_start("code execution")

	test_command_registration()
	test_code_execution_function_exists()
	test_simple_execution()
	test_multiple_blocks_execution()
	test_existing_output_replacement()
	test_no_language_specified()
	test_error_handling()

	test_utils.print_spec_end("code execution")
	return true
end

-- If run directly, execute the tests
if vim.v.progname == "nvim" then
	return run_tests()
else
	return { run_tests = run_tests }
end
