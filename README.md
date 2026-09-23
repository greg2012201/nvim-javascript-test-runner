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
    require("jest-runner").setup(opts)
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
    require("jest-runner").setup(opts)
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
:Jest file
:Jest folder
:Jest project
:Jest line
```

Default keymaps:

| Keymap       | Action                           |
| ------------ | -------------------------------- |
| `<Leader>tf` | Run tests for the current file   |
| `<Leader>tl` | Run the test on the current line |

The line mode recognizes calls such as `test("name")`, `it("name")`, and
`describe("name")`.

The plugin searches upward from the current buffer for the nearest
`package.json`. It runs the project's local Jest installation when available
and falls back to `npx jest` otherwise.

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
  },
  config = function(_, opts)
    require("jest-runner").setup(opts)
  end,
}
```

Set either keymap to `false` to disable it.

## Current scope

The plugin currently provides a Jest-backed terminal runner for file, folder,
project, and current-line test execution. The backend is intentionally kept
separate so additional JavaScript test frameworks can be added later.
