# Tailnet Presence Design

## Goal

Provide an installable Omarchy bar plugin that shows every machine in a
Tailscale tailnet and communicates its current connection state with a green
or red machine icon.

## Repository and distribution

The public repository is named `omarchy-tailnet-presence`. It exposes one
Omarchy bar-widget plugin with the ID `cylon58.tailnet-presence` and the
display name `Tailnet Presence`. Its manifest declares `clonedFrom:
omarchy.tailscale`, so it replaces the built-in Tailscale widget without a
bar-layout change. The repository is MIT licensed and retains attribution to
Omarchy's MIT-licensed Tailscale panel, from which its self-contained panel
implementation is derived.

Users install it with:

```bash
omarchy plugin add https://github.com/cylon58/omarchy-tailnet-presence.git
```

It requires Omarchy, Quickshell, and a working `tailscale` CLI. It does not
modify files under `/usr/share/omarchy`.

## Runtime behavior

The plugin runs `tailscale status --json` using the same refresh cadence as
Omarchy's built-in Tailscale panel, with a configurable interval that defaults
to 30 seconds. It preserves every peer received from Tailscale, including
offline peers. The panel renders each peer's operating-system glyph `#76c893`
green when `Online` is `true` and the active Omarchy theme's urgent red when
`Online` is `false`. Names and address text use the active Omarchy theme
foreground and muted colors.

The existing panel controls remain: Tailscale on/off, account switching, exit
node selection, peer address copying, and Taildrop where available.

## Structure

The repository root contains `manifest.json` and the complete QML panel,
adjacent JavaScript model, service, and icon so `omarchy plugin add` can
discover it directly. `tests/` contains Node-based tests for the status model.
The status model is the boundary between Tailscale JSON and the QML
view: it must return all non-Mullvad peers, each with a boolean `Online` field
and a `presence` field (`online` or `offline`), sorted by hostname.

## Validation

The test fixture includes one online and one offline peer. Tests prove both
peers reach the normalized model and retain their separate connection states.
The QML panel is syntax-checked, then installed into the user's Omarchy plugin
directory and rescanned for a live integration check. The public repository
includes installation and update instructions.
