#!/usr/bin/env ruby
# frozen_string_literal: true

# git-auto-commit-ai.rb — Brickverse (Cloudflare Workers AI) backend for
# git-auto-commit. Reads a chat prompt on stdin, calls the Brickverse
# model-proxy, and writes the assistant's reply to stdout.
#
# This helper exists because the main `git-auto-commit` script is bash, while
# the Brickverse backend needs:
#   - Cloudflare Access interactive login (opens a browser, runs a local
#     callback server to capture the CF_Authorization JWT)
#   - JSON request/response handling
# Both are far easier in Ruby stdlib than in bash + curl + jq.
#
# Auth follows the same flow as `mp/vscode/auth-core.ts` and
# `SimpleMultiApp/scripts/auto_release_notes.rb`: the first run opens the
# system browser to complete Cloudflare Access login, and the resulting
# `CF_Authorization` cookie is cached on disk at
# `~/.cache/brickverse/cf_authorization` (mode 0600) for subsequent runs.
#
# Usage:
#   git-auto-commit-ai.rb --model=llama-3.3-70b < prompt.txt
#   echo "say hi" | git-auto-commit-ai.rb
#
# Env vars:
#   BRICKVERSE_HOST  – override the model-proxy origin (default: https://pub.brickverse.net)
#   AI_MODEL         – default model if --model is not given (default: llama-3.3-70b)
#
# Exit codes:
#   0 – success, assistant message written to stdout
#   1 – any failure (login, network, API, empty response); diagnostics on stderr

require 'fileutils'
require 'json'
require 'net/http'
require 'securerandom'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'uri'
require 'rbconfig'

BRICKVERSE_HOST = ENV['BRICKVERSE_HOST'] || 'https://pub.brickverse.net'
# llama-3.3-70b is the default because it answers directly in ~25-70
# completion tokens (~2-4s per call) and follows the commit-message
# format/language rules reliably. Reasoning models (gpt-oss-*, qwen3-*,
# gemma-4-*) spend tokens and wall-clock time on hidden chain-of-thought
# before the answer, so they stay opt-in via --model / AI_MODEL.
DEFAULT_MODEL = ENV['AI_MODEL'] || 'llama-3.3-70b'

COOKIE_PATH = begin
  cache_root = if ENV['XDG_CACHE_HOME'] && !ENV['XDG_CACHE_HOME'].empty?
                 ENV['XDG_CACHE_HOME']
               else
                 File.expand_path('~/.cache')
               end
  File.join(cache_root, 'brickverse', 'cf_authorization')
end

POST_LOGIN_WARN_PATH = File.join(File.dirname(COOKIE_PATH), 'post_login_warn')

# --- Argument parsing ---
model = DEFAULT_MODEL
ARGV.each do |arg|
  case arg
  when /^--model=(.+)$/ then model = Regexp.last_match(1)
  when '-h', '--help'
    puts 'Usage: git-auto-commit-ai.rb [--model=NAME] < prompt'
    exit 0
  else
    warn "✗ Unknown argument: #{arg}"
    exit 2
  end
end

# --- Read prompt from stdin ---
# Expected format: system prompt, then a line containing only `\f` (form feed),
# then the user prompt. The form-feed split keeps the bash caller simple, but
# the two parts are NOT sent as a `system` message: the deployed model-proxy
# (and Cloudflare Workers AI behind it) rejects system-role messages with
# HTTP 500 "System messages are not allowed... Use the instructions option
# instead", and the proxy currently ignores a top-level `instructions` field.
# The proven-working shape (same one auto_release_notes.rb relies on) is a
# single user message, so we fold the system part in as a clearly labelled
# prefix of that one user message.
raw = $stdin.read.to_s
if raw.strip.empty?
  warn '✗ Empty prompt on stdin.'
  exit 1
end
system_prompt, user_prompt = raw.split("\f", 2)
if user_prompt.nil?
  # No separator: treat the whole input as the user prompt.
  system_prompt, user_prompt = nil, raw
end

