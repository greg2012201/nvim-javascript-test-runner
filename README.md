# JavaScript Test Runner

A batteries-included, zero-configuration test runner for JavaScript development
in Neovim. It detects Node.js projects and their npm or pnpm setup, and
automatically uses the Node.js version configured for each project. Run Jest
or Vitest tests for the current file, its folder, the project, or the test on
the current line. Optional `nvim-dap` integration lets you debug supported
test runs.

## Features

- Run Jest or Vitest tests by file, folder, project, or current line.
- Detect the nearest `package.json`, test framework, and npm or pnpm setup.
- Use a local test runner when available, with npm or pnpm execution as a
  fallback.
- Optionally register Jest and Vitest debug configurations with `nvim-dap`.

## Requirements

- Neovim 0.9 or newer
- Node.js, available on your `PATH` or managed with `nvm`, `fnm`, `mise`,
  `asdf`, or Volta
- A JavaScript or TypeScript project with a `package.json`
- Jest or Vitest installed in the project, or available through npm or pnpm

## Installation

Add the plugin to your [lazy.nvim](https://github.com/folke/lazy.nvim) plugin
specs:

```lua
{
  "greg2012201/nvim-javascript-test-runner",
  ft = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  opts = {},
  config = function(_, opts)
    require("javascript-test-runner").setup(opts)
  end,
}
```

Then run `:Lazy sync`.

The plugin also works with other Neovim plugin managers. Install the repository
with your manager and call `require("javascript-test-runner").setup()` from its
configuration hook.

## Usage

Run a command from a JavaScript or TypeScript project:

| Command         | Runs tests for               |
| --------------- | ---------------------------- |
| `:Test file`    | The current file             |
| `:Test folder`  | The current file's folder    |
| `:Test project` | The whole project            |
| `:Test line`    | The test on the current line |

The default keymaps are `<Leader>tf` for the current file and `<Leader>tl` for
the current line. Line mode recognizes calls such as `test("name")`,
`it("name")`, and `describe("name")`.

The plugin searches upward from the current buffer for the nearest
`package.json`, detects Jest or Vitest, and selects npm or pnpm for fallback
execution when a local test runner is unavailable.

## Configuration

Configure the command name and keymaps with `setup`:

```lua
require("javascript-test-runner").setup({
  command_name = "Test",
  keymaps = {
    file = "<Leader>tf",
    line = "<Leader>tl",
  },
})
```

Set either keymap to `false` to disable it.

### Project overrides

Automatic project detection is used unless you configure project-specific
overrides. Override keys are project roots; in a monorepo, the workspace root
is used when it has a `workspaces` field or a `pnpm-workspace.yaml` file.

```lua
require("javascript-test-runner").setup({
  project_overrides = {
    ["/path/to/monorepo"] = {
      node_version = "22",
      package_manager = "pnpm",
      framework = "jest",
      env = {
        NODE_OPTIONS = "--experimental-vm-modules",
      },
    },
  },
})
```

`package_manager` accepts `npm` or `pnpm`, and `framework` accepts `jest` or
`vitest`. `node_version` selects a version understood by an installed `nvm`,
`fnm`, `mise`, `asdf`, or Volta manager; if an explicit version cannot be
resolved, the runner reports an error rather than silently using system Node.
Values in `env` are passed only to the test process and do not change Neovim's
environment. Without a workspace marker, overrides use the nearest
`package.json` project root.

### Running tests with nvim-dap

Set `dap = true` to register file, folder, and line configurations with
`nvim-dap`:

```lua
require("javascript-test-runner").setup({
  dap = true,
})
```

This requires `nvim-dap` and a supported `pwa-node` adapter. Jest or Vitest
must be installed locally in the project for debugging. The plugin's debug
terminals follow their output; unrelated DAP sessions and terminals are
unchanged.

## Testing

The test suite uses `mini.test` and runs in headless Neovim. Testing requires
Neovim 0.10 or newer and Git; the Makefile fetches `mini.nvim` into
`deps/mini.nvim` on the first run. Run `make test` for the full suite, or
`make test-file FILE=tests/test_setup.lua` to run a single test file.
Use `NVIM_BIN=/path/to/nvim make test` to select a specific Neovim binary.
