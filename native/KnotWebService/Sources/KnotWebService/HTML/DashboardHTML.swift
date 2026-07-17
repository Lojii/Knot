//
//  DashboardHTML.swift
//  TunnelServices
//
//  Self-contained HTML dashboard for real-time proxy monitoring.
//

import Foundation

enum DashboardHTML {

    static let html: String = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Knot Proxy Dashboard</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #1a1a2e; color: #e0e0e0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, monospace; font-size: 14px; }
#topbar { background: #16213e; padding: 12px 20px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #0f3460; }
#topbar h1 { font-size: 18px; font-weight: 600; }
#topbar .status { font-size: 12px; color: #888; }
#topbar .status.connected { color: #4ecca3; }
.container { padding: 16px 20px; }
.cards { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 16px; }
.card { background: #16213e; border-radius: 8px; padding: 14px 18px; min-width: 150px; flex: 1; border: 1px solid #0f3460; }
.card .label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }
.card .value { font-size: 22px; font-weight: 700; color: #e0e0e0; }
.card .sub { font-size: 11px; color: #666; margin-top: 4px; }
.progress-bar { width: 100%; height: 6px; background: #0f3460; border-radius: 3px; margin-top: 6px; overflow: hidden; }
.progress-bar .fill { height: 100%; border-radius: 3px; transition: width 0.3s ease; }
.fill-mem { background: #e94560; }
.fill-cpu { background: #f5a623; }
.protocols { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
.proto-badge { background: #16213e; border: 1px solid #0f3460; border-radius: 6px; padding: 8px 14px; text-align: center; min-width: 80px; }
.proto-badge .name { font-size: 11px; color: #888; }
.proto-badge .count { font-size: 18px; font-weight: 700; color: #4ecca3; }
#surf-section { display: none; margin-bottom: 16px; }
#surf-section .surf-bar { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 14px 18px; }
#surf-section .surf-progress { width: 100%; height: 8px; background: #0f3460; border-radius: 4px; margin-top: 8px; overflow: hidden; }
#surf-section .surf-fill { height: 100%; background: #4ecca3; border-radius: 4px; transition: width 0.3s ease; }
#retest-section { display: none; margin-bottom: 16px; }
#retest-section .retest-box { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 14px 18px; }
#retest-section .result { margin-top: 8px; font-size: 13px; }
.table-wrap { background: #16213e; border-radius: 8px; border: 1px solid #0f3460; overflow: hidden; }
.table-wrap table { width: 100%; border-collapse: collapse; }
.table-wrap th { background: #0f3460; padding: 10px 12px; text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #888; position: sticky; top: 0; }
.table-wrap td { padding: 8px 12px; border-bottom: 1px solid #0f3460; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 300px; }
.table-wrap tr.failed td { color: #e94560; }
.table-wrap tr:hover td { background: rgba(78, 204, 163, 0.05); }
#flow-container { max-height: 60vh; overflow-y: auto; }
.status-2xx { color: #4ecca3; }
.status-3xx { color: #f5a623; }
.status-4xx { color: #e94560; }
.status-5xx { color: #ff2e63; }
</style>
</head>
<body>

<div id="topbar">
  <h1>&#x1F534; Knot Proxy Dashboard</h1>
  <div>
    <span class="status" id="ws-status">Disconnected</span>
    &nbsp;|&nbsp;
    <span class="status" id="uptime">Uptime: --</span>
  </div>
</div>

<div class="container">

  <div class="cards">
    <div class="card">
      <div class="label">Memory</div>
      <div class="value" id="mem-value">-- MB</div>
      <div class="progress-bar"><div class="fill fill-mem" id="mem-bar" style="width:0%"></div></div>
    </div>
    <div class="card">
      <div class="label">CPU</div>
      <div class="value" id="cpu-value">--%</div>
      <div class="progress-bar"><div class="fill fill-cpu" id="cpu-bar" style="width:0%"></div></div>
    </div>
    <div class="card">
      <div class="label">Connections</div>
      <div class="value" id="conn-value">0</div>
      <div class="sub" id="conn-sub">active</div>
    </div>
    <div class="card">
      <div class="label">Pool</div>
      <div class="value" id="pool-value">0</div>
      <div class="sub" id="pool-sub">idle / 0 hosts</div>
    </div>
    <div class="card">
      <div class="label">Flows</div>
      <div class="value" id="flow-total">0</div>
      <div class="sub" id="flow-sub">0 failed</div>
    </div>
  </div>

  <div class="protocols">
    <div class="proto-badge"><div class="name">HTTP</div><div class="count" id="p-http">0</div></div>
    <div class="proto-badge"><div class="name">HTTPS</div><div class="count" id="p-https">0</div></div>
    <div class="proto-badge"><div class="name">H2</div><div class="count" id="p-h2">0</div></div>
    <div class="proto-badge"><div class="name">WS</div><div class="count" id="p-ws">0</div></div>
    <div class="proto-badge"><div class="name">WSS</div><div class="count" id="p-wss">0</div></div>
  </div>

  <div id="surf-section">
    <div class="surf-bar">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <span style="font-weight:600">Auto-Surf Progress</span>
        <span id="surf-label">0 / 0</span>
      </div>
      <div class="surf-progress"><div class="surf-fill" id="surf-fill" style="width:0%"></div></div>
      <div class="sub" id="surf-url" style="margin-top:6px"></div>
    </div>
  </div>

  <div id="retest-section">
    <div class="retest-box">
      <div style="font-weight:600">Retest Results</div>
      <div class="result" id="retest-content"></div>
    </div>
  </div>

  <div class="table-wrap">
    <div id="flow-container">
      <table>
        <thead>
          <tr>
            <th>Time</th>
            <th>Protocol</th>
            <th>Method</th>
            <th>Host</th>
            <th>URI</th>
            <th>Status</th>
            <th>Size</th>
            <th>Duration</th>
          </tr>
        </thead>
        <tbody id="flow-tbody"></tbody>
      </table>
    </div>
  </div>

</div>

<script>
(function() {
  var ws = null;
  var startTime = Date.now();
  var flowCount = 0;
  var failedCount = 0;

  var protoCounters = { http: 0, https: 0, h2: 0, ws: 0, wss: 0 };

  function $(id) { return document.getElementById(id); }

  function formatBytes(b) {
    if (b == null) return '--';
    if (b < 1024) return b + ' B';
    if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
    return (b / 1048576).toFixed(1) + ' MB';
  }

  function formatDuration(ms) {
    if (ms == null) return '--';
    if (ms < 1000) return ms + ' ms';
    return (ms / 1000).toFixed(2) + ' s';
  }

  function statusClass(code) {
    if (!code) return '';
    if (code >= 200 && code < 300) return 'status-2xx';
    if (code >= 300 && code < 400) return 'status-3xx';
    if (code >= 400 && code < 500) return 'status-4xx';
    return 'status-5xx';
  }

  function updateUptime() {
    var s = Math.floor((Date.now() - startTime) / 1000);
    var h = Math.floor(s / 3600); s %= 3600;
    var m = Math.floor(s / 60); s %= 60;
    $('uptime').textContent = 'Uptime: ' + h + 'h ' + m + 'm ' + s + 's';
  }
  setInterval(updateUptime, 1000);

  function connect() {
    var proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(proto + '//' + location.host + '/ws?token=__KNOT_TOKEN__');

    ws.onopen = function() {
      $('ws-status').textContent = 'Connected';
      $('ws-status').className = 'status connected';
    };

    ws.onclose = function() {
      $('ws-status').textContent = 'Disconnected';
      $('ws-status').className = 'status';
      setTimeout(connect, 2000);
    };

    ws.onerror = function() { ws.close(); };

    ws.onmessage = function(evt) {
      try {
        var msg = JSON.parse(evt.data);
        handleMessage(msg);
      } catch(e) {}
    };
  }

  function handleMessage(msg) {
    switch (msg.type) {
      case 'flow': handleFlow(msg.data); break;
      case 'stats': handleStats(msg.data); break;
      case 'metrics': handleMetrics(msg.data); break;
      case 'retest': handleRetest(msg.data); break;
      case 'surf_progress': handleSurf(msg.data); break;
    }
  }

  function handleFlow(d) {
    flowCount++;
    var isFailed = d.status >= 400 || d.failed;
    if (isFailed) failedCount++;

    var proto = (d.protocol || 'HTTP').toUpperCase();
    var key = proto.toLowerCase().replace('/', '');
    if (protoCounters[key] !== undefined) {
      protoCounters[key]++;
      var el = $('p-' + key);
      if (el) el.textContent = protoCounters[key];
    }

    $('flow-total').textContent = flowCount;
    $('flow-sub').textContent = failedCount + ' failed';

    var tbody = $('flow-tbody');
    var tr = document.createElement('tr');
    if (isFailed) tr.className = 'failed';

    var time = d.time || new Date().toLocaleTimeString();
    var sc = d.status ? '<span class="' + statusClass(d.status) + '">' + d.status + '</span>' : '--';

    tr.innerHTML =
      '<td>' + time + '</td>' +
      '<td>' + (d.protocol || '--') + '</td>' +
      '<td>' + (d.method || '--') + '</td>' +
      '<td>' + (d.host || '--') + '</td>' +
      '<td title="' + (d.uri || '') + '">' + (d.uri || '--') + '</td>' +
      '<td>' + sc + '</td>' +
      '<td>' + formatBytes(d.size) + '</td>' +
      '<td>' + formatDuration(d.duration) + '</td>';

    tbody.appendChild(tr);

    var container = $('flow-container');
    container.scrollTop = container.scrollHeight;

    if (tbody.children.length > 1000) {
      tbody.removeChild(tbody.children[0]);
    }
  }

  function handleStats(d) {
    if (d.totalFlows != null) $('flow-total').textContent = d.totalFlows;
    if (d.failedFlows != null) $('flow-sub').textContent = d.failedFlows + ' failed';
    if (d.activeConnections != null) $('conn-value').textContent = d.activeConnections;
    if (d.poolIdle != null) $('pool-value').textContent = d.poolIdle;
    if (d.poolHosts != null) $('pool-sub').textContent = 'idle / ' + d.poolHosts + ' hosts';
  }

  function handleMetrics(d) {
    if (d.memoryMB != null) {
      $('mem-value').textContent = d.memoryMB.toFixed(1) + ' MB';
      var pct = Math.min(100, (d.memoryMB / (d.memoryLimitMB || 512)) * 100);
      $('mem-bar').style.width = pct + '%';
    }
    if (d.cpuPercent != null) {
      $('cpu-value').textContent = d.cpuPercent.toFixed(1) + '%';
      $('cpu-bar').style.width = Math.min(100, d.cpuPercent) + '%';
    }
  }

  function handleRetest(d) {
    $('retest-section').style.display = 'block';
    var html = '<strong>' + (d.url || '--') + '</strong> &mdash; ';
    if (d.passed) {
      html += '<span style="color:#4ecca3">PASSED</span>';
    } else {
      html += '<span style="color:#e94560">FAILED: ' + (d.error || 'unknown') + '</span>';
    }
    if (d.statusCode) html += ' (HTTP ' + d.statusCode + ')';
    $('retest-content').innerHTML = html;
  }

  function handleSurf(d) {
    $('surf-section').style.display = 'block';
    var current = d.current || 0;
    var total = d.total || 0;
    $('surf-label').textContent = current + ' / ' + total;
    var pct = total > 0 ? (current / total * 100) : 0;
    $('surf-fill').style.width = pct + '%';
    if (d.url) $('surf-url').textContent = d.url;
  }

  connect();
})();
</script>

</body>
</html>
"""#

}
