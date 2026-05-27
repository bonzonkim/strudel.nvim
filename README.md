# strudel.nvim

A Neovim plugin for live coding with [Strudel](https://strudel.cc/), bringing the TidalCycles experience to your favorite editor.

## Demo


https://github.com/user-attachments/assets/86431c80-c05c-4d93-833d-c56ed92e7e2f

code source: (switch angel) https://www.youtube.com/shorts/AJ7atBkisOU 


## How it Works

This plugin enables a seamless "Neovim-only" live coding experience by bridging Neovim with a browser.

1.  **Neovim**: You write Strudel (JavaScript) code in Neovim.
2.  **OSC**: When you evaluate code, the plugin sends it via **OSC (Open Sound Control)** over UDP port `9129`.
3.  **Headless Bridge**: A Node.js script (managed by the plugin) runs a Chrome instance using Puppeteer.
    *   It loads the Strudel REPL.
    *   It listens for OSC messages and evaluates the code in the browser.
    *   It handles audio playback (bypassing autoplay restrictions).
    *   It captures browser console logs (e.g., note events) and streams them back to Neovim for text-based visualization.

## Features

| Feature | Status | Description |
| :--- | :---: | :--- |
| **Sound Synthesis** | ✅ | Full Strudel audio engine support via browser. |
| **Code Evaluation** | ✅ | Eval line, selection, or entire file (`:StrudelEvalFile`). |
| **Bridge Management** | ✅ | Start/Stop the audio engine directly from Neovim (`:StrudelStart`). |
| **Visuals** | ✅ | In-buffer per-note flash on the exact mini-notation token, distinct color per sound. Toggle: `:StrudelVisualToggle`. Browser window: `:StrudelShow`. |
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

## Visual Effects Configuration

When Strudel is playing, each mini-notation token in your buffer flashes the moment its sound triggers. Colors are assigned automatically per sound name; you can override:

```lua
require("strudel").setup({
  visual_effects = {
    enabled = true,  -- default
    colors = {
      bd = "#ff5555",   -- override auto-assigned color
      sd = "#55ff55",
    },
  }
})
```

Toggle at runtime with `:StrudelVisualToggle` or `<leader>sV`.

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
    *   Note: don't append `.play()` — current Strudel auto-plays evaluated patterns; `.play()` throws and leaves the previous (or default) pattern running.

3.  **Stop Sound**:
    *   Command: `:StrudelStop`
    *   Keybinding: `<leader>ss`

4.  **Visuals**:
    *   **Graphical**: `<leader>sv` (Show Window), `<leader>sh` (Hide Window)
    *   **Text**: Add `.log()` to your pattern (e.g., `s("bd").log()`) to see events in Neovim.

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
| `<leader>sV` | Toggle Visual Effects |
