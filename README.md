# strudel.nvim

A Neovim plugin for live coding with [Strudel](https://strudel.cc/), bringing the TidalCycles experience to your favorite editor.

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
| **Visuals ** | 🚧 | Toggle the browser window to see scopes, piano rolls, etc. (`:StrudelShow`). |
| **Autocomplete** | 🚧 | Basic dictionary-based completion for Strudel functions. |
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

4.  **Visuals**:
    *   **Graphical**: `<leader>sv` (Show Window), `<leader>sh` (Hide Window)
    *   **Text**: Add `.log()` to your pattern (e.g., `s("bd").log().play()`) to see events in Neovim.

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
