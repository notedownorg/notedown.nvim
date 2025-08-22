# Test Data for Notedown Neovim Plugin

This directory contains golden files for testing the Notedown Neovim plugin functionality.

## Golden File Testing Approach

Golden file testing provides a clear, maintainable way to test complex text transformations by storing expected outputs as separate files. This approach offers several benefits:

### Benefits

- **👀 Visual Clarity**: Easy to see exactly what each operation should accomplish
- **🐛 Better Debugging**: When tests fail, you get a clear diff of expected vs actual
- **📝 Easy Maintenance**: Update expected outputs by regenerating golden files
- **🧪 Comprehensive Coverage**: Each test case has clear input and expected output

### Directory Structure

```
tests/testdata/list_movement/
├── simple/              # Basic list movement tests
│   ├── input.md        # Initial content for simple tests
│   ├── move_second_down.md
│   ├── move_third_up.md
│   ├── move_first_up_no_change.md
│   └── move_fourth_down_no_change.md
├── nested/             # Deep nested list tests (6 levels)
│   ├── input.md       # Complex nested content
│   ├── level1_move_b_up.md
│   ├── level2_move_a2_up.md
│   ├── level4_move_ii_up.md
│   ├── level5_move_beta_up.md
│   ├── mixed_list_renumber.md
│   └── boundary_level6_first_up_no_change.md
└── tasks/             # Task list specific tests
    ├── input.md
    └── move_subtask_a1b_up.md
```

### Usage

#### Running Tests
```bash
# Run all golden file tests
cd neovim && nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run_file('tests/test_list_movement_golden.lua')" -c "qall!"

# Run specific test pattern
cd neovim && nvim --headless --noplugin -u tests/helpers/minimal_init.lua -c "lua MiniTest.run_file('tests/test_list_movement_golden.lua', {filter = 'nested'})" -c "qall!"
```

#### Updating Golden Files
When the expected behavior changes, regenerate golden files:

```bash
UPDATE_GOLDEN=1 make test-nvim
```

#### Writing New Tests
1. Add input file to appropriate category directory
2. Create expected output file with descriptive name  
3. Add test case to `test_list_movement_golden.lua`:

```lua
T["category - descriptive test name"] = function()
    golden.test_list_movement("category", "expected_output_file", {
        search_pattern = "text to find for cursor positioning",
        command = "NotedownMoveUp"  -- or NotedownMoveDown
    })
end
```

### Test Categories

#### Simple Tests
Basic list movement operations with 4 items, testing:
- Moving items up/down
- Boundary conditions (first/last items)

#### Nested Tests  
Complex deeply nested lists (up to 6 levels) testing:
- Movement at different nesting levels
- Preservation of hierarchy structure
- Mixed list types (bullets, ordered, tasks)
- Automatic renumbering of ordered lists

#### Task Tests
Task list specific functionality testing:
- Checkbox preservation during movement
- Deep nesting with task items

### Comparison: Old vs New Approach

#### Old Approach (Inline Testing)
```lua
T["move second item down"] = function()
    local workspace_path, file_path = create_list_test_workspace()
    local child = utils.new_child_neovim()
    
    -- 50+ lines of setup, execution, and verification code
    -- Complex string parsing and position checking
    -- Hard to see what the expected result should be
    
    local final_lines = child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    if #final_lines >= 5 then
        local line4 = final_lines[4] or ""
        local line5 = final_lines[5] or ""
        MiniTest.expect.equality(string.find(line4, "Third item") ~= nil, true, "Line 4 should contain 'Third item'")
        MiniTest.expect.equality(string.find(line5, "Second item") ~= nil, true, "Line 5 should contain 'Second item'")
    end
    -- ... more complex verification logic
end
```

#### New Approach (Golden Files)
```lua
T["simple - move second item down"] = function()
    golden.test_list_movement("simple", "move_second_down", {
        search_pattern = "Second item",
        command = "NotedownMoveDown"
    })
end
```

**Input file** (`simple/input.md`):
```markdown
# Test List

- First item
- Second item  ← cursor positioned here
- Third item
- Fourth item
```

**Expected output** (`simple/move_second_down.md`):
```markdown
# Test List

- First item
- Third item
- Second item  ← moved down
- Fourth item
```

The golden file approach makes it immediately clear what the test is doing and what the expected result should be!