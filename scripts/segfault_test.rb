#!/usr/bin/env ruby
require 'webrick'
require 'redis'
require 'json'
require 'thread'

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")
PORT = 8080

puts "🛡️ Memulai Segfault / FFI Memory Safety Test"
puts "Target Redis : #{REDIS_URL}"
puts "Dummy Server : http://localhost:#{PORT}"
puts "----------------------------------------"

# 1. Start a local HTTP server in a separate thread to serve the malformed HTML
server = WEBrick::HTTPServer.new(Port: PORT, AccessLog: [], Logger: WEBrick::Log.new(File.open(File::NULL, 'w')))

nested_html = "<div>" * 5000 + "Target Data" + "</div>" * 5000
malformed_html = "<html><body><div class='job-card'> <span class=salary>$100"

server.mount_proc '/nested' do |req, res|
  res.body = nested_html
  res.content_type = 'text/html'
end

server.mount_proc '/malformed' do |req, res|
  res.body = malformed_html
  res.content_type = 'text/html'
end

server.mount_proc '/large' do |req, res|
  res.body = "<html><body>" + ("<p>Text</p>" * 10_000) + "</body></html>"
  res.content_type = 'text/html'
end

server_thread = Thread.new do
  server.start
end

# Give server time to start
sleep 1

# 2. Connect to Redis and send tasks
begin
  redis = Redis.new(url: REDIS_URL)
  redis.ping
  puts "✅ Terkoneksi ke Redis."
rescue => e
  puts "❌ Gagal terkoneksi ke Redis: #{e.message}"
  server.shutdown
  exit 1
end

redis.del("kalubampa:task_queue")
redis.del("kalubampa:result_queue")

large_schema = {
  container: "body",
  fields: {}
}
1000.times { |i| large_schema[:fields]["field_#{i}"] = "div:nth-child(#{i})" }

tasks = [
  {
    name: "Deeply Nested HTML",
    payload: {
      url: "http://localhost:#{PORT}/nested",
      schema_json: { container: "div", fields: { data: "div" } }
    }
  },
  {
    name: "Malformed HTML",
    payload: {
      url: "http://localhost:#{PORT}/malformed",
      schema_json: { container: ".job-card", fields: { salary: ".salary" } }
    }
  },
  {
    name: "Large HTML & Schema",
    payload: {
      url: "http://localhost:#{PORT}/large",
      schema_json: large_schema
    }
  }
]

puts "🚀 Mengirim tasks ke Redis untuk diuji..."
tasks.each do |task|
  redis.lpush("kalubampa:task_queue", task[:payload].to_json)
  puts "   -> Terkirim: #{task[:name]}"
end

puts "👀 Menunggu hasil dari worker..."

# 3. Wait and check the result queue
timeout = 30
start_time = Time.now
results_received = 0

while (Time.now - start_time) < timeout
  result = redis.rpop("kalubampa:result_queue")

  if result
    results_received += 1
    parsed = JSON.parse(result)
    puts "✅ Hasil diterima untuk: #{parsed['task_url']}"
  end

  dead = redis.rpop("kalubampa:dead_letter_queue")
  if dead
    results_received += 1
    parsed = JSON.parse(dead)
    puts "💀 Masuk Dead Letter Queue: #{parsed['task_url']}"
  end

  break if results_received == tasks.size
  sleep 0.5
end

if results_received == tasks.size
  puts "🎉 Semua tugas diproses tanpa worker mengalami segfault!"
else
  puts "⚠️ Worker mungkin mengalami crash (Segfault), atau belum selesai memproses."
  puts "   Tugas dikirim: #{tasks.size}, Hasil/Dead diterima: #{results_received}"
end

# Cleanup
server.shutdown
server_thread.join
redis.close
puts "🛑 Test Selesai."
