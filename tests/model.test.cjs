const assert = require("node:assert/strict")
const path = require("node:path")
const test = require("node:test")

const modelPath = process.env.MODEL_PATH
assert.ok(modelPath, "MODEL_PATH must name the Model.js implementation under test")
const Model = require(path.resolve(modelPath))

test("parseStatus retains online and offline tailnet machines", () => {
  const result = Model.parseStatus(JSON.stringify({
    BackendState: "Running",
    Self: { HostName: "laptop", TailscaleIPs: ["100.64.0.1"] },
    Peer: {
      online: {
        HostName: "atlas",
        DNSName: "atlas.example.ts.net.",
        Online: true,
        TailscaleIPs: ["100.64.0.2"],
        OS: "linux"
      },
      offline: {
        HostName: "beacon",
        DNSName: "beacon.example.ts.net.",
        Online: false,
        TailscaleIPs: ["100.64.0.3"],
        OS: "windows"
      }
    }
  }))

  assert.deepStrictEqual(result.peers.map(peer => [peer.HostName, peer.Online, peer.presence]), [
    ["atlas", true, "online"],
    ["beacon", false, "offline"]
  ])
})
