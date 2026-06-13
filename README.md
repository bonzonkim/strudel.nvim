# strudel.nvim

A Neovim plugin for live coding with [Strudel](https://strudel.cc/), bringing the TidalCycles experience to your favorite editor.

## Demo


https://github.com/user-attachments/assets/a95e018b-d354-4c08-b9e0-b7bcca437ef5


## How it Works

This plugin enables a seamless "Neovim-only" live coding experience by bridging Neovim with a browser.

1.  **Neovim**: You write Strudel (JavaScript) code in Neovim.
2.  **OSC**: When you evaluate code, the plugin sends it via **OSC (Open Sound Control)** over UDP port `9129`.
3.  **Headless Bridge**: A Node.js script (managed by the plugin) runs a Chrome instance using Puppeteer.
    *   It loads the Strudel REPL.
    *   It listens for OSC messages and evaluates the code in the browser.
    *   It handles audio playback (bypassing autoplay restrictions).
    *   It installs an `onTrigger` hook on the Strudel scheduler that streams per-hap events (sound name + source location + duration) back to Neovim, which renders them as in-buffer highlights on the exact mini-notation tokens.

## Features

| Feature | Status | Description |
| :--- | :---: | :--- |
| **Sound Synthesis** | ✅ | Full Strudel audio engine support via browser. |
| **Code Evaluation** | ✅ | Eval line, selection, or entire file (`:StrudelEvalFile`). |
| **Bridge Management** | ✅ | Start/Stop the audio engine directly from Neovim (`:StrudelStart`). |
| **Visuals** | ✅ | In-buffer per-note flash on the exact mini-notation token, distinct color per sound. Browser window: `:StrudelShow` / `:StrudelHide`. |
| **Autocomplete** | ✅ | Native `nvim-cmp` source + Dictionary support. |
| **Syntax Highlighting** | 🚧 | Uses standard JavaScript syntax highlighting. |

## Installation

### Prerequisites
*   **Node.js** (v16+ recommended)
*   **npm** (to install Puppeteer)

### lazy.nvim

```lua
{
  "bonzonkim/strudel.nvim",
  build = "npm install --prefix osc-bridge", -- Installs dependencies automatically
  config = function()
    require("strudel").setup()
  end
}
```

### packer.nvim

```lua
use {
  "bonzonkim/strudel.nvim",
  run = "npm install --prefix osc-bridge",
  config = function()
    require("strudel").setup()
  end
}
```

### nvim-cmp Setup

The plugin attempts to automatically register the `strudel` completion source.
Add it to your `nvim-cmp` configuration:

```lua
local cmp = require("cmp")
cmp.setup({
  sources = {
    { name = "strudel" },
    -- other sources...
  }
})
```

**Troubleshooting:**
If autocompletion doesn't work (e.g., due to lazy loading order), you can manually register the source in your config:

```lua
-- After cmp setup
require("cmp").register_source("strudel", require("strudel.cmp").new())
```

Completion data is loaded from the bundled `dict/strudel_completions.json` catalog, so runtime completion works offline and does not require the upstream Strudel repository. The catalog mirrors upstream reference metadata for function names, documented aliases, parameters, and examples; `dict/strudel.dict` remains available as a Vim keyword-completion fallback.

The source is active for Strudel-oriented buffers (`javascript`, `javascriptreact`, `typescript`, `typescriptreact`, `strudel`) and returns documented aliases as their own selectable entries. Inside sound string arguments such as `s("...")` and `sound("...")`, catalog entries marked as sounds are suggested when available; outside those contexts the source falls back to Strudel function completions.

Maintainers can refresh the catalog from a local Strudel checkout:

```bash
# In the upstream Strudel checkout first:
cd /path/to/strudel
pnpm i
npm run jsdoc-json

# Then in strudel.nvim:
node dict/generate_completions.js --strudel-repo /path/to/strudel
node tests/generate_completions_spec.js
make test
```

Manual acceptance check:

1. Run `:StrudelDebug` and confirm the completion catalog path, load status, and entry count are printed.
2. In a JavaScript Strudel buffer, trigger completion for a canonical function prefix and an alias prefix.
3. Inspect a completion detail window and confirm description, aliases, parameters, or examples appear when available.
4. In an unrelated filetype buffer, confirm the `strudel` source is not active unless you manually opt into it in your completion setup.

## Visual Effects Configuration

When Strudel is playing, each mini-notation token in your buffer flashes the moment its sound triggers. Colors are assigned automatically per sound name (deterministic FNV-1a hash → HSL hue); override per-sound if you want specific colors:

```lua
require("strudel").setup({
  visual_effects = {
    enabled = true,  -- default; set false to suppress all highlights
    colors = {
      bd = "#ff5555",   -- override auto-assigned color
      sd = "#55ff55",
    },
  }
})
```

### Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). With plenary installed via your plugin manager, run:

```bash
make test
```

## Usage

1.  **Start the Bridge**:
    *   Command: `:StrudelStart`
    *   Keybinding: `<leader>sS`
    *   Wait for the message "Strudel Bridge started!".

2.  **Play Sound**:
    *   Write some code: `note("c3")` or `s("bd sd hh cp")`
    *   Evaluate File: `<leader>sf` (or `:StrudelEvalFile`)
    *   Evaluate Line: `<leader>se` (or `:StrudelEval`)
    *   Note: don't append `.play()`. Current Strudel auto-plays evaluated patterns; `.play()` throws inside the browser, so the eval is rejected and no highlights appear.

3.  **Stop Sound**:
    *   Command: `:StrudelStop`
    *   Keybinding: `<leader>ss`

4.  **Visuals**:
    *   **In-buffer**: highlights flash on each mini-notation token in beat with the audio. Automatic — no command needed. Configure colors via `setup({ visual_effects = ... })` (see below).
    *   **Browser window**: `<leader>sv` (Show), `<leader>sh` (Hide).
    *   **Text log**: add `.log()` to your pattern (e.g., `s("bd").log()`) to see events in Neovim's `:messages`.

## Keybindings

| Key | Action |
| :--- | :--- |
| `<leader>sS` | Start Bridge |
| `<leader>sq` | Stop Bridge |
| `<leader>sf` | Evaluate File |
| `<leader>se` | Evaluate Line / Selection |
| `<leader>ss` | Stop Sound (Hush) |
| `<leader>sv` | Show Browser Window |
| `<leader>sh` | Hide Browser Window |
