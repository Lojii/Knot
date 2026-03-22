const WebSocket = require('ws');
const http = require('http');
const tls = require('tls');

const PROXY_HOST = '127.0.0.1';
const PROXY_PORT = process.env.PROXY_PORT || 50157;

const endpoints = [
  { url: 'wss://ws.postman-echo.com/raw', label: 'postman-echo', sendMsg: 'hello-knot', expectEcho: true },
  { url: 'wss://socketsbay.com/wss/v2/1/demo/', label: 'socketsbay', sendMsg: 'test', expectEcho: false },
  { url: 'wss://stream.binance.com:9443/ws/btcusdt@trade', label: 'binance-stream', sendMsg: null, expectEcho: false },
];

function testEndpoint(ep) {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      console.log(`  [${ep.label}] TIMEOUT after 10s`);
      resolve({ label: ep.label, status: 'timeout' });
    }, 10000);

    const parsedUrl = new URL(ep.url);
    const targetHost = parsedUrl.hostname;
    const targetPort = parseInt(parsedUrl.port) || 443;

    const connectReq = http.request({
      host: PROXY_HOST,
      port: PROXY_PORT,
      method: 'CONNECT',
      path: `${targetHost}:${targetPort}`,
    });

    connectReq.on('connect', (res, socket) => {
      if (res.statusCode !== 200) {
        console.log(`  [${ep.label}] CONNECT failed: ${res.statusCode}`);
        clearTimeout(timeout);
        resolve({ label: ep.label, status: 'connect_failed' });
        return;
      }

      const tlsSocket = tls.connect({
        socket: socket,
        servername: targetHost,
        rejectUnauthorized: false,
        ALPNProtocols: ['http/1.1'],
      }, () => {
        const ws = new WebSocket(ep.url, {
          createConnection: () => tlsSocket,
          rejectUnauthorized: false,
          handshakeTimeout: 8000,
        });

        ws.on('open', () => {
          console.log(`  [${ep.label}] OPEN ✓`);
          if (ep.sendMsg) ws.send(ep.sendMsg);
        });

        ws.on('message', (data) => {
          const msg = data.toString().substring(0, 80);
          console.log(`  [${ep.label}] MSG: ${msg}`);
          clearTimeout(timeout);
          ws.close(1000);
          resolve({ label: ep.label, status: 'success' });
        });

        ws.on('error', (err) => {
          console.log(`  [${ep.label}] ERR: ${err.message}`);
          clearTimeout(timeout);
          resolve({ label: ep.label, status: 'error', error: err.message });
        });

        ws.on('close', (code) => {
          console.log(`  [${ep.label}] CLOSED: ${code}`);
        });
      });

      tlsSocket.on('error', (err) => {
        console.log(`  [${ep.label}] TLS ERR: ${err.message}`);
        clearTimeout(timeout);
        resolve({ label: ep.label, status: 'tls_error' });
      });
    });

    connectReq.on('error', (err) => {
      console.log(`  [${ep.label}] CONNECT ERR: ${err.message}`);
      clearTimeout(timeout);
      resolve({ label: ep.label, status: 'connect_error' });
    });

    connectReq.end();
  });
}

async function main() {
  console.log(`Testing ${endpoints.length} WSS endpoints through proxy at ${PROXY_HOST}:${PROXY_PORT}\n`);
  const results = [];
  for (const ep of endpoints) {
    const result = await testEndpoint(ep);
    results.push(result);
    console.log('');
  }
  console.log('=== RESULTS ===');
  let pass = 0, fail = 0;
  for (const r of results) {
    const ok = r.status === 'success';
    console.log(`${ok ? '✅' : '❌'} ${r.label}: ${r.status}`);
    if (ok) pass++; else fail++;
  }
  console.log(`\n${pass}/${results.length} passed`);
  process.exit(fail > 0 ? 1 : 0);
}

main();
