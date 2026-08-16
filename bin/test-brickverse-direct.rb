#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick diagnostic: pipe a known-good request body through git-auto-commit-ai.rb
# to isolate whether the failure is in the code path or the API.
#
# Usage:
#   ruby bin/test-brickverse-direct.rb
#
# This sends the SAME shape of request that auto_release_notes.rb uses
# (simple system + user prompt, no fancy diff content).

require 'json'
require 'net/http'
require 'uri'

BRICKVERSE_HOST = ENV['BRICKVERSE_HOST'] || 'https://pub.brickverse.net'
COOKIE_PATH = File.expand_path('~/.cache/brickverse/cf_authorization')

unless File.exist?(COOKIE_PATH)
  warn "✗ No cached cookie at #{COOKIE_PATH}. Run git-auto-commit with brickverse backend first."
  exit 1
end

cookie = File.read(COOKIE_PATH).strip
api_url = URI("#{BRICKVERSE_HOST}/model-proxy/v1/chat/completions")

# Test 1: Minimal prompt (like auto_release_notes.rb uses)
puts "=== Test 1: Minimal prompt (same shape as auto_release_notes.rb) ==="
body = {
  model: 'gpt-oss-120b',
  messages: [
    { role: 'system', content: 'You are a helpful assistant. Reply in one short sentence.' },
    { role: 'user', content: 'Say hello' }
  ],
  max_tokens: 2000,
  temperature: 0.3
}

http = Net::HTTP.new(api_url.host, api_url.port)
http.use_ssl = true
http.open_timeout = 15
http.read_timeout = 60
%w[/etc/ssl/cert.pem /opt/homebrew/etc/openssl/cert.pem].each do |p|
  if File.exist?(p)
    http.ca_file = p
    break
  end
end

req = Net::HTTP::Post.new(api_url)
req['Cookie'] = "CF_Authorization=#{cookie}"
req['Content-Type'] = 'application/json'
req.body = JSON.generate(body)

puts "Request body (#{req.body.bytesize} bytes):"
puts JSON.pretty_generate(body)
puts ""

resp = http.request(req)
puts "Response status: #{resp.code}"
data = JSON.parse(resp.body)
puts "Response: #{JSON.pretty_generate(data)}"
content = data.dig('choices', 0, 'message', 'content')
if content && !content.strip.empty?
  puts "✅ SUCCESS: #{content.strip}"
else
  puts "❌ FAILED: empty content (prompt_tokens=#{data.dig('usage', 'prompt_tokens')})"
end

puts ""

# Test 2: Send the git-auto-commit system prompt style (with special chars)
puts "=== Test 2: Commit-message style prompt (with ∈, special chars) ==="
body2 = {
  model: 'gpt-oss-120b',
  messages: [
    { role: 'system', content: "You write git commit messages.\ntype ∈ feat, fix, docs\nOutput ONLY the message." },
    { role: 'user', content: "diff: added hello.rb\n+puts 'hello'" }
  ],
  max_tokens: 2000,
  temperature: 0.2
}

req2 = Net::HTTP::Post.new(api_url)
req2['Cookie'] = "CF_Authorization=#{cookie}"
req2['Content-Type'] = 'application/json'
req2.body = JSON.generate(body2)

puts "Request body (#{req2.body.bytesize} bytes):"
puts JSON.pretty_generate(body2)
puts ""

resp2 = http.request(req2)
puts "Response status: #{resp2.code}"
data2 = JSON.parse(resp2.body)
puts "Response: #{JSON.pretty_generate(data2)}"
content2 = data2.dig('choices', 0, 'message', 'content')
if content2 && !content2.strip.empty?
  puts "✅ SUCCESS: #{content2.strip}"
else
  puts "❌ FAILED: empty content (prompt_tokens=#{data2.dig('usage', 'prompt_tokens')})"
end
