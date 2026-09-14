# Tailnet Presence

An [Omarchy](https://omarchy.org/) bar plugin for Tailscale. It lists every
machine in the active tailnet and colors each machine's operating-system icon:

- Green: the machine is online.
- Red: the machine is offline.

The panel also retains the built-in Tailscale controls for connection state,
account switching, exit-node selection, copying machine addresses, and
Taildrop where available.

## Security boundaries

The plugin invokes Tailscale and its helpers by fixed absolute paths, uses a
minimal environment for every managed process, limits captured output to
256 KiB per stream, and cancels a command that exceeds its deadline.

## Requirements

- Omarchy with Quickshell support
- Tailscale CLI installed and signed in

## Install

```bash
omarchy plugin add https://github.com/cylon58/omarchy-tailnet-presence.git
```

Tailnet Presence replaces Omarchy's built-in Tailscale widget in its current
bar position, so no bar-layout change is needed.

## Update

```bash
omarchy plugin update cylon58.tailnet-presence
```

## Remove

```bash
omarchy plugin remove cylon58.tailnet-presence
```

## Refresh interval

The plugin polls Tailscale every 30 seconds by default. Change the plugin's
**Refresh interval (seconds)** setting in Omarchy to use a value from 5 to
3,600 seconds.

## Attribution and license

Tailnet Presence derives from Omarchy's Tailscale panel, which is licensed
under the MIT License. This repository is also MIT licensed; see
[LICENSE](LICENSE).
