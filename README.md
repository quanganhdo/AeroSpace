# AeroSpace Cotton [![Build](https://github.com/quanganhdo/AeroSpace/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/quanganhdo/AeroSpace/actions/workflows/build.yml)

<img src="./resources/Assets.xcassets/AppIcon.appiconset/icon.png" width="40%" align="right">

AeroSpace Cotton is a personal fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace),
an i3-like tiling window manager for macOS. It follows upstream development and adds
Dwindle layouts, workspace layout controls in the menu bar, and in-app updates through Sparkle.

Current source and future releases target **Apple Silicon (`arm64`) on macOS 13 or later**.
[v0.21.3-Beta-cotton.7](https://github.com/quanganhdo/AeroSpace/releases/tag/v0.21.3-Beta-cotton.7)
is the final universal release for both Apple Silicon and Intel Macs.

## What this fork adds

- **Dwindle layout:** automatically create nested splits around the most recently focused
  tiling branch, alternating the split direction. Inserting a window preserves the size
  of unaffected branches.
- **Workspace layout controls:** choose Tiles, Accordion, or Dwindle for each workspace
  from the AeroSpace menu bar.
- **Sparkle updates:** check for new Cotton releases from **Check for Updates…** in the
  menu bar. Update archives are signed, and future arm64 updates are restricted to
  compatible Macs.
- **Signed and notarized releases:** the release workflow signs apps with an Apple
  Developer ID, notarizes them with Apple, and staples the notarization ticket before distribution.
- **Bundled CLI resources:** the app includes the `aerospace` CLI, manpages, and shell
  completions for zsh, bash, and fish. The Homebrew cask exposes these resources.

The fork retains AeroSpace's keyboard-driven workflow, tree-based tiling, fast virtual
workspace switching, multi-monitor support, plain-text configuration, and CLI commands.
It does not require disabling System Integrity Protection (SIP).

## Installation

### Homebrew

Install the Cotton fork from its own tap:

```bash
brew install --cask quanganhdo/tap/aerospace
```

If you already have another AeroSpace cask installed, uninstall that cask before
installing this one. Both distributions use the same app and CLI names.

Launch **AeroSpace** from Applications, then grant it permission in
**System Settings → Privacy & Security → Accessibility** when prompted.
For multiple monitors, follow the upstream guide on
[monitor arrangement](https://nikitabobko.github.io/AeroSpace/guide#proper-monitor-arrangement).

Homebrew installs the app, CLI, manpages, and shell completions. Subsequent application
updates are available through Sparkle; choose **Check for Updates…** in the AeroSpace
menu. Homebrew can also upgrade the cask:

```bash
brew upgrade --cask quanganhdo/tap/aerospace
```

### Manual installation

1. Download `AeroSpace-v<VERSION>.zip` from this fork's
   [releases](https://github.com/quanganhdo/AeroSpace/releases).
2. Unzip it and move `AeroSpace.app` into `/Applications`.
3. To use the CLI, add the app's `Contents/Helpers` directory to your shell's `PATH`.
   For zsh or bash, add this line to your shell configuration:

   ```bash
   export PATH="/Applications/AeroSpace.app/Contents/Helpers:$PATH"
   ```

4. Launch the app and grant Accessibility permission.

The separate `bin/aerospace` executable is also included in the release archive.
Using the CLI bundled inside the app keeps it in sync with Sparkle app updates.
The `-sparkle.zip` asset is used by the updater; use the regular ZIP for manual installation.

### Intel Macs

Use [v0.21.3-Beta-cotton.7](https://github.com/quanganhdo/AeroSpace/releases/tag/v0.21.3-Beta-cotton.7)
for Intel Macs. New builds and future releases support Apple Silicon only.

## Configuration and Dwindle

Start with the [default configuration](./docs/config-examples/default-config.toml).
Save your configuration in either `~/.aerospace.toml` or
`~/.config/aerospace/aerospace.toml` (or `$XDG_CONFIG_HOME/aerospace/aerospace.toml`
if you set `XDG_CONFIG_HOME`). Use one location to avoid an ambiguous configuration.

To use Dwindle as the default root layout, set this top-level option:

```toml
default-root-container-layout = 'dwindle'
```

To switch an existing workspace to Dwindle, use its menu bar layout control or run:

```bash
aerospace layout --root dwindle
```

To target a specific workspace:

```bash
aerospace layout --workspace 1 --root dwindle
```

You can also add a binding to your existing `[mode.main.binding]` table:

```toml
alt-d = 'layout --root dwindle'
```

Reload after editing:

```bash
aerospace reload-config
```

## Documentation

The upstream documentation explains the shared configuration and commands.
Its installation instructions refer to upstream; use the Cotton installation steps above.
Dwindle and the Cotton update setup are described in this README.

- [AeroSpace Guide](https://nikitabobko.github.io/AeroSpace/guide)
- [AeroSpace Commands](https://nikitabobko.github.io/AeroSpace/commands)
- [AeroSpace Goodies](https://nikitabobko.github.io/AeroSpace/goodies)
- [Upstream 91-second demo](https://www.youtube.com/watch?v=UOl7ErqWbrk)
- [Video guide by Josean Martinez](https://www.youtube.com/watch?v=-FoWClVHG5g)

## Development and releases

See [development notes](./dev-docs/development.md) for dependencies, local builds,
tests, code signing, and the release workflow. The generated Xcode project is based
on [xcode/project.yml](./xcode/project.yml).

Cotton versions follow the upstream base version and append a fork revision, such as
`0.21.3-Beta-cotton.7`. The project remains in beta; configuration, commands, and
behavior may change as upstream development continues.

When reporting a problem, include the full Cotton version, macOS version, relevant
configuration, and steps to reproduce it. For window-handling problems, include
`aerospace debug-windows` output. Identify whether the problem also occurs in upstream
AeroSpace before reporting it to the
[upstream community](https://github.com/nikitabobko/AeroSpace/discussions).
The [contribution guide](./CONTRIBUTING.md) contains upstream contribution conventions.

## Credits and license

AeroSpace was created by [Nikita Bobko](https://github.com/nikitabobko) and is developed
by its [contributors](https://github.com/nikitabobko/AeroSpace/graphs/contributors).
This Cotton fork is maintained by [Quang Anh Do](https://github.com/quanganhdo).
You can [sponsor upstream AeroSpace](https://github.com/sponsors/nikitabobko).

AeroSpace is licensed under the [MIT license](./LICENSE.txt).
