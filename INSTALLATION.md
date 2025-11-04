# Installation Guide

## ⚡️ Requirements

- Neovim >= 0.10.0
- [notedown-language-server](https://github.com/notedownorg/language-server) (built and available in PATH)
- Neovim with LSP support (for folding support in notedown files)

## Installing the Plugin

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "notedownorg/notedown.nvim",
  opts = {
    -- Most users need no configuration!
    -- Just create a .notedown/ directory in your project root
  }
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "notedownorg/notedown.nvim",
  config = function()
    require("notedown").setup()
  end
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'notedownorg/notedown.nvim'

" Then in your init.lua or a lua file
lua require("notedown").setup()
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/notedownorg/notedown.nvim.git ~/.local/share/nvim/site/pack/plugins/start/notedown.nvim
   ```

2. Add to your `init.lua`:
   ```lua
   require("notedown").setup()
   ```

## Verification

After installation, verify the plugin is working:

1. Create a test workspace:
   ```bash
   mkdir -p ~/notedown-test/.notedown
   cd ~/notedown-test
   nvim test.md
   ```

2. Check workspace status:
   ```vim
   :NotedownWorkspaceStatus
   ```

3. Verify LSP is running:
   ```vim
   :LspInfo
   ```

You should see the notedown language server listed and active.

## Next Steps

- See [CONFIGURATION.md](CONFIGURATION.md) for configuration options
- See [USAGE.md](USAGE.md) for usage instructions and features
