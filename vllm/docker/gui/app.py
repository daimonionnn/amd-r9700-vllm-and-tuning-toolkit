#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get('GUI_HOST', '0.0.0.0')
PORT = int(os.environ.get('GUI_PORT', '8080'))
VLLM_BASE_URL = os.environ.get('VLLM_BASE_URL') or f"http://127.0.0.1:{os.environ.get('VLLM_PORT', '8000')}"
DEFAULT_MODEL = os.environ.get('VLLM_MODEL', 'Qwen3.6-27B-FP8')
DEFAULT_MODE = os.environ.get('GUI_DEFAULT_MODE', 'chat')
DEFAULT_TEMPERATURE = os.environ.get('GUI_DEFAULT_TEMPERATURE', '0.2')
DEFAULT_MAX_TOKENS = os.environ.get('GUI_DEFAULT_MAX_TOKENS', '10000')
DEFAULT_SYSTEM_PROMPT = os.environ.get(
    'GUI_DEFAULT_SYSTEM_PROMPT',
    'You are a concise assistant. Keep answers short and practical.',
)

PAGE = r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>vLLM Browser Prompt UI</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0b1020;
      --panel: rgba(16, 23, 41, 0.9);
      --panel-2: rgba(22, 31, 54, 0.95);
      --text: #e8edf7;
      --muted: #9fb0d0;
      --accent: #74d0ff;
      --accent-2: #9bffcb;
      --border: rgba(126, 156, 204, 0.22);
      --shadow: 0 24px 80px rgba(0, 0, 0, 0.45);
      --radius: 20px;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(116, 208, 255, 0.18), transparent 38%),
        radial-gradient(circle at right 15%, rgba(155, 255, 203, 0.10), transparent 34%),
        linear-gradient(135deg, #060915 0%, #0b1020 45%, #101a33 100%);
    }
    .wrap {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 24px 0 40px;
    }
    .hero {
      display: grid;
      gap: 12px;
      margin-bottom: 20px;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      color: var(--accent-2);
      text-transform: uppercase;
      letter-spacing: 0.16em;
      font-size: 12px;
      font-weight: 700;
    }
    .title {
      font-size: clamp(32px, 4vw, 54px);
      line-height: 0.98;
      margin: 0;
      max-width: 12ch;
    }
    .subtitle {
      margin: 0;
      max-width: 68ch;
      color: var(--muted);
      font-size: 15px;
      line-height: 1.6;
    }
    .grid {
      display: grid;
      gap: 16px;
      grid-template-columns: 1.15fr 0.85fr;
    }
    .card {
      background: linear-gradient(180deg, rgba(24, 34, 58, 0.92), rgba(15, 22, 40, 0.96));
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      overflow: hidden;
    }
    .card-head {
      padding: 16px 18px;
      border-bottom: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: center;
      background: rgba(255, 255, 255, 0.02);
    }
    .card-head h2, .card-head h3 {
      margin: 0;
      font-size: 15px;
      letter-spacing: 0.02em;
    }
    .badge {
      font-size: 12px;
      color: #b5c7ef;
      border: 1px solid rgba(181, 199, 239, 0.25);
      padding: 6px 10px;
      border-radius: 999px;
      background: rgba(181, 199, 239, 0.08);
    }
    .body {
      padding: 18px;
    }
    label {
      display: block;
      margin: 0 0 8px;
      font-size: 13px;
      color: #c8d5ee;
    }
    input, select, textarea, button {
      font: inherit;
    }
    input, select, textarea {
      width: 100%;
      border-radius: 14px;
      border: 1px solid rgba(141, 166, 219, 0.22);
      background: rgba(8, 13, 28, 0.72);
      color: var(--text);
      padding: 12px 14px;
      outline: none;
    }
    textarea {
      min-height: 150px;
      resize: vertical;
      line-height: 1.5;
    }
    input:focus, select:focus, textarea:focus {
      border-color: rgba(116, 208, 255, 0.75);
      box-shadow: 0 0 0 3px rgba(116, 208, 255, 0.15);
    }
    .row {
      display: grid;
      gap: 12px;
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
    .row-3 {
      display: grid;
      gap: 12px;
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }
    .stack {
      display: grid;
      gap: 14px;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
    }
    button {
      border: 0;
      border-radius: 14px;
      padding: 12px 16px;
      cursor: pointer;
      font-weight: 700;
      color: #07111f;
      background: linear-gradient(135deg, var(--accent), var(--accent-2));
      box-shadow: 0 10px 30px rgba(116, 208, 255, 0.18);
    }
    button.secondary {
      color: var(--text);
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(141, 166, 219, 0.22);
      box-shadow: none;
    }
    .status {
      font-size: 13px;
      color: var(--muted);
    }
    .badge.ok { color: #9bffcb; border-color: rgba(155, 255, 203, 0.36); }
    .badge.err { color: #ff9c9c; border-color: rgba(255, 156, 156, 0.36); }
    pre {
      margin: 0;
      white-space: pre-wrap;
      word-break: break-word;
      min-height: 280px;
      max-height: 62vh;
      overflow: auto;
      background: rgba(4, 8, 18, 0.58);
      border: 1px solid rgba(141, 166, 219, 0.16);
      border-radius: 16px;
      padding: 16px;
      color: #eff4ff;
      line-height: 1.55;
      font-size: 14px;
    }
    .meta {
      display: grid;
      gap: 10px;
      color: var(--muted);
      font-size: 13px;
    }
    .kv {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      padding: 10px 12px;
      border-radius: 14px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(141, 166, 219, 0.12);
    }
    .footer {
      margin-top: 16px;
      color: var(--muted);
      font-size: 12px;
    }
    @media (max-width: 960px) {
      .grid { grid-template-columns: 1fr; }
      .row, .row-3 { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="eyebrow">vLLM browser prompt UI</div>
      <p class="subtitle">This page proxies requests to the local vLLM server, so you can test the Qwen3.6-27B-FP8 model without touching the API directly.</p>
    </div>

    <div class="grid">
      <section class="card">
        <div class="card-head">
          <h2>Prompt</h2>
          <span id="status" class="badge">Idle</span>
        </div>
        <div class="body stack">
          <div class="row-3">
            <div>
              <label for="mode">Mode</label>
              <select id="mode">
                <option value="chat">Chat</option>
                <option value="completion">Completion</option>
              </select>
            </div>
            <div>
              <label for="model">Model</label>
              <input id="model" type="text" spellcheck="false" />
            </div>
            <div>
              <label for="max_tokens">Max tokens</label>
              <input id="max_tokens" type="number" min="1" step="1" />
            </div>
          </div>

          <div class="row">
            <div>
              <label for="temperature">Temperature</label>
              <input id="temperature" type="number" min="0" max="2" step="0.1" />
            </div>
            <div>
              <label for="system_prompt">System prompt</label>
              <input id="system_prompt" type="text" spellcheck="false" />
            </div>
          </div>

          <div>
            <label for="prompt">Prompt</label>
            <textarea id="prompt" placeholder="Ask a question, request code, or paste a prompt here."></textarea>
          </div>

          <div class="actions">
            <button id="send">Generate</button>
            <button id="clear" class="secondary">Clear output</button>
          </div>

          <div>
            <label for="output">Output</label>
            <pre id="output">Ready.</pre>
          </div>
        </div>
      </section>

      <aside class="card">
        <div class="card-head">
          <h3>Server</h3>
          <span class="badge">Proxy</span>
        </div>
        <div class="body meta">
          <div class="kv"><span>vLLM base URL</span><strong id="base_url"></strong></div>
          <div class="kv"><span>Health</span><strong id="health_text">checking…</strong></div>
          <div class="kv"><span>TTFT</span><strong id="m_ttft">-</strong></div>
          <div class="kv"><span>Generation speed</span><strong id="m_tps">-</strong></div>
          <div class="kv"><span>Output tokens</span><strong id="m_tokens">-</strong></div>
          <div class="kv"><span>Elapsed</span><strong id="m_elapsed">-</strong></div>
          <div class="kv"><span>Model endpoint</span><strong>/v1/chat/completions or /v1/completions</strong></div>
          <div class="kv"><span>Browser origin</span><strong>http://127.0.0.1:8080</strong></div>
        </div>
      </aside>
    </div>

    <div class="footer">If the model is still warming up, this UI will show the error from the proxy instead of hanging silently.</div>
  </div>

  <script>
    const config = window.__GUI_CONFIG__;
    const el = (id) => document.getElementById(id);
    const statusEl = el('status');
    const outputEl = el('output');
    const healthTextEl = el('health_text');
    const ttftEl = el('m_ttft');
    const tpsEl = el('m_tps');
    const tokensEl = el('m_tokens');
    const elapsedEl = el('m_elapsed');
    let metricsTimer = null;
    const runMetrics = {
      startedAt: 0,
      firstTokenAt: 0,
      usageCompletionTokens: null,
      streamDone: false,
    };

    el('base_url').textContent = config.vllm_base_url;
    el('mode').value = config.default_mode;
    el('model').value = config.default_model;
    el('max_tokens').value = config.default_max_tokens;
    el('temperature').value = config.default_temperature;
    el('system_prompt').value = config.default_system_prompt;

    async function refreshHealth() {
      try {
        const resp = await fetch('/api/health');
        const text = await resp.text();
        if (resp.ok) {
          healthTextEl.textContent = text.trim() || 'ok';
          statusEl.textContent = 'Server ready';
          statusEl.className = 'badge ok';
        } else {
          healthTextEl.textContent = `error ${resp.status}`;
          statusEl.textContent = 'Proxy error';
          statusEl.className = 'badge err';
        }
      } catch (err) {
        healthTextEl.textContent = 'unreachable';
      }
    }

    function setBusy(isBusy) {
      const btn = el('send');
      btn.disabled = isBusy;
      btn.textContent = isBusy ? 'Generating…' : 'Generate';
      statusEl.textContent = isBusy ? 'Working…' : statusEl.textContent;
    }

    function approxTokenCount(text) {
      const t = String(text || '').trim();
      if (!t) return 0;
      return t.split(/\s+/).length;
    }

    function formatSeconds(sec) {
      if (!Number.isFinite(sec) || sec < 0) return '-';
      return `${sec.toFixed(2)}s`;
    }

    function resetMetrics() {
      runMetrics.startedAt = performance.now();
      runMetrics.firstTokenAt = 0;
      runMetrics.usageCompletionTokens = null;
      runMetrics.streamDone = false;
      ttftEl.textContent = '-';
      tpsEl.textContent = '-';
      tokensEl.textContent = '0';
      elapsedEl.textContent = '0.00s';
      if (metricsTimer) {
        clearInterval(metricsTimer);
      }
      metricsTimer = setInterval(updateMetrics, 150);
    }

    function stopMetrics() {
      if (metricsTimer) {
        clearInterval(metricsTimer);
        metricsTimer = null;
      }
      updateMetrics();
    }

    function updateMetrics() {
      if (!runMetrics.startedAt) return;
      const now = performance.now();
      const elapsed = Math.max((now - runMetrics.startedAt) / 1000, 0);
      elapsedEl.textContent = formatSeconds(elapsed);

      const completionTokens = Number.isFinite(runMetrics.usageCompletionTokens)
        ? runMetrics.usageCompletionTokens
        : approxTokenCount(outputEl.textContent);
      tokensEl.textContent = String(completionTokens);

      if (runMetrics.firstTokenAt > 0) {
        const ttft = Math.max((runMetrics.firstTokenAt - runMetrics.startedAt) / 1000, 0);
        ttftEl.textContent = formatSeconds(ttft);
        const genSeconds = Math.max((now - runMetrics.firstTokenAt) / 1000, 1e-6);
        tpsEl.textContent = `${(completionTokens / genSeconds).toFixed(2)} tok/s`;
      }
    }

    async function generateStreaming(payload) {
      const resp = await fetch('/api/generate/stream', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!resp.ok || !resp.body) {
        const txt = await resp.text();
        let err = txt || `HTTP ${resp.status}`;
        try {
          const j = JSON.parse(txt);
          err = j.error || err;
        } catch (_) {
          // Keep raw text fallback.
        }
        throw new Error(err);
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let kind = payload.mode || 'chat';

      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          break;
        }
        buffer += decoder.decode(value, { stream: true });

        while (true) {
          const idx = buffer.indexOf('\n');
          if (idx < 0) break;
          const line = buffer.slice(0, idx).trim();
          buffer = buffer.slice(idx + 1);
          if (!line) continue;

          let evt;
          try {
            evt = JSON.parse(line);
          } catch (_) {
            continue;
          }

          if (evt.type === 'chunk') {
            if (evt.text) {
              if (!runMetrics.firstTokenAt) {
                runMetrics.firstTokenAt = performance.now();
              }
              outputEl.textContent += evt.text;
            }
            if (evt.kind) {
              kind = evt.kind;
            }
            continue;
          }

          if (evt.type === 'usage' && evt.usage && Number.isFinite(evt.usage.completion_tokens)) {
            runMetrics.usageCompletionTokens = evt.usage.completion_tokens;
            continue;
          }

          if (evt.type === 'done') {
            runMetrics.streamDone = true;
            statusEl.textContent = `Done (${evt.kind || kind})`;
            statusEl.className = 'badge ok';
            continue;
          }

          if (evt.type === 'error') {
            throw new Error(evt.error || 'streaming error');
          }
        }
      }
    }

    el('clear').addEventListener('click', () => {
      outputEl.textContent = '';
    });

    el('send').addEventListener('click', async () => {
      setBusy(true);
      outputEl.textContent = '';
      resetMetrics();
      const payload = {
        mode: el('mode').value,
        model: el('model').value.trim() || config.default_model,
        prompt: el('prompt').value,
        system_prompt: el('system_prompt').value,
        temperature: Number(el('temperature').value || 0),
        max_tokens: Number(el('max_tokens').value || 128),
      };
      try {
        await generateStreaming(payload);
      } catch (err) {
        outputEl.textContent = String(err);
        statusEl.textContent = 'Error';
        statusEl.className = 'badge err';
      } finally {
        stopMetrics();
        setBusy(false);
        await refreshHealth();
      }
    });

    refreshHealth();
    setInterval(refreshHealth, 10000);
  </script>
</body>
</html>
'''


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode('utf-8')
    handler.send_response(status)
    handler.send_header('Content-Type', 'application/json; charset=utf-8')
    handler.send_header('Content-Length', str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def text_response(handler: BaseHTTPRequestHandler, status: int, payload: str) -> None:
    body = payload.encode('utf-8')
    handler.send_response(status)
    handler.send_header('Content-Type', 'text/plain; charset=utf-8')
    handler.send_header('Content-Length', str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def fetch_json(method: str, path: str, payload: dict | None = None) -> dict:
    url = f'{VLLM_BASE_URL}{path}'
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    headers = {'Content-Type': 'application/json'}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode('utf-8'))


def upstream_stream(path: str, payload: dict) -> urllib.request.addinfourl:
  url = f'{VLLM_BASE_URL}{path}'
  data = json.dumps(payload).encode('utf-8')
  headers = {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  }
  req = urllib.request.Request(url, data=data, headers=headers, method='POST')
  return urllib.request.urlopen(req, timeout=600)


def iter_sse_events(resp: urllib.request.addinfourl):
  for raw in resp:
    line = raw.decode('utf-8', errors='replace').strip()
    if not line or line.startswith(':'):
      continue
    if not line.startswith('data:'):
      continue
    data = line[5:].strip()
    if data == '[DONE]':
      yield {'_done': True}
      break
    try:
      yield json.loads(data)
    except json.JSONDecodeError:
      continue


def build_chat_payload(model: str, prompt: str, system_prompt: str, temperature: float, max_tokens: int) -> dict:
  messages = []
  if system_prompt:
    messages.append({'role': 'system', 'content': system_prompt})
  messages.append({'role': 'user', 'content': prompt})
  return {
    'model': model,
    'messages': messages,
    'temperature': temperature,
    'max_tokens': max_tokens,
    'stream': False,
  }


def build_completion_payload(model: str, prompt: str, system_prompt: str, temperature: float, max_tokens: int) -> dict:
  if system_prompt:
    prompt = f'{system_prompt}\n\nUser: {prompt}\nAssistant:'
  return {
    'model': model,
    'prompt': prompt,
    'temperature': temperature,
    'max_tokens': max_tokens,
    'stream': False,
  }


def stream_with_fallback(handler: BaseHTTPRequestHandler, mode: str, model: str, prompt: str, system_prompt: str, temperature: float, max_tokens: int) -> None:
  attempts: list[tuple[str, str, dict, str]]
  chat_payload = build_chat_payload(model, prompt, system_prompt, temperature, max_tokens)
  completion_payload = build_completion_payload(model, prompt, system_prompt, temperature, max_tokens)
  chat_payload['stream'] = True
  completion_payload['stream'] = True
  chat_payload['stream_options'] = {'include_usage': True}
  completion_payload['stream_options'] = {'include_usage': True}

  if mode == 'completion':
    attempts = [
      ('completion', '/v1/completions', completion_payload, 'text'),
      ('chat', '/v1/chat/completions', chat_payload, 'message'),
    ]
  else:
    attempts = [
      ('chat', '/v1/chat/completions', chat_payload, 'message'),
      ('completion', '/v1/completions', completion_payload, 'text'),
    ]

  last_404_detail: str | None = None
  for kind, path, body, choice_key in attempts:
    try:
      with upstream_stream(path, body) as resp:
        for event in iter_sse_events(resp):
          if event.get('_done'):
            chunk = json.dumps({'type': 'done', 'kind': kind}) + '\n'
            handler.wfile.write(chunk.encode('utf-8'))
            handler.wfile.flush()
            return

          usage = event.get('usage')
          if usage is not None:
            usage_chunk = json.dumps({'type': 'usage', 'usage': usage}) + '\n'
            handler.wfile.write(usage_chunk.encode('utf-8'))
            handler.wfile.flush()

          choices = event.get('choices') or []
          if not choices:
            continue
          first = choices[0] or {}
          text_piece = ''
          if choice_key == 'text':
            text_piece = first.get('text') or ''
          else:
            delta = first.get('delta') or {}
            text_piece = delta.get('content') or delta.get('reasoning') or ''

          if text_piece:
            chunk = json.dumps({'type': 'chunk', 'kind': kind, 'text': text_piece}) + '\n'
            handler.wfile.write(chunk.encode('utf-8'))
            handler.wfile.flush()
        chunk = json.dumps({'type': 'done', 'kind': kind}) + '\n'
        handler.wfile.write(chunk.encode('utf-8'))
        handler.wfile.flush()
        return
    except urllib.error.HTTPError as err:
      if err.code != 404:
        raise
      last_404_detail = err.read().decode('utf-8', errors='replace') if err.fp else str(err)

  if last_404_detail is not None:
    raise RuntimeError(f'upstream HTTP 404: {last_404_detail}')
  raise RuntimeError('generation failed unexpectedly')


def generate_with_fallback(mode: str, model: str, prompt: str, system_prompt: str, temperature: float, max_tokens: int) -> tuple[str, str, dict]:
  attempts: list[tuple[str, str, dict, str]]
  chat_payload = build_chat_payload(model, prompt, system_prompt, temperature, max_tokens)
  completion_payload = build_completion_payload(model, prompt, system_prompt, temperature, max_tokens)

  if mode == 'completion':
    attempts = [
      ('completion', '/v1/completions', completion_payload, 'text'),
      ('chat', '/v1/chat/completions', chat_payload, 'message'),
    ]
  else:
    attempts = [
      ('chat', '/v1/chat/completions', chat_payload, 'message'),
      ('completion', '/v1/completions', completion_payload, 'text'),
    ]

  last_404_detail: str | None = None
  for kind, path, body, choice_key in attempts:
    try:
      data = fetch_json('POST', path, body)
      if choice_key == 'text':
        text = data['choices'][0].get('text', '')
      else:
        choice = data['choices'][0].get('message', {})
        text = choice.get('content') or choice.get('reasoning') or ''
      return kind, text, data
    except urllib.error.HTTPError as err:
      if err.code != 404:
        raise
      last_404_detail = err.read().decode('utf-8', errors='replace') if err.fp else str(err)

  if last_404_detail is not None:
    raise RuntimeError(f'upstream HTTP 404: {last_404_detail}')
  raise RuntimeError('generation failed unexpectedly')


class Handler(BaseHTTPRequestHandler):
    server_version = 'vllm-gui/1.0'

    def log_message(self, fmt: str, *args) -> None:
        print(f'[{self.address_string()}] {fmt % args}')

    def _send_html(self) -> None:
        body = PAGE.replace(
            'window.__GUI_CONFIG__ = config;',
            '',
        )
        config = {
            'vllm_base_url': VLLM_BASE_URL,
            'default_mode': DEFAULT_MODE,
            'default_model': DEFAULT_MODEL,
            'default_max_tokens': DEFAULT_MAX_TOKENS,
            'default_temperature': DEFAULT_TEMPERATURE,
            'default_system_prompt': DEFAULT_SYSTEM_PROMPT,
        }
        init = '<script>window.__GUI_CONFIG__ = ' + json.dumps(config) + ';</script>'
        body = body.replace('</head>', f'  {init}\n</head>', 1)
        text_response(self, 200, body)

    def do_GET(self) -> None:
        if self.path in ('/', '/index.html'):
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            html_bytes = self._render_index().encode('utf-8')
            self.send_header('Content-Length', str(len(html_bytes)))
            self.end_headers()
            self.wfile.write(html_bytes)
            return
        if self.path == '/health':
            try:
                body = urllib.request.urlopen(f'{VLLM_BASE_URL}/health', timeout=10).read().decode('utf-8').strip()
                text_response(self, 200, body or 'ok')
            except Exception as err:
                text_response(self, 502, f'upstream unavailable: {err}')
            return
        if self.path == '/api/health':
            try:
                body = urllib.request.urlopen(f'{VLLM_BASE_URL}/health', timeout=10).read().decode('utf-8').strip()
                json_response(self, 200, {'ok': True, 'text': body or 'ok'})
            except Exception as err:
                json_response(self, 502, {'ok': False, 'error': str(err)})
            return
        if self.path == '/api/models':
            try:
                data = fetch_json('GET', '/v1/models')
                json_response(self, 200, data)
            except Exception as err:
                json_response(self, 502, {'error': str(err)})
            return
        json_response(self, 404, {'error': 'not found'})

    def _render_index(self) -> str:
        config = {
            'vllm_base_url': VLLM_BASE_URL,
            'default_mode': DEFAULT_MODE,
            'default_model': DEFAULT_MODEL,
            'default_max_tokens': DEFAULT_MAX_TOKENS,
            'default_temperature': DEFAULT_TEMPERATURE,
            'default_system_prompt': DEFAULT_SYSTEM_PROMPT,
        }
        init = '<script>window.__GUI_CONFIG__ = ' + json.dumps(config) + ';</script>'
        page = PAGE.replace('</head>', f'  {init}\n</head>', 1)
        return page

    def do_POST(self) -> None:
        if self.path not in ('/api/generate', '/api/generate/stream'):
            json_response(self, 404, {'error': 'not found'})
            return

        try:
            length = int(self.headers.get('Content-Length', '0'))
            payload = json.loads(self.rfile.read(length).decode('utf-8'))
        except Exception as err:
            json_response(self, 400, {'error': f'invalid JSON payload: {err}'})
            return

        mode = payload.get('mode', 'chat')
        model = payload.get('model') or DEFAULT_MODEL
        prompt = str(payload.get('prompt', '')).strip()
        system_prompt = str(payload.get('system_prompt', '')).strip()
        temperature = float(payload.get('temperature', 0.2))
        max_tokens = int(payload.get('max_tokens', 256))

        if not prompt:
            json_response(self, 400, {'error': 'prompt is required'})
            return

        if self.path == '/api/generate/stream':
            self.send_response(200)
            self.send_header('Content-Type', 'application/x-ndjson; charset=utf-8')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            try:
                start_chunk = json.dumps({'type': 'start', 'started_at': time.time()}) + '\n'
                self.wfile.write(start_chunk.encode('utf-8'))
                self.wfile.flush()
                stream_with_fallback(self, mode, model, prompt, system_prompt, temperature, max_tokens)
            except urllib.error.HTTPError as err:
                error_body = err.read().decode('utf-8', errors='replace') if err.fp else str(err)
                err_chunk = json.dumps({'type': 'error', 'error': f'upstream HTTP {err.code}', 'detail': error_body}) + '\n'
                self.wfile.write(err_chunk.encode('utf-8'))
                self.wfile.flush()
            except Exception as err:
                err_chunk = json.dumps({'type': 'error', 'error': str(err)}) + '\n'
                self.wfile.write(err_chunk.encode('utf-8'))
                self.wfile.flush()
            return

        try:
            kind, text, data = generate_with_fallback(mode, model, prompt, system_prompt, temperature, max_tokens)
            json_response(self, 200, {'kind': kind, 'text': text, 'raw': data})
        except urllib.error.HTTPError as err:
            error_body = err.read().decode('utf-8', errors='replace') if err.fp else str(err)
            json_response(self, 502, {'error': f'upstream HTTP {err.code}', 'detail': error_body})
        except Exception as err:
            json_response(self, 502, {'error': str(err)})


def main() -> None:
    print(f'GUI serving on http://{HOST}:{PORT} and proxying to {VLLM_BASE_URL}')
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == '__main__':
    main()
