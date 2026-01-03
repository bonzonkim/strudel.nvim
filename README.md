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
| **Visual Feedback** | ✅ | Flash effects on eval, ASCII visualizer window (`:StrudelVisuals`). |
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

## Usage

1.  **Start the Bridge**:
    *   Command: `:StrudelStart`
    *   Keybinding: `<leader>sS`
    *   Wait for the message "Strudel Bridge started!".

2.  **Play Sound**:
    *   Write some code: `note("c3").play()`
    *   Evaluate File: `<leader>sf` (or `:StrudelEvalFile`)
    *   Evaluate Line: `<leader>se` (or `:StrudelEval`)

3.  **Stop Sound**:
    *   Command: `:StrudelStop`
    *   Keybinding: `<leader>ss`

4.  **Visual Feedback**:
    *   **Flash Effect**: Code lines flash gold when evaluated (automatic)
    *   **ASCII Visualizer**: `<leader>sv` or `:StrudelVisuals` (toggle animated waveform display)
    *   **Browser Visuals**: `:StrudelShow` / `:StrudelHide` for scopes and piano rolls

## Keybindings

| Key | Action |
| :--- | :--- |
| `<leader>sS` | Start Bridge |
| `<leader>sq` | Stop Bridge |
| `<leader>sf` | Evaluate File |
| `<leader>se` | Evaluate Line / Selection |
| `<leader>ss` | Stop Sound (Hush) |
| `<leader>sv` | Toggle ASCII Visualizer |
| `<leader>sh` | Hide Browser Window |

## Visual Feedback

The plugin provides native visual feedback in Neovim:

### Flash Effect
When you evaluate code (`<leader>se`), the line or selection flashes with a gold highlight that fades out smoothly. This gives immediate visual confirmation that code was sent to Strudel.

### ASCII Visualizer
Toggle an animated ASCII waveform display with `:StrudelVisuals`:

```
  ╭─────────────────────────────────────────────────────╮
  │  ♪ STRUDEL VISUALIZER                               │
  ├─────────────────────────────────────────────────────┤
  │  Waveform:                                          │
  │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█              │
  │  Beat Pattern:                                      │
  │  █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░       │
  ╰─────────────────────────────────────────────────────╯
```

