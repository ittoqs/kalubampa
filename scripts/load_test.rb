#!/usr/bin/env ruby
require 'redis'
require 'json'
require 'time'

REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379")
TASK_COUNT = 100_000
BATCH_SIZE = 10_000

puts "🔥 Memulai Load Test Kalubampa"
puts "Target Redis : #{REDIS_URL}"
puts "Jumlah Task  : #{TASK_COUNT}"
puts "----------------------------------------"

begin
  redis = Redis.new(url: REDIS_URL)
  redis.ping
  puts "✅ Terkoneksi ke Redis."
rescue => e
  puts "❌ Gagal terkoneksi ke Redis: #{e.message}"
  exit 1
end

# Bersihkan queue sebelum mulai
redis.del("kalubampa:task_queue")
redis.del("kalubampa:processing_queue")
redis.del("kalubampa:result_queue")
redis.del("kalubampa:dead_letter_queue")
puts "🧹 Queue dibersihkan."

puts "⏳ Menyiapkan payload..."
payload = {
  url: "http://example.com/load-test",
  schema_json: {
    container: "body",
    fields: {
      title: "h1"
    }
  }
}.to_json

puts "🚀 Mengirim tasks ke Redis..."
start_time = Time.now

(TASK_COUNT / BATCH_SIZE).times do |i|
  redis.pipelined do |pipeline|
    BATCH_SIZE.times do
      pipeline.lpush("kalubampa:task_queue", payload)
    end
  end
  print "."
end
puts ""

end_time = Time.now
duration = end_time - start_time
enqueue_rate = (TASK_COUNT / duration).round(2)

puts "✅ Berhasil mengirim #{TASK_COUNT} tasks."
puts "⏱️  Waktu Enqueue: #{duration.round(2)} detik"
puts "⚡ Kecepatan Enqueue: #{enqueue_rate} tasks/detik"

puts "----------------------------------------"
puts "👀 Memantau konsumsi worker..."

loop do
  tasks = redis.llen("kalubampa:task_queue")
  processing = redis.llen("kalubampa:processing_queue")
  results = redis.llen("kalubampa:result_queue")
  dead = redis.llen("kalubampa:dead_letter_queue")

  print "\r📊 Queue: #{tasks} | Processing: #{processing} | Results: #{results} | Dead: #{dead}"

  break if tasks == 0 && processing == 0
  sleep 1
end

puts "\n----------------------------------------"
total_time = Time.now - start_time
process_rate = (TASK_COUNT / total_time).round(2)
puts "🎉 Load Test Selesai!"
puts "⏱️  Total Waktu (Enqueue + Process): #{total_time.round(2)} detik"
puts "⚡ Throughput Pekerja: #{process_rate} tasks/detik"

redis.close
