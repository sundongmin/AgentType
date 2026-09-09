# AgentType

**Automatic input-source switching between your shell and AI agents.**

[简体中文](README.md) · [Installation guide (Chinese)](docs/INSTALL.md) · [Contributing](CONTRIBUTING.md)

AgentType switches to an English input source in a regular Ghostty shell and to a Chinese input method while running `claude`, `codex`, or `pi`. State belongs to the originating terminal, so each Ghostty tab or split follows its own rule.

This preview supports **macOS, Ghostty, and local interactive zsh**. Hammerspoon provides the runtime. AgentType is an independent community project, not an official product of Ghostty, Hammerspoon, or any agent vendor.

## Install

Enable ABC and a Chinese input source in macOS settings. Use a Ghostty version that supports AppleScript terminal IDs, TTYs, and focused terminals. Download the repository source or the full release archive, then run from its root:

```sh
/bin/zsh ./install.sh --dry-run
/bin/zsh ./install.sh
```

The installer currently displays Chinese prompts. Choose a numbered input method, or enter `q` to cancel. It lists enabled, selectable Chinese input sources and does not choose one automatically.

If Hammerspoon is missing, the installer uses Homebrew when available; otherwise it downloads the official stable GitHub release and verifies its SHA-256 and developer signature. It does not install Homebrew. Dry runs never download or install dependencies.

After installation, open Hammerspoon, or reload its configuration if already running. Grant the requested macOS permissions, exit active agents, and open a new Ghostty terminal:

```sh
ghostty-im doctor
```

Exclude Ghostty from other input-source managers such as KeyboardHolder. Existing legacy scripts must be removed before installation; see the [migration guide](docs/INSTALL.md#从旧版脚本迁移).

## Configure and uninstall

Settings are stored in `~/.hammerspoon/GhosttyInputMethod/config.lua`. The default poll interval is **0.15 seconds**, and external queries run only while Ghostty is frontmost. Successful automatic selection allows temporary manual changes until the next focus or terminal-state change.

```sh
# Unattended install: use an input source enabled on your Mac.
/bin/zsh ./install.sh --agent-source com.apple.inputmethod.SCIM.ITABC

# Removes managed integration; keeps Hammerspoon and unrelated configuration.
/bin/zsh ./uninstall.sh
```

Existing aliases and functions are preserved. Custom commands can opt in using `ghostty_im_run codex "$@"`. Direct calls such as `command codex` bypass the integration.

## Limitations

SSH and tmux sessions are skipped. Background agents, nested shells, suspension/resumption, and multiple agents in one terminal are not fully supported. Input-source selection does not guarantee an IME's internal language mode or composition state. Automated tests cover installation and state handling; real input behavior still requires manual verification.

For compatibility, the current adapter retains the names `GhosttyInputMethod.spoon`, `ghostty-im`, and its existing settings paths.

## Development and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and builds. Contributions and issue reports in English or Chinese are welcome. Licensed under [MIT](LICENSE). Third-party applications and input methods are not bundled.
