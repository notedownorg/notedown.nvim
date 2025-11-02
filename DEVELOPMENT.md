# Development Guide

## Development Commands

### Testing
- `make test` - Run all tests in Docker (recommended, matches CI environment)
- `make test-local` or `./scripts/test` - Run tests locally (requires Go toolchain to build LSP server)
- `nvim -l tests/minit.lua` - Direct test runner invocation
- `nvim -l tests/<spec_name>_spec.lua` - Run a single test spec file
- `make test-docker-shell` - Open interactive shell in test container for debugging

### Code Quality
- `make format` - Format Lua code with stylua and apply license headers
- `make hygiene` - Run all code quality checks (formatting + licensing)
- `make check` - Run hygiene checks, tests, and verify no uncommitted changes

### Docker Testing
- `make test-docker-build` - Build Docker test image with specific Neovim/LSP versions
- `NVIM_VERSION=v0.11.0 LSP_VERSION=v0.2.0 make test-docker` - Test with specific versions

### Nix Development
- `nix develop` - Enter Nix development shell (if Nix is installed, Makefile auto-detects)
- Development shell includes: Go, Git, licenser, stylua, and Neovim

## 🧪 Testing

The plugin includes a comprehensive test suite using a simplified testing approach inspired by folke/trouble.nvim.

### Running Tests

```bash
# Run all tests (builds LSP server and runs spec files)
nvim -l tests/minit.lua

# Alternative: use shell wrapper
./scripts/test

# Run specific spec file
nvim -l tests/wikilink_spec.lua
```

#### Docker Testing

For reproducible tests with controlled Neovim and LSP versions:

```bash
# Build and run tests in Docker (recommended for CI)
make test-docker

# Just build the Docker image
make test-docker-build

# Open a shell in the test container for debugging
make test-docker-shell
```

**Benefits:**
- Isolated environment with pinned Neovim v0.10.x
- Pre-built notedown-language-server from releases
- No local Go toolchain required
- Consistent results across different machines

**When to use:**
- CI/CD pipelines
- Verifying plugin works with specific Neovim versions
- Debugging environment-specific issues
- Testing without building LSP from source

### Test Structure

Tests are organized in simple `*_spec.lua` files in the `tests/` directory:

- `wikilink_spec.lua` - Wikilink navigation, completion, and concealment
- `folding_spec.lua` - LSP-based folding functionality
- `list_text_object_spec.lua` - List item boundary detection and text objects
- `config_spec.lua` - Configuration and workspace detection
- `task_completion_spec.lua` - Task completion features
- `task_diagnostics_spec.lua` - Task diagnostics and validation
- `workspace_spec.lua` - Workspace management functionality
- `init_spec.lua` - Plugin initialization

Each spec file:
- Has a `run_tests()` function that returns `true`/`false` for pass/fail
- Uses simple assertion functions instead of external test frameworks
- Creates temporary test workspaces for isolated testing
- Tests against real notedown-language-server for authentic behavior

### Test Runners

- **`minit.lua`**: Main test runner that builds the LSP binary and runs all spec files
- **`scripts/test`**: Shell script wrapper for easy execution

The testing approach prioritizes simplicity and reliability over complex frameworks.

#### Test Troubleshooting

If `make test-nvim` fails:

1. **Check Dependencies**:
   ```bash
   nvim --version  # Ensure Neovim is available
   go version      # Needed for LSP binary building
   ```

2. **Check Permissions**:
   ```bash
   # Make test script executable
   chmod +x scripts/test
   ```

3. **Debug Individual Tests**:
   ```bash
   # Run one spec file to isolate issues
   nvim -l tests/config_spec.lua
   ```

4. **Check Project Structure**:
   - Ensure you're running from the repository root directory
   - Verify language-server/ directory exists in project root

## 🤝 Contributing

Contributions are welcome! Please see the [main repository](https://github.com/notedownorg/notedown) for contribution guidelines.

### Adding Tests

When contributing new features:

1. Add test coverage in the appropriate `*_spec.lua` file
2. Follow the existing assertion pattern with clear error messages
3. Use temporary workspaces for test isolation
4. Test both positive and negative cases
5. Ensure tests clean up after themselves

For detailed patterns on adding tests and LSP commands, see [CLAUDE.md](CLAUDE.md#common-development-patterns).

### Code Quality

Before submitting changes:

```bash
# Format code and apply license headers
make format

# Run all checks
make check
```

All Lua files must have Apache 2.0 license headers. The `make format` command automatically applies them using the licenser tool.
