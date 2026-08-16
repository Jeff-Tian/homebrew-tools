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
#   git-auto-commit-ai.rb --model=gpt-oss-120b < prompt.txt
#   echo "say hi" | git-auto-commit-ai.rb
#
# Env vars:
#   BRICKVERSE_HOST  – override the model-proxy origin (default: https://pub.brickverse.net)
#   AI_MODEL         – default model if --model is not given (default: gpt-oss-120b)
#
# Exit codes:
#   0 – success, assistant message written to stdout
#   1 – any failure (login, network, API, empty response); diagnostics on stderr

require 'fileutils'
require 'json'
require 'net/http'
require 'socket'
require 'timeout'
require 'uri'
require 'rbconfig'

BRICKVERSE_HOST = ENV['BRICKVERSE_HOST'] || 'https://pub.brickverse.net'
DEFAULT_MODEL = ENV['AI_MODEL'] || 'gpt-oss-120b'

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
# then the user prompt. The form-feed split keeps the bash caller simple while
# letting us send proper `system` + `user` messages like auto_release_notes.rb
# does — gpt-oss reasoning models behave noticeably better with that split.
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
def chat_completion(system_prompt, user_prompt, model, cookie)
  api_url = URI("#{BRICKVERSE_HOST}/model-proxy/v1/chat/completions")

  messages = []
  messages << { role: 'system', content: system_prompt } if system_prompt && !system_prompt.strip.empty?
  messages << { role: 'user', content: user_prompt }

  body = {
    model: model,
    messages: messages,
    # Reasoning models (gpt-oss-*) burn tokens on hidden chain-of-thought.
    # 2000 is the proven value from auto_release_notes.rb; higher values can
    # cause the model to return empty content with prompt_tokens: 0.
    max_tokens: 2000,
    temperature: 0.2
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
    File.write('/tmp/gac-req-body.json', req.body)
    warn "[ai] DEBUG: wrote request body to /tmp/gac-req-body.json (#{req.body.bytesize} bytes)"
    warn "[ai] DEBUG: request URL: #{api_url}"
    warn "[ai] DEBUG: model=#{model}, messages count=#{messages.size}"
    messages.each_with_index do |m, i|
      warn "[ai] DEBUG: message[#{i}] role=#{m[:role]}, content length=#{m[:content].to_s.bytesize}"
    end
  end

  resp = http.request(req)

  if ENV['GIT_AUTO_COMMIT_AI_DEBUG'] == '1'
    warn "[ai] DEBUG: response status=#{resp.code}"
    resp.each_header { |k, v| warn "[ai] DEBUG: response header: #{k}=#{v}" }
  end

  case resp
  when Net::HTTPSuccess
    warn resp.body
    data = JSON.parse(resp.body)
    message = data.dig('choices', 0, 'message') || {}
    # Reasoning models can put the answer in `content`, `reasoning_content`,
    # `reasoning`, or split it across fields; try them in priority order.
    content = message['content']
    content = message['reasoning_content'] if content.nil? || content.strip.empty?
    content = message['reasoning'] if content.nil? || content.strip.empty?
    # Some Workers AI responses put the text directly on the choice or under
    # `response` — handle those shapes too so we don't silently return nil.
    if content.nil? || content.strip.empty?
      choice = data.dig('choices', 0) || {}
      content = choice['text'] || data['response']
    end
    if content.nil? || content.strip.empty?
      warn '[ai] Empty content in API response. Raw body (first 500 chars):'
      warn resp.body.to_s[0..500]
      return nil
    end
    return content.strip
  when Net::HTTPForbidden
    clear_stored_cookie
    unless File.exist?(POST_LOGIN_WARN_PATH)
      warn '[ai] Cloudflare Access cookie rejected (HTTP 403). The next run will ask you to log in again.'
      FileUtils.mkdir_p(File.dirname(POST_LOGIN_WARN_PATH))
      File.write(POST_LOGIN_WARN_PATH, Time.now.to_i.to_s)
    end
    nil
  else
    warn "[ai] API returned #{resp.code}: #{resp.body.to_s[0..200]}"
    nil
  end
rescue StandardError => e
  warn "[ai] Request failed: #{e.class}: #{e.message}"
  nil
end

# --- Main ---
cookie = resolve_token
unless cookie
  warn '✗ Could not obtain Brickverse Cloudflare Access cookie.'
  exit 1
end

warn "[ai] Using model: #{model} via #{BRICKVERSE_HOST}"

# gpt-oss-120b on Brickverse intermittently returns empty content (with
# prompt_tokens: 0) even for small prompts. Retry a few times — the
# failure is transient and a retry usually succeeds.
MAX_RETRIES = 3
message = nil
MAX_RETRIES.times do |attempt|
  warn "[ai] Attempt #{attempt + 1}/#{MAX_RETRIES}…" if attempt > 0
  message = chat_completion(system_prompt, user_prompt, model, cookie)
  break if message && !message.empty?
  # Brief pause before retry (1s, 2s, 4s)
  sleep(2**attempt) if attempt < MAX_RETRIES - 1
end

# Clean up the one-shot warn flag so the next fresh run can warn again.
File.delete(POST_LOGIN_WARN_PATH) if File.exist?(POST_LOGIN_WARN_PATH)

if message.nil? || message.empty?
  warn "✗ Empty response from Brickverse model-proxy after #{MAX_RETRIES} attempts."
  exit 1
end

puts message
