# Test Data for Notedown Neovim Plugin

This directory contains test data files used by the Neovim plugin test suite.

## Directory Structure

```
tests/fixtures/testdata/list_text_object/
├── simple/              # Basic list structure tests
│   ├── input.md        # Simple list content
│   └── delete_third_item.md
├── nested/             # Deep nested list tests 
│   ├── input.md       # Complex nested content
│   └── delete_level4_with_children.md
├── multiline/          # Multi-line list item tests
│   └── input.md
└── tasks/             # Task list specific tests
    ├── input.md
    └── delete_incomplete_subtask.md
```

## Usage

These test data files are used by the list text object tests in `list_text_object_spec.lua`. The current testing approach uses simple assertion-based tests that create temporary workspaces for isolated testing.

### Running Tests

```bash
# Run all plugin tests (includes list text object tests)
cd neovim && nvim -l tests/minit.lua

# Run list text object tests specifically
cd neovim && nvim -l tests/list_text_object_spec.lua
```

## Test Categories

### Simple Tests
Basic list boundary detection with simple list structures.

### Nested Tests  
Complex deeply nested lists (up to 6 levels) for testing boundary detection accuracy.

### Task Tests
Task list specific functionality with checkbox preservation.

### Multiline Tests
Testing list items that span multiple lines.