def fold_prompt(system_prompt, user_prompt)
  if system_prompt && !system_prompt.strip.empty?
    "System instructions:\n#{system_prompt.strip}\n\n" \
      "User request:\n#{user_prompt}"
  else
    user_prompt
  end
end

# --- Cookie helpers ---
def read_stored_cookie
  return nil unless File.exist?(COOKIE_PATH)
  cookie = File.read(COOKIE_PATH).to_s.strip
  cookie.empty? ? nil : cookie
end

def write_stored_cookie(cookie)
  FileUtils.mkdir_p(File.dirname(COOKIE_PATH))
  File.write(COOKIE_PATH, cookie)
  File.chmod(0o600, COOKIE_PATH)
rescue StandardError => e
  warn "[ai] Failed to cache cookie at #{COOKIE_PATH}: #{e.message}"
end

def clear_stored_cookie
  File.delete(COOKIE_PATH) if File.exist?(COOKIE_PATH)
rescue StandardError
  # best-effort
end

def open_browser(url)
  cmd = case RbConfig::CONFIG['host_os']
        when /mswin|mingw|cygwin/ then ['cmd', '/c', 'start', '""', url]
        when /darwin/             then ['open', url]
        else                           ['xdg-open', url]
        end
  system(*cmd)
end

# Start a temporary local HTTP server that waits for the browser to GET/POST
# /callback?cf_authorization=<jwt>. Returns [port, thread, wait_proc, server].
def start_local_callback_server
  mutex = Mutex.new
  cond = ConditionVariable.new
  result = nil
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  thread = Thread.new do
    loop do
      client = server.accept
      begin
        request_line = client.gets
        next unless request_line
        method, path, _ = request_line.split(' ', 3)
        content_length = 0
        while (line = client.gets) && line != "\r\n"
          if (m = line.match(/\AContent-Length:\s*(\d+)/i))
            content_length = m[1].to_i
          end
        end
        body = content_length.positive? ? client.read(content_length) : ''

        token = nil
        if method == 'GET' && path&.start_with?('/callback')
          qs = path.split('?', 2)[1].to_s
          token = URI.decode_www_form(qs).to_h['cf_authorization']
        elsif method == 'POST' && path == '/callback'
          token = URI.decode_www_form(body).to_h['cf_authorization']
        end

        if token && !token.empty?
          client.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
          client.close
          mutex.synchronize do
            result = token
            cond.signal
          end
          break
        else
          client.write("HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 14\r\nConnection: close\r\n\r\nmissing token")
          client.close
        end
      rescue StandardError
        begin
          client.close
        rescue StandardError
          nil
        end
      end
    end
  end

  wait_proc = lambda do
    mutex.synchronize do
      Timeout.timeout(5 * 60) { cond.wait(mutex) until result }
    end
    result
  end

  [port, thread, wait_proc, server]
end

def interactive_login
  port, _thread, wait_proc, server = start_local_callback_server
  callback_url = "http://127.0.0.1:#{port}/callback"
  login_url = "#{BRICKVERSE_HOST}/auth/vscode-login?callback=#{URI.encode_www_form_component(callback_url)}"

  warn '[ai] No cached Brickverse session found. Starting interactive login…'
  warn "[ai] Opening browser to: #{login_url}"
  open_browser(login_url)
  warn '[ai] If the browser did not open, copy the URL above into your browser.'
  warn '[ai] You have 5 minutes to complete Cloudflare Access login.'

  begin
    token = wait_proc.call
    warn '[ai] Logged in to Brickverse.'
    token
  rescue Timeout::Error
    warn '[ai] Interactive login timed out after 5 minutes.'
    nil
  ensure
    begin
      server.close
    rescue StandardError
      nil
    end
  end
end

def resolve_token
  cookie = read_stored_cookie
  return cookie if cookie
  cookie = interactive_login
  write_stored_cookie(cookie) if cookie
  cookie
end

