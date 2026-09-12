# Tailnet Presence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish an Omarchy Tailscale panel that lists every peer and colors its machine glyph green online and red offline.

**Architecture:** A self-contained Omarchy `bar-widget` plugin derives from the built-in Tailscale panel. Its JavaScript status model preserves offline peers; QML binds each peer glyph color to its `Online` state. Node tests exercise the JSON-model boundary and a live Omarchy install verifies loading.

**Tech Stack:** QML, Quickshell, JavaScript, Node.js test runner, Omarchy plugin manifest, GitHub.

**Spec:** `docs/superpowers/specs/2026-09-12-tailnet-presence-design.md`

## Global Constraints

- Plugin ID is `cylon58.tailnet-presence`; display name is `Tailnet Presence`.
- Preserve all non-Mullvad peers from `tailscale status --json`, including offline peers.
- Use `#76c893` for online machine glyphs and Omarchy theme `Color.urgent` for offline glyphs.
- Do not modify `/usr/share/omarchy`.
- License the repository as MIT and retain Omarchy attribution.

---

### Task 1: Preserve peer connection state in the status model

**Files:**
- Create: `tests/model.test.cjs`
- Create: `src/Model.js`

**Interfaces:**
- Consumes: Tailscale `status --json` peer map.
- Produces: `parseStatus(raw).peers`, an array of normalized peers with `HostName`, boolean `Online`, and `presence` (`"online"` or `"offline"`) fields.

- [ ] **Step 1: Write the failing test**

```js
const result = Model.parseStatus(JSON.stringify({
  BackendState: "Running",
  Peer: {
    online: { HostName: "atlas", Online: true },
    offline: { HostName: "beacon", Online: false }
  }
}))
assert.deepStrictEqual(result.peers.map(peer => [peer.HostName, peer.Online, peer.presence]), [
  ["atlas", true, "online"],
  ["beacon", false, "offline"]
])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/model.test.cjs /usr/share/omarchy/shell/plugins/panels/tailscale/Model.js`

Expected: FAIL because the built-in model filters the offline peer.

- [ ] **Step 3: Copy the upstream model and retain all normalized peers**

```js
if (normalized.Online) {
  peers.push(normalized)
  if (normalized.ExitNodeOption) exitNodes.push(normalized)
}
```

Replace the conditional peer insertion with unconditional `peers.push(normalized)` and retain the conditional only for `exitNodes.push(normalized)`. Add `presence: peer.Online === true ? "online" : "offline"` to the normalized peer.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/model.test.cjs src/Model.js`

Expected: PASS, with both `atlas` and `beacon` present.

- [ ] **Step 5: Commit**

```bash
git add src/Model.js tests/model.test.cjs
git commit -m "feat: retain offline tailnet machines"
```

### Task 2: Render peer presence colors in the standalone panel

**Files:**
- Create: `src/Panel.qml`
- Create: `src/Service.qml`
- Create: `src/TailscaleIcon.qml`
- Create: `src/manifest.json`

**Interfaces:**
- Consumes: normalized peers from `Service.qml` and the Omarchy `Color` palette.
- Produces: a `cylon58.tailnet-presence` bar widget whose peer glyph uses fixed green online and theme urgent red offline.

- [ ] **Step 1: Copy the upstream panel files and add the status-color binding**

```qml
readonly property color statusColor: peer && peer.presence === "online" ? "#76c893" : Color.urgent

Text {
  text: tailscale.osIcon(peer ? peer.OS : "")
  color: peerRow.statusColor
}
```

Set the manifest ID, name, version, author, description, and bar-widget display name to the repository values.

- [ ] **Step 2: Run unit and QML checks**

Run: `node --test tests/model.test.cjs && qmllint src/Panel.qml src/Service.qml src/TailscaleIcon.qml`

Expected: all Node tests pass and `qmllint` exits successfully.

- [ ] **Step 3: Commit**

```bash
git add src tests
git commit -m "feat: color tailnet machines by presence"
```

### Task 3: Document, install, and publish the plugin

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`

**Interfaces:**
- Consumes: GitHub repository URL and Omarchy plugin command.
- Produces: documented installation, update, removal, and verification workflow.

- [ ] **Step 1: Write documentation and license**

Document prerequisites, installation, update, removal, state-color behavior,
refresh configuration, and MIT/Omarchy attribution.

- [ ] **Step 2: Run complete verification and live-install check**

Run: `node --test tests/*.test.cjs && qmllint src/Panel.qml src/Service.qml src/TailscaleIcon.qml && omarchy plugin add file:///home/geoff/Work/omarchy-tailnet-presence && omarchy-plugin-list --json`

Expected: tests and QML validation pass; the plugin list includes `cylon58.tailnet-presence`.

- [ ] **Step 3: Commit and publish**

```bash
git add README.md LICENSE .gitignore
git commit -m "docs: publish tailnet presence plugin"
gh repo create cylon58/omarchy-tailnet-presence --public --source=. --remote=origin --push
```
