import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string selfUserId: ""
  property bool fileSharing: false
  property string authUrl: ""
  property var peers: []
  property var exitNodes: []
  property var tailnetExitNodes: []
  property var mullvadExitNodes: []
  property var mullvadRegions: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string switchingAccountId: ""
  property string settingExitNodeId: ""
  property bool accountsAccessDenied: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property string tailscalePath: "/usr/bin/tailscale"
  readonly property string wlCopyPath: "/usr/bin/wl-copy"
  readonly property string pkexecPath: "/usr/bin/pkexec"
  readonly property string taildropPath: "/usr/bin/omarchy-tailscale-send"
  readonly property string browserLauncherPath: "/usr/bin/omarchy-launch-browser"
  readonly property int maxOutputChars: 262144
  readonly property int commandTimeoutMs: 15000
  readonly property var safeEnvironment: ({
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8"
  })
  readonly property bool busy: installCheckProcess.running || statusProcess.running || mullvadExitNodesProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running || clipboardProcess.running || taildropProcess.running || browserProcess.running
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property var _processDeadlines: ({})
  property var _timedOutProcesses: ({})
  property var _truncatedOutputs: ({})

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _mullvadExitNodesOutput: ""
  property string _mullvadExitNodesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastAccountsRefreshMs: 0
  property string _switchOutput: ""
  property string _switchError: ""
  property string _exitNodeOutput: ""
  property string _exitNodeError: ""
  property string _operatorOutput: ""
  property string _operatorError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function filterIPv4(ips) {
    return Model.filterIPv4(ips)
  }

  function cleanDnsName(name) {
    return Model.cleanDnsName(name)
  }

  function shortDnsName(name) {
    return Model.shortDnsName(name)
  }

  function displayHostName(hostName, dnsName) {
    return Model.displayHostName(hostName, dnsName)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function accountLabel(account) {
    return Model.accountLabel(account)
  }

  function tailscaleCommand(args) {
    return [tailscalePath].concat(args || [])
  }

  function operatorEnvironment() {
    return {
      "PATH": "/usr/bin:/bin",
      "LANG": "C.UTF-8",
      "LC_ALL": "C.UTF-8",
      "DISPLAY": Quickshell.env("DISPLAY") || "",
      "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "",
      "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
      "DBUS_SESSION_BUS_ADDRESS": Quickshell.env("DBUS_SESSION_BUS_ADDRESS") || ""
    }
  }

  function startManaged(process, command, timeoutMs) {
    if (process.running) return false
    var name = String(process.objectName || "")
    var deadlines = {}
    for (var key in _processDeadlines) deadlines[key] = _processDeadlines[key]
    deadlines[name] = { process: process, deadline: Date.now() + timeoutMs }
    _processDeadlines = deadlines
    process.command = command
    process.running = true
    return true
  }

  function finishManaged(process) {
    var name = String(process.objectName || "")
    var timedOut = _timedOutProcesses[name] === true
    var deadlines = {}
    var timeouts = {}
    for (var key in _processDeadlines) {
      if (key !== name) deadlines[key] = _processDeadlines[key]
    }
    for (var timeoutName in _timedOutProcesses) {
      if (timeoutName !== name) timeouts[timeoutName] = _timedOutProcesses[timeoutName]
    }
    _processDeadlines = deadlines
    _timedOutProcesses = timeouts
    return timedOut
  }

  function clearOutput(name) {
    root[name] = ""
    var limits = {}
    for (var key in _truncatedOutputs) {
      if (key !== name) limits[key] = _truncatedOutputs[key]
    }
    _truncatedOutputs = limits
  }

  function appendBoundedOutput(name, data, process) {
    var current = String(root[name] || "")
    var chunk = String(data || "")
    var remaining = maxOutputChars - current.length
    if (remaining <= 0) {
      var existingLimits = {}
      for (var existingKey in _truncatedOutputs) existingLimits[existingKey] = _truncatedOutputs[existingKey]
      existingLimits[name] = true
      _truncatedOutputs = existingLimits
      process.running = false
      return
    }
    root[name] = current + chunk.substring(0, remaining)
    if (chunk.length > remaining) {
      var limits = {}
      for (var key in _truncatedOutputs) limits[key] = _truncatedOutputs[key]
      limits[name] = true
      _truncatedOutputs = limits
      process.running = false
    }
  }

  function takeOutputLimit(first, second) {
    var limited = _truncatedOutputs[first] === true || _truncatedOutputs[second] === true
    clearOutput(first)
    clearOutput(second)
    return limited
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    startManaged(clipboardProcess, [wlCopyPath, text], commandTimeoutMs)
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function peerAddress(peer) {
    if (!peer) return ""
    if (peer.DNSName) return cleanDnsName(peer.DNSName)
    if (peer.HostName) return String(peer.HostName)
    var ips = filterIPv4(peer.TailscaleIPs || [])
    return ips.length > 0 ? ips[0] : ""
  }

  function canSendFiles(peer) {
    if (!fileSharing || !running || !peer || !peer.Online) return false
    return Model.isTaildropTarget(peer, selfUserId)
  }

  function sendFile(peer) {
    if (!canSendFiles(peer)) return
    var target = peerAddress(peer)
    if (target === "") return
    startManaged(taildropProcess, [taildropPath, target], 120000)
  }

  function refresh(forceAccounts) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true)
      return
    }
    if (!installCheckProcess.running) {
      refreshing = true
      startManaged(installCheckProcess, [tailscalePath, "version"], commandTimeoutMs)
    }
  }

  function refreshStatusAndAccounts(forceAccounts) {
    if (!installed) return
    if (!statusProcess.running) {
      clearOutput("_statusOutput")
      clearOutput("_statusError")
      refreshing = true
      startManaged(statusProcess, tailscaleCommand(["status", "--json"]), commandTimeoutMs)
    }
    if (!mullvadExitNodesProcess.running) {
      clearOutput("_mullvadExitNodesOutput")
      clearOutput("_mullvadExitNodesError")
      startManaged(mullvadExitNodesProcess, tailscaleCommand(["exit-node", "list"]), commandTimeoutMs)
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      clearOutput("_accountsOutput")
      clearOutput("_accountsError")
      _lastAccountsRefreshMs = now
      startManaged(accountsProcess, tailscaleCommand(["switch", "--list", "--json"]), commandTimeoutMs)
    }
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    selfUserId = ""
    fileSharing = false
    authUrl = ""
    peers = []
    exitNodes = []
    tailnetExitNodes = []
    mullvadExitNodes = []
    mullvadRegions = []
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
    switchingAccountId = ""
    settingExitNodeId = ""
    accountsAccessDenied = false
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse tailscale status"
      console.warn("tailscale", lastError)
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) openAuthUrlFrom(authUrl, false)
    selfName = parsed.selfName
    selfDnsName = parsed.selfDnsName
    selfIp = parsed.selfIp
    selfUserId = parsed.selfUserId
    fileSharing = parsed.fileSharing
    peers = parsed.running ? parsed.peers : []
    tailnetExitNodes = parsed.running ? parsed.exitNodes : []
    exitNodes = parsed.running ? tailnetExitNodes.concat(mullvadRegions) : []

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Stopped") {
      statusText = "Disconnected"
    } else {
      statusText = backendState
    }
    lastError = ""
  }

  function parseAccounts(raw) {
    var parsed = Model.parseAccounts(raw)
    accounts = parsed.accounts
    selectedAccountId = parsed.selectedAccountId
    selectedAccountLabel = parsed.selectedAccountLabel
    accountsAccessDenied = false
  }

  function parseMullvadExitNodes(raw) {
    mullvadExitNodes = Model.parseExitNodeList(raw)
    mullvadRegions = Model.mullvadRegionOptions(mullvadExitNodes)
    exitNodes = running ? tailnetExitNodes.concat(mullvadRegions) : []
  }

  function toggleTailscale() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    // No progress status here — the greyed icon and hero line already convey
    // the optimistic off; only surface a message if the command fails.
    _desired = 0
    runAction(tailscaleCommand(["down"]))
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    var plan = Model.loginPlan(needsLogin, authUrl)
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrlFrom(plan.authUrl, true)
      return
    }
    clearOutput("_loginOutput")
    clearOutput("_loginError")
    if (needsLogin) actionStatus = "Starting Tailscale login…"
    else _desired = 1
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    startManaged(loginProcess, tailscaleCommand(plan.command), 120000)
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running) return
    clearOutput("_switchOutput")
    clearOutput("_switchError")
    switchingAccountId = accountId
    startManaged(switchProcess, tailscaleCommand(["switch", accountId]), commandTimeoutMs)
  }

  function exitNodeTarget(peer) {
    if (!peer) return ""
    if (peer.Mullvad === true) {
      var mullvadIps = filterIPv4(peer.TailscaleIPs || [])
      if (mullvadIps.length > 0) return mullvadIps[0]
    }
    return peerAddress(peer)
  }

  function setExitNode(peer) {
    if (!installed || !running || !peer || exitNodeProcess.running) return
    var active = peer.ExitNode === true
    var target = active ? "" : exitNodeTarget(peer)
    if (!active && target === "") return
    clearOutput("_exitNodeOutput")
    clearOutput("_exitNodeError")
    settingExitNodeId = String(peer.id || "")
    startManaged(exitNodeProcess, tailscaleCommand(["set", "--exit-node=" + target]), commandTimeoutMs)
  }

  function authorizeTailscaleOperator() {
    if (!installed || operatorProcess.running || userName === "") return
    clearOutput("_operatorOutput")
    clearOutput("_operatorError")
    actionStatus = "Authorizing Tailscale operator..."
    startManaged(operatorProcess, [pkexecPath, tailscalePath, "set", "--operator=" + userName], 120000)
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    clearOutput("_actionOutput")
    clearOutput("_actionError")
    actionStatus = label || ""
    startManaged(actionProcess, command, commandTimeoutMs)
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      // Turning on ended up needing browser auth — stop pretending we're up.
      _desired = -1
      _loginUrlOpened = true
      _loginInProgress = false
      loginTimeoutTimer.stop()
      startManaged(browserProcess, [browserLauncherPath, url], commandTimeoutMs)
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var field = isError ? "_loginError" : "_loginOutput"
    appendBoundedOutput(field, String(data || "") + "\n", loginProcess)
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(String(data || ""), false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every spawned helper has a deadline. This protects refreshes and
    // interactive controls alike from a blocked daemon, helper, or polkit UI.
    id: processWatchdog
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      var remaining = {}
      var timedOut = {}
      var expired = []
      for (var key in root._processDeadlines) {
        var entry = root._processDeadlines[key]
        if (entry.deadline <= now) {
          timedOut[key] = true
          expired.push(entry.process)
        } else {
          remaining[key] = entry
        }
      }
      root._processDeadlines = remaining
      for (var priorTimeout in root._timedOutProcesses) timedOut[priorTimeout] = root._timedOutProcesses[priorTimeout]
      root._timedOutProcesses = timedOut
      for (var i = 0; i < expired.length; i++) expired[i].running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return
      if (!root.openAuthUrlFrom(root.authUrl, true)) {
        root._loginInProgress = false
        root.actionStatus = "Tailscale login link not available yet"
      }
    }
  }

  Process {
    id: installCheckProcess
    objectName: "installCheck"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(installCheckProcess)
      root.installed = !timedOut && exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
      else {
        root.refreshing = false
        root.resetUnavailable(timedOut ? "Tailscale check timed out" : "Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    objectName: "status"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_statusOutput", data, statusProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_statusError", data, statusProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(statusProcess)
      root.refreshing = false
      var stdout = String(root._statusOutput || "")
      var stderr = String(root._statusError || "")
      var tooLarge = root.takeOutputLimit("_statusOutput", "_statusError")
      if (timedOut) {
        root.resetUnavailable("Tailscale status timed out")
        root.lastError = "Tailscale status timed out"
      } else if (tooLarge) {
        root.resetUnavailable("Status output too large")
        root.lastError = "Tailscale status exceeded the 256 KiB limit"
      } else if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = root.elideStatus(stderr || "Tailscale status failed")
      }
    }
  }

  Process {
    id: accountsProcess
    objectName: "accounts"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_accountsOutput", data, accountsProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_accountsError", data, accountsProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(accountsProcess)
      var stdout = String(root._accountsOutput || "")
      var stderr = String(root._accountsError || "")
      var tooLarge = root.takeOutputLimit("_accountsOutput", "_accountsError")
      if (timedOut || tooLarge) {
        root.parseAccounts("")
        root.lastError = timedOut ? "Tailscale account lookup timed out" : "Tailscale account output exceeded the 256 KiB limit"
      } else if (exitCode === 0) root.parseAccounts(stdout)
      else {
        root.parseAccounts("")
        if (/profiles access denied/i.test(stderr) || /profiles access denied/i.test(stdout)) {
          root.accountsAccessDenied = true
          root.lastError = "Authorize Tailscale operator to show connections"
        } else {
          root.lastError = elideStatus(stderr || stdout || "Could not list Tailscale connections")
        }
      }
    }
  }

  Process {
    id: mullvadExitNodesProcess
    objectName: "mullvadExitNodes"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_mullvadExitNodesOutput", data, mullvadExitNodesProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_mullvadExitNodesError", data, mullvadExitNodesProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(mullvadExitNodesProcess)
      var stdout = String(root._mullvadExitNodesOutput || "")
      var tooLarge = root.takeOutputLimit("_mullvadExitNodesOutput", "_mullvadExitNodesError")
      if (!timedOut && !tooLarge && exitCode === 0) root.parseMullvadExitNodes(stdout)
      else root.parseMullvadExitNodes("")
    }
  }

  Process {
    id: actionProcess
    objectName: "action"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_actionOutput", data, actionProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_actionError", data, actionProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(actionProcess)
      var stdout = String(root._actionOutput || "")
      var stderr = String(root._actionError || "")
      var tooLarge = root.takeOutputLimit("_actionOutput", "_actionError")
      if (timedOut || tooLarge || exitCode !== 0) {
        root._desired = -1
        root.lastError = timedOut ? "Tailscale command timed out" : (tooLarge ? "Tailscale command output exceeded the 256 KiB limit" : elideStatus(stderr || stdout || "Tailscale command failed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    objectName: "login"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(loginProcess)
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var tooLarge = root.takeOutputLimit("_loginOutput", "_loginError")
      if (timedOut || tooLarge) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = timedOut ? "Tailscale login timed out" : "Tailscale login output exceeded the 256 KiB limit"
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        delayedRefresh.restart()
        return
      }
      var opened = root.openAuthUrlFrom(combined, true)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = elideStatus(combined || "tailscale up failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: switchProcess
    objectName: "switch"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_switchOutput", data, switchProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_switchError", data, switchProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(switchProcess)
      var stdout = String(root._switchOutput || "")
      var stderr = String(root._switchError || "")
      var tooLarge = root.takeOutputLimit("_switchOutput", "_switchError")
      if (timedOut || tooLarge || exitCode !== 0) {
        root.lastError = timedOut ? "Account switch timed out" : (tooLarge ? "Account switch output exceeded the 256 KiB limit" : elideStatus(stderr || stdout || "Account switch failed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastAccountsRefreshMs = 0
      }
      root.switchingAccountId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: exitNodeProcess
    objectName: "exitNode"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_exitNodeOutput", data, exitNodeProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_exitNodeError", data, exitNodeProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(exitNodeProcess)
      var stdout = String(root._exitNodeOutput || "")
      var stderr = String(root._exitNodeError || "")
      var tooLarge = root.takeOutputLimit("_exitNodeOutput", "_exitNodeError")
      if (timedOut || tooLarge || exitCode !== 0) {
        root.lastError = timedOut ? "Exit node selection timed out" : (tooLarge ? "Exit node output exceeded the 256 KiB limit" : elideStatus(stderr || stdout || "Exit node selection failed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settingExitNodeId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: operatorProcess
    objectName: "operator"
    running: false
    command: []
    clearEnvironment: true
    environment: root.operatorEnvironment()
    stdout: SplitParser { onRead: function(data) { root.appendBoundedOutput("_operatorOutput", data, operatorProcess) } }
    stderr: SplitParser { onRead: function(data) { root.appendBoundedOutput("_operatorError", data, operatorProcess) } }
    onExited: function(exitCode) {
      var timedOut = root.finishManaged(operatorProcess)
      var stdout = String(root._operatorOutput || "")
      var stderr = String(root._operatorError || "")
      var tooLarge = root.takeOutputLimit("_operatorOutput", "_operatorError")
      if (timedOut || tooLarge || exitCode !== 0) {
        root.lastError = timedOut ? "Tailscale authorization timed out" : (tooLarge ? "Tailscale authorization output exceeded the 256 KiB limit" : elideStatus(stderr || stdout || "Tailscale authorization failed"))
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.accountsAccessDenied = false
        root.lastError = ""
        root.actionStatus = "Tailscale operator authorized"
        actionStatusTimer.restart()
        root._lastAccountsRefreshMs = 0
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: clipboardProcess
    objectName: "clipboard"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    onExited: function() { root.finishManaged(clipboardProcess) }
  }

  Process {
    id: taildropProcess
    objectName: "taildrop"
    running: false
    command: []
    clearEnvironment: true
    environment: root.safeEnvironment
    onExited: function() { root.finishManaged(taildropProcess) }
  }

  Process {
    id: browserProcess
    objectName: "browser"
    running: false
    command: []
    clearEnvironment: true
    environment: root.operatorEnvironment()
    onExited: function() { root.finishManaged(browserProcess) }
  }
}
