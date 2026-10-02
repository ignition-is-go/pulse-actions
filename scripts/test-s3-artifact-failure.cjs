const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const action = path.join(root, '.github/actions/s3-artifact/dist/index.js');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-s3-artifact-failure-'));
const workspace = path.join(temporary, 'workspace');
fs.mkdirSync(workspace);
fs.writeFileSync(path.join(workspace, 'payload'), Buffer.alloc(8 * 1024 * 1024, 0x5a));
const output = path.join(temporary, 'output');
fs.writeFileSync(output, '');

const requests = [];
const server = http.createServer((request, response) => {
  requests.push(request.url);
  response.writeHead(403, { 'content-type': 'application/xml' });
  response.end('<Error><Code>AccessDenied</Code><Message>Access Denied.</Message></Error>');
});

server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  const started = Date.now();
  const child = spawn(process.execPath, [action], {
    cwd: workspace,
    env: {
      ...process.env,
      GITHUB_WORKSPACE: workspace,
      GITHUB_REPOSITORY: 'example/repo',
      GITHUB_OUTPUT: output,
      'INPUT_ENDPOINT': `http://127.0.0.1:${port}`,
      'INPUT_BUCKET': 'artifacts',
      'INPUT_ACCESS-KEY': 'testing',
      'INPUT_SECRET-KEY': 'testing',
      'INPUT_SESSION-TOKEN': '',
      'INPUT_NAME': 'linux-build',
      'INPUT_RUN-ID': '123',
      'INPUT_COMPRESSION-LEVEL': '1',
      'INPUT_OPERATION': 'upload',
      'INPUT_PATH': 'payload',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let outputText = '';
  child.stdout.on('data', chunk => { outputText += chunk; });
  child.stderr.on('data', chunk => { outputText += chunk; });
  const timeout = setTimeout(() => child.kill('SIGKILL'), 3000);

  child.once('exit', code => {
    clearTimeout(timeout);
    server.close();
    fs.rmSync(temporary, { recursive: true, force: true });
    assert.notEqual(code, 0, outputText);
    assert(Date.now() - started < 3000, 'artifact action hung after S3 rejected the upload');
    assert(outputText.includes('Access Denied'), outputText);
    assert(requests.some(request => decodeURIComponent(request).includes('rust/v1/artifacts/')), requests);
    console.log('PASS: an S3 rejection stops the streaming archive immediately.');
  });
});
