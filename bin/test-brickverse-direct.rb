#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick diagnostic for the brickverse backend, mirroring the exact request
# shape that bin/git-auto-commit-ai.rb uses:
#   * ONE user message (system prompt folded in as a labelled prefix) — the
#     model-proxy folds system messages into Workers AI's `instructions`
#     field; the client folds them itself as well so it works against older
#     proxy deployments that reject `system`-role messages.
#   * stream: true — mid-stream upstream failures come back as readable
#     "[Error: ...]" SSE frames instead of opaque non-streaming 500s.
#   * default model llama-3.3-70b — a non-reasoning model that answers
#     directly in a few dozen tokens; reasoning models are opt-in via
#     --model / AI_MODEL.
#
# This is a LIVE integration diagnostic: it needs a cached Cloudflare Access
# cookie and network access. In CI (CI=true) it skips with exit 0 when no
# cookie is present; locally, running it without a cookie fails with exit 1.
#
# Usage:
#   ruby bin/test-brickverse-direct.rb            # small + large prompt tests
#   AI_MODEL=qwen2.5-coder-32b ruby bin/test-brickverse-direct.rb

require 'json'
require 'net/http'
require 'uri'

BRICKVERSE_HOST = ENV['BRICKVERSE_HOST'] || 'https://pub.brickverse.net'
COOKIE_PATH = File.join(
  (ENV['XDG_CACHE_HOME'].to_s.empty? ? File.expand_path('~/.cache') : ENV['XDG_CACHE_HOME']),
  'brickverse', 'cf_authorization'
)
MODEL = ENV['AI_MODEL'] || 'llama-3.3-70b'

unless File.exist?(COOKIE_PATH)
  if ENV['CI'] == 'true'
    puts '⊘ Skipped: no Brickverse Cloudflare Access cookie in CI.'
    puts '  This is a live integration diagnostic; run it locally after'
    puts '  "git-auto-commit --backend=brickverse" has cached a cookie.'
    exit 0
  end
  warn "✗ No cached cookie at #{COOKIE_PATH}. Run git-auto-commit with brickverse backend first."
  exit 1
end

def http_client
  http = Net::HTTP.new(URI(BRICKVERSE_HOST).host, 443)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 120
  %w[
    /etc/ssl/cert.pem
    /opt/homebrew/etc/openssl/cert.pem
    /usr/local/etc/openssl/cert.pem
  ].each do |p|
    next unless File.exist?(p)

    http.ca_file = p
    break
  end
  http
end

# Sends one folded user message via SSE; returns [status, text_or_error].
def call(cookie, content, max_tokens: 2000)
  body = {
    model: MODEL,
    messages: [{ role: 'user', content: content }],
    max_tokens: max_tokens,
    temperature: 0.2,
    stream: true
  }
  req = Net::HTTP::Post.new(URI("#{BRICKVERSE_HOST}/model-proxy/v1/chat/completions"))
  req['Cookie'] = "CF_Authorization=#{cookie}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body)

  status = nil
  raw = +''
  error = nil
  parts = []
  http_client.request(req) do |resp|
    status = resp.code
    if status != '200'
      resp.read_body { |seg| raw << seg }
      next
    end

    resp.read_body do |seg|
      raw << seg
      seg.scan(%r{data: (.+)}) do |(payload),|
        next if payload == '[DONE]'

        frame = JSON.parse(payload) rescue next
        choice = frame.dig('choices', 0) || {}
        delta = choice['delta'] || {}
        if choice['finish_reason'] == 'error' || delta['content'].to_s.start_with?("\n\n[Error:")
          error = delta['content'].to_s
        elsif delta['content'].is_a?(String)
          parts << delta['content']
        end
      end
    end
  end

  if status != '200'
    [status, "HTTP #{status}: #{raw.strip[0, 200]}"]
  elsif error
    [status, "ERROR FRAME: #{error.strip[0, 200]}"]
  else
    [status, parts.join]
  end
end

cookie = File.read(COOKIE_PATH).strip
puts "Host: #{BRICKVERSE_HOST}   Model: #{MODEL}"

# Test 1: minimal prompt (validates cookie, model, folding, SSE plumbing)
sys1 = 'You are a helpful assistant. Reply in one short sentence.'
failed = false
status1, out1 = call(cookie, "#{sys1}\n\n---\n\nSay hello")
puts "\n=== Test 1: minimal folded prompt → HTTP #{status1} (#{out1.size} chars)"
if status1 != '200' || out1.empty?
  failed = true
  puts out1.empty? ? '❌ FAILED: empty' : "❌ FAILED: #{out1.strip}"
else
  puts "✅ #{out1.strip}"
end

# Test 2: commit-message style prompt with a ~12KB diff (the size the bash
# script ships after truncation; this size exposes the upstream
# numeric-token-id flakiness, so a failure here is upstream, not plumbing).
diff = (1..250).map { |i| "+    def feature_#{i}(v)\n      v * #{i}\n    end\n" }.join
sys2 = "Write Conventional Commit messages. Format: type(scope): subject\nOutput ONLY the commit message."
usr2 = "Recent commits:\nfeat: initial version\n\nStaged diff:\n#{diff}"
status2, out2 = call(cookie, "#{sys2}\n\n---\n\n#{usr2}")
puts "\n=== Test 2: commit prompt with #{diff.bytesize}B diff → HTTP #{status2} (#{out2.size} chars)"
if status2 != '200' || out2.empty?
  failed = true
  puts out2.empty? ? '❌ FAILED: empty' : "❌ FAILED: #{out2.strip}"
else
  puts "✅ #{out2.strip.lines.first(3).map(&:rstrip).join("\n")}"
end

exit 1 if failed
