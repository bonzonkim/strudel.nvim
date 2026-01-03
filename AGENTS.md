This project is dependent on Strudel(https://strudel.cc/learn) read the docs first


# Strudel.nvim Development Guide

## Commands
- **Install Bridge Dependencies**: `cd osc-bridge && npm install`
- **Run Plugin**: `make run` (Starts Neovim with the plugin loaded)
- **Verify OSC**: `nvim -l verify_osc.lua` (Starts a UDP listener to test OSC messages)
- **Strudel Commands**:
  - `:StrudelStart` - Start the headless bridge (Chrome)
  - `:StrudelHydra` - Initialize Hydra visual synthesizer
  - `:StrudelVisuals` - Toggle ASCII visualizer in a split
  - `:StrudelEval` (`<leader>se`) - Evaluate line/selection
  - `:StrudelStop` (`<leader>ss`) - Stop sound

## Knowledge Base
- **Strudel API**: Refer to `dict/docs_raw.md` for a comprehensive list of functions (factories, modifiers, synths).
- **Hydra**: The bridge supports basic Hydra visuals.
  - Init: `initHydra()` (handled by `:StrudelHydra`)
  - Usage: `osc(10).out()` (Standard Hydra syntax)
  - Visuals are rendered as ASCII in Neovim via `:StrudelVisuals`.

## Code Style & Conventions
- **Lua**:
  - **Indent**: 2 spaces.
  - **Naming**: `snake_case` for variables and functions.
  - **Modules**: Use standard `local M = {} ... return M` pattern.
  - **Imports**: `require` at the top of the file.
  - **Neovim API**: Prefer `vim.api` over `vim.cmd` for programmatic operations.
  - **Error Handling**: Use `pcall` for optional dependencies (e.g., `cmp`).
- **JavaScript (OSC Bridge)**:
  - **Indent**: 2 spaces.
  - **Environment**: Node.js (Puppeteer).
- **General**:
  - Keep functions focused and small.
  - Add descriptive comments for complex logic (e.g., OSC packet parsing).

---

## What I want to make
- **sturdel(https://strudel.cc) integrated nvim plugin**
- Full Strudel live coding experience in Neovim
- Implement visual feedback when playing notes
