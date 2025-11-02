# Configuration Guide

## Default Configuration

```lua
require("notedown").setup({
  server = {
    name = "notedown",
    cmd = { "notedown-language-server", "serve", "--log-level", "debug", "--log-file", "/tmp/notedown.log" },
    root_dir = function()
      return vim.fn.getcwd()
    end,
    capabilities = vim.lsp.protocol.make_client_capabilities(),
  },
  -- Most users need no additional configuration!
  -- The 'al' text object is automatically available
})
```

## Workspace Detection

**The plugin automatically detects Notedown workspaces** by looking for a `.notedown/` directory:

1. **Starting from the current file's directory**, the plugin walks up the directory tree
2. **First `.notedown/` directory found** marks the workspace root
3. **Files in detected workspaces** automatically use the notedown parser and LSP features
4. **Files outside workspaces** use standard markdown behavior

**No configuration required** - just create a `.notedown/` directory in your project root!

### Setting Up a Workspace

```bash
# Navigate to your project/notes directory
cd ~/my-notes

# Create .notedown directory to mark it as a workspace
mkdir .notedown

# Optional: Add workspace configuration
echo "tasks:" > .notedown/settings.yaml
echo "  states:" >> .notedown/settings.yaml
echo "    - value: ' '" >> .notedown/settings.yaml
echo "      name: todo" >> .notedown/settings.yaml
```

### Workspace Detection Examples

```
Project Structure:
├── my-notes/
│   ├── .notedown/           ← Workspace root detected here
│   ├── daily/
│   │   └── today.md         ← Opens as notedown
│   ├── projects/
│   │   └── work.md          ← Opens as notedown
│   └── README.md            ← Opens as notedown

├── other-project/
│   └── README.md            ← Opens as markdown (no .notedown)
```

## Advanced Configuration

### Custom LSP Server Command

```lua
require("notedown").setup({
  server = {
    cmd = { "/path/to/notedown-language-server", "serve", "--log-level", "info" },
    root_dir = function()
      -- Use git root or fallback to current directory
      return vim.fn.system("git rev-parse --show-toplevel"):gsub("\n", "") or vim.fn.getcwd()
    end,
  }
})
```

### Custom Capabilities

```lua
require("notedown").setup({
  server = {
    capabilities = vim.tbl_deep_extend(
      "force",
      vim.lsp.protocol.make_client_capabilities(),
      require("cmp_nvim_lsp").default_capabilities() -- if using nvim-cmp
    ),
  }
})
```

### Custom Root Directory Detection

By default, the plugin uses the directory containing the `.notedown/` folder as the workspace root. You can customize this:

```lua
require("notedown").setup({
  server = {
    root_dir = function()
      -- Use git root if available
      local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
      if vim.v.shell_error == 0 and git_root ~= "" then
        return git_root
      end
      -- Fall back to current working directory
      return vim.fn.getcwd()
    end,
  }
})
```

### Changing Log Level

Adjust LSP server logging for debugging:

```lua
require("notedown").setup({
  server = {
    cmd = {
      "notedown-language-server",
      "serve",
      "--log-level", "debug",  -- Options: debug, info, warn, error
      "--log-file", "/tmp/notedown.log"
    },
  }
})
```

Then check logs with:
```bash
tail -f /tmp/notedown.log
```
