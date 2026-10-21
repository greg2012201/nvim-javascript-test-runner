# JavaScript Test Runner

A Neovim plugin for running tests from JavaScript and TypeScript projects.

## Requirements

- Neovim 0.9 or newer
- Node.js
- A JavaScript or TypeScript project with a `package.json`
- Jest installed in the project, or available through `npx`

## Installation

### Local checkout

For a private repository or local development checkout, point `lazy.nvim`
directly at the repository:

```lua
{
  dir = vim.fn.expand("~/src/javascript-test-runner"),
  name = "javascript-test-runner",
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

Update the `dir` value to the location of your checkout.

### Private Git repository

If the repository is hosted privately on GitHub and your SSH key has access,
use its SSH clone URL:

```lua
{
  "git@github.com:OWNER/javascript-test-runner.git",
  name = "javascript-test-runner",
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

Replace `OWNER` with the GitHub account or organization that owns the
repository. Verify access outside Neovim with:

```bash
ssh -T git@github.com
```

## Usage

The current Jest backend provides these commands:

```text
:Test file
:Test folder
:Test project
:Test line
```

Default keymaps:

| Keymap       | Action                           |
| ------------ | -------------------------------- |
| `<Leader>tf` | Run tests for the current file   |
| `<Leader>tl` | Run the test on the current line |

The line mode recognizes calls such as `test("name")`, `it("name")`, and
`describe("name")`.

The plugin searches upward from the current buffer for the nearest
`package.json`, detects Jest or Vitest, and selects npm or pnpm for fallback
execution when a local test runner is unavailable.

## Configuration

The command name and default keymaps can be changed:

```lua
{
  dir = vim.fn.expand("~/src/javascript-test-runner"),
  name = "javascript-test-runner",
  opts = {
    command_name = "Test",
    keymaps = {
      file = "<Leader>tf",
      line = "<Leader>tl",
    },
    dap = false,
  },
  config = function(_, opts)
    require("javascript-test-runner").setup(opts)
  end,
}
```

Set either keymap to `false` to disable it.

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

For Jest, ESM is detected from a package's `"type": "module"` or test files
with `.mjs`/`.mts` extensions in the selected scope. Folder and project runs
also check nested package scopes. The runner adds `--experimental-vm-modules`
to the Jest process's `NODE_OPTIONS` when needed, preserving inherited and
configured options. This enables Jest's ESM runtime; it does not configure
transforms or other Jest settings required by some TypeScript, JSX, or
mixed-module projects. Vitest does not receive this Jest-specific option.

## Current scope

The plugin provides Jest and Vitest terminal runners for file, folder, project,
and current-line test execution. The backends are kept separate so additional
JavaScript test frameworks can be added later.

## Testing

The test suite uses `mini.test` and runs in headless Neovim. Testing requires
Neovim 0.10 or newer and Git; the Makefile fetches `mini.nvim` into
`deps/mini.nvim` on the first run. Run `make test` for the full suite, or
`make test-file FILE=tests/test_setup.lua` to run a single test file.
Use `NVIM_BIN=/path/to/nvim make test` to select a specific Neovim binary.