# --- HTTP call ---
# Returns [kind, content]. kind is one of:
#   :ok        – content holds the assistant message
#   :forbidden – Cloudflare Access rejected the cookie (caller should re-login)
#   :empty     – HTTP 200 but no usable text (transient upstream truncation)
#   :error     – any other failure (content holds a human-readable detail)
def chat_completion(system_prompt, user_prompt, model, cookie)
  api_url = URI("#{BRICKVERSE_HOST}/model-proxy/v1/chat/completions")

  # The deployed model-proxy rejects `system`-role messages (HTTP 500) and
  # ignores a top-level `instructions` field, so everything goes into one
  # user message.
  messages = [{ role: 'user', content: fold_prompt(system_prompt, user_prompt) }]

  body = {
    model: model,
    messages: messages,
    max_tokens: 2000,
    temperature: 0.2,
    # Stream the response (SSE). Workers AI / the model-proxy historically
    # returned numeric token-id chunks (e.g. {"content":250}) that surfaced
    # either as an opaque HTTP 500 (non-streaming) or as an "[Error: ...]"
    # SSE frame (streaming); the model-proxy now sanitizes those chunks, but
    # streaming is kept because it reports mid-stream failures readably and
    # plays well with the retry loop below, which still absorbs transient
    # network/open-timeout errors and older proxy deployments.
    stream: true
  }

  http = Net::HTTP.new(api_url.host, api_url.port)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 60

  cert_file = ENV['SSL_CERT_FILE']
  if cert_file && File.exist?(cert_file)
    http.ca_file = cert_file
  else
    %w[
      /etc/ssl/cert.pem
      /usr/local/etc/openssl/cert.pem
      /opt/homebrew/etc/openssl/cert.pem
      /usr/local/etc/openssl@3/cert.pem
      /opt/homebrew/etc/openssl@3/cert.pem
    ].each do |path|
      if File.exist?(path)
        http.ca_file = path
        break
      end
    end
  end

  req = Net::HTTP::Post.new(api_url)
  req['Cookie'] = "CF_Authorization=#{cookie}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body)

  if ENV['GIT_AUTO_COMMIT_AI_DEBUG'] == '1'
    # Use a randomly named, owner-only temp file instead of a fixed
    # /tmp path: a fixed path is symlink-attackable and world-readable.
    debug_path = File.join(Dir.tmpdir, "gac-req-body-#{SecureRandom.hex(8)}.json")
    File.open(debug_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
      f.write(req.body)
    end
    warn "[ai] DEBUG: wrote request body to #{debug_path} (#{req.body.bytesize} bytes)"
    warn "[ai] DEBUG: request URL: #{api_url}"
    warn "[ai] DEBUG: model=#{model}, messages count=#{messages.size}"
    messages.each_with_index do |m, i|
      warn "[ai] DEBUG: message[#{i}] role=#{m[:role]}, content length=#{m[:content].to_s.bytesize}"
    end
  end

  status = nil
  error_body = +""
  parts = []
  stream_error = nil

  # Events are separated by a blank line. TCP segments can split events, so
  # keep an accumulating buffer and only consume frame blocks that are whole.
  sse_buffer = +""
  consume_frame = lambda do |frame|
    frame.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?(':')
      next unless line.start_with?('data:')

      payload = line.sub(/\Adata:\s?/, '')
      break if payload == '[DONE]'

      begin
        data = JSON.parse(payload)
      rescue JSON::ParserError
        next
      end
      choice = data.dig('choices', 0) || {}
      delta = choice['delta'] || {}
      content = delta['content']
      # The proxy encodes mid-stream failures as a normal frame carrying an
      # "[Error: ...]" text with finish_reason "error".
      if choice['finish_reason'] == 'error' || content.to_s.start_with?("\n\n[Error:")
        stream_error = content.to_s
        next
      end
      # Belt-and-braces: never let a stray numeric token id reach the output.
      parts << content if content.is_a?(String)
    end
  end

  http.request(req) do |resp|
    status = resp.code
    if resp.is_a?(Net::HTTPSuccess)
      resp.read_body do |segment|
        sse_buffer << segment
        # Split on blank-line event boundaries while keeping the leftover
        # (possibly partial event) in the buffer.
        while (idx = sse_buffer.index(/\r?\n\r?\n/))
          frame = sse_buffer[0...idx]
          sse_buffer.replace(sse_buffer[(idx + Regexp.last_match(0).length)..-1] || +'')
          consume_frame.call(frame)
        end
      end
      consume_frame.call(sse_buffer) unless sse_buffer.strip.empty?
    else
      resp.read_body { |segment| error_body << segment }
    end
  end

  if ENV['GIT_AUTO_COMMIT_AI_DEBUG'] == '1'
    warn "[ai] DEBUG: response status=#{status}, collected #{parts.join.size} chars"
  end

  case status
  when '200'
    if stream_error
      detail = "stream error frame: #{stream_error.to_s[0..300]}"
      return [stream_error =~ /Type validation/i ? :retryable : :empty, detail]
    end
    content = parts.join.strip
    return [:empty, 'empty content in SSE stream (no text frames received)'] if content.empty?

    [:ok, content]
  when '403'
    clear_stored_cookie
    unless File.exist?(POST_LOGIN_WARN_PATH)
      warn '[ai] Cloudflare Access cookie rejected (HTTP 403). Re-authenticating…'
      FileUtils.mkdir_p(File.dirname(POST_LOGIN_WARN_PATH))
      File.write(POST_LOGIN_WARN_PATH, Time.now.to_i.to_s)
    end
    [:forbidden, "Cloudflare Access cookie rejected (HTTP 403): #{error_body.to_s[0..200]}"]
  else
    detail = "API returned #{status}: #{error_body.to_s[0..300]}"
    # 5xx are commonly the proxy's intermittent upstream parsing errors —
    # worth retrying; other 4xx are deterministic client errors.
    [status.to_s.start_with?('5') ? :retryable : :error, detail]
  end
rescue StandardError => e
  [:retryable, "Request failed: #{e.class}: #{e.message}"]
end

# --- Main ---
cookie = resolve_token
unless cookie
  warn '✗ Could not obtain Brickverse Cloudflare Access cookie.'
  exit 1
end

warn "[ai] Using model: #{model} via #{BRICKVERSE_HOST}"

# The deployed model-proxy fails intermittently (measured ~70% per-call
# success on 2026-09: Cloudflare sometimes streams numeric token-id chunks,
# which the proxy's response schema rejects with HTTP 500 "Type validation
# failed", and reasoning models occasionally return empty content). The
# failures are independent between calls, so a handful of retries takes the
# overall success rate above ~99%.
MAX_ATTEMPTS = 4
message = nil
last_detail = nil

MAX_ATTEMPTS.times do |attempt|
  warn "[ai] Attempt #{attempt + 1}/#{MAX_ATTEMPTS}…" if attempt > 0
  kind, detail = chat_completion(system_prompt, user_prompt, model, cookie)

  case kind
  when :ok
    message = detail
    break
  when :forbidden
    # Cached cookie expired mid-run: drop it and run the interactive login
    # immediately (previously the user had to wait for the next invocation).
    cookie = resolve_token
    last_detail = detail
    unless cookie
      warn '✗ Re-authentication failed.'
      exit 1
    end
  when :empty
    # Upstream answered 200 but with no usable text — retry.
    last_detail = detail
    warn "[ai] #{detail}"
  when :retryable
    last_detail = detail
    warn "[ai] #{detail}"
  else
    # Deterministic client error (4xx other than 403) — retrying won't help.
    warn "✗ #{detail}"
    exit 1
  end

  sleep(2**attempt) if attempt < MAX_ATTEMPTS - 1
end

# Clean up the one-shot warn flag so the next fresh run can warn again.
File.delete(POST_LOGIN_WARN_PATH) if File.exist?(POST_LOGIN_WARN_PATH)

if message.nil? || message.empty?
  warn "✗ No usable response from Brickverse model-proxy after #{MAX_ATTEMPTS} attempts."
  warn "  Last error: #{last_detail}" if last_detail
  exit 1
end

puts message
