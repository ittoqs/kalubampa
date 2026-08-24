require "http/client"
require "uri"
require "log"
require "./config"

module Kalubampa
  record FetchResult,
    url : String,
    html : String?,
    status_code : Int32,
    bytes : Int64,
    duration_ms : Int64,
    error : String?,
    redirected_to : String?

  class Fetcher
    Log = ::Log.for(self)

    MAX_RESPONSE_BYTES = 10 * 1024 * 1024

    MAX_REDIRECTS = 5

    getter config : Config

    def initialize(@config : Config)
    end

    def fetch(url : String) : FetchResult
      unless safe_target?(url)
        return FetchResult.new(
          url: url, html: nil, status_code: 0, bytes: 0_i64,
          duration_ms: 0_i64, error: "SSRF: blocked internal/private target",
          redirected_to: nil
        )
      end

      last_error : String? = nil
      final_url = url

      (@config.http_max_retries + 1).times do |attempt|
        if attempt > 0
          delay = @config.http_retry_delay_ms * (2 ** (attempt - 1))
          Log.debug { "⏳ Retry #{attempt}/#{@config.http_max_retries} untuk #{url} (delay: #{delay}ms)" }
          sleep delay.milliseconds
        end

        start_time = Time.monotonic

        begin
          result = do_fetch(final_url)

          duration = (Time.monotonic - start_time).total_milliseconds.to_i64

          if result.is_a?(RedirectResult)
            final_url = result.location
            Log.debug { "↪️  Redirect: #{url} → #{final_url}" }
            next
          end

          status, body = result.as(ResponseResult).status, result.as(ResponseResult).body

          if status == 200 && body
            return FetchResult.new(
              url: url,
              html: body,
              status_code: status,
              bytes: body.bytesize.to_i64,
              duration_ms: duration,
              error: nil,
              redirected_to: (final_url != url) ? final_url : nil
            )
          else
            last_error = "HTTP #{status}"
            Log.warn { "⚠️  HTTP #{status} untuk #{url}" }
          end

        rescue ex : IO::TimeoutError
          last_error = "Timeout: #{ex.message}"
          Log.warn { "⏰ Timeout (attempt #{attempt + 1}): #{url}" }
        rescue ex : Socket::ConnectError
          last_error = "Connection refused: #{ex.message}"
          Log.warn { "🔌 Connection error (attempt #{attempt + 1}): #{url}" }
        rescue ex : OpenSSL::SSL::Error
          last_error = "SSL error: #{ex.message}"
          Log.warn { "🔒 SSL error (attempt #{attempt + 1}): #{url}" }
          break # SSL errors biasanya tidak worth retrying
        rescue ex : Exception
          last_error = "#{ex.class}: #{ex.message}"
          Log.warn { "❌ Error (attempt #{attempt + 1}): #{url} — #{ex.message}" }
        end
      end

      duration = 0_i64
      FetchResult.new(
        url: url,
        html: nil,
        status_code: 0,
        bytes: 0_i64,
        duration_ms: duration,
        error: last_error,
        redirected_to: nil
      )
    end

    def fetch_batch(urls : Array(String)) : Array(FetchResult)
      return [] of FetchResult if urls.empty?

      results = Array(FetchResult).new(urls.size)
      channel = Channel(FetchResult).new(urls.size)
      semaphore = Channel(Nil).new(@config.http_concurrency)

      @config.http_concurrency.times { semaphore.send(nil) }

      urls.each do |url|
        spawn do
          semaphore.receive

          begin
            result = fetch(url)
            channel.send(result)
          ensure
            semaphore.send(nil)
          end
        end
      end

      urls.size.times do
        results << channel.receive
      end

      succeeded = results.count(&.html)
      failed = results.size - succeeded
      Log.info { "📦 Batch selesai: #{succeeded} berhasil, #{failed} gagal dari #{urls.size} total" }

      results
    end

    private abstract struct FetchInternalResult
    end

    private record RedirectResult < FetchInternalResult,
      location : String

    private record ResponseResult < FetchInternalResult,
      status : Int32,
      body : String?

    private def do_fetch(
      url : String,
      redirect_count : Int32 = 0
    ) : FetchInternalResult
      if redirect_count >= MAX_REDIRECTS
        return ResponseResult.new(status: 310, body: nil) # Custom: too many redirects
      end

      uri = URI.parse(url)

      client = HTTP::Client.new(uri)
      client.connect_timeout = @config.http_connect_timeout.seconds
      client.read_timeout = @config.http_read_timeout.seconds

      headers = HTTP::Headers{
        "User-Agent"      => @config.user_agent,
        "Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" => "en-US,en;q=0.5",
        "Accept-Encoding" => "identity", # Hindari gzip untuk simplicity
        "Connection"      => "close",
      }

      response = client.get(uri.request_target, headers: headers)

      case response.status_code
      when 200
        body = response.body
        if body.bytesize > MAX_RESPONSE_BYTES
          Log.warn { "⚠️  Response terlalu besar (#{body.bytesize} bytes), truncated: #{url}" }
          body = body[0, MAX_RESPONSE_BYTES]
        end
        ResponseResult.new(status: 200, body: body)
      when 301, 302, 307, 308
        location = response.headers["Location"]?
        if location
          resolved = resolve_redirect(uri, location)
          do_fetch(resolved, redirect_count + 1)
        else
          ResponseResult.new(status: response.status_code, body: nil)
        end
      else
        ResponseResult.new(status: response.status_code, body: nil)
      end
    ensure
      client.try &.close
    end

    private def resolve_redirect(base_uri : URI, location : String) : String
      if location.starts_with?("http")
        location
      else
        "#{base_uri.scheme}://#{base_uri.host}#{location}"
      end
    end

    private def safe_target?(url : String) : Bool
      uri = URI.parse(url)
      host = uri.host.to_s.downcase
      return false if host.empty?
      return false if host == "localhost" || host == "0.0.0.0" || host == "[::]"

      BLOCKED_PATTERNS.none? { |pattern| host.matches?(pattern) }
    rescue
      false
    end

    BLOCKED_PATTERNS = [
      /\A127\./,
      /\A10\./,
      /\A172\.(1[6-9]|2\d|3[01])\./,
      /\A192\.168\./,
      /\A169\.254\./,
      /\A0\./,
      /\A::1\z/,
      /\Afe80:/i,
      /\Afd[0-9a-f]{2}:/i,
    ]
  end
end
