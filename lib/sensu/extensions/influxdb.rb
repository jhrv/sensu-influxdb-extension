#!/usr/bin/env ruby
# coding: utf-8

require "sensu/extension"
require "net/http"
require "json"

module Sensu::Extension
  class InfluxDB < Handler

    @@extension_name = "influxdb-extension"

    def name
      @@extension_name
    end

    def description
      "Transforms and sends metrics to InfluxDB"
    end

    @@default_config = {
      :hostname       => "127.0.0.1",
      :port           => "8086",
      :ssl            => false,
      :precision      => "s",
      :protocol       => "http",
      :buffer_size    => 100,
      :buffer_max_age => 10,
      :proxy_mode     => false
    }

    def create_config(name, defaults)
      if settings[name].nil?
        Raise ArgumentError "no configuration for #{name} provided. exiting..."
      end
      config = defaults.merge(settings[name])
      @logger.debug("Config for #{name} created: #{config}")
      validate_config(name, config)

      hostname         = config[:hostname]
      port             = config[:port]
      database         = config[:database]
      ssl              = config[:ssl]
      ssl_ca_file      = config[:ssl_ca_file]
      ssl_verify       = if config.key?(:ssl_verify) then config[:ssl_verify] else true end
      precision        = config[:precision]
      retention_policy = config[:retention_policy]
      rp_queryparam    = if retention_policy.nil? then "" else "&rp=#{retention_policy}" end
      protocol         = if ssl then "https" else "http" end
      username         = config[:username]
      password         = config[:password]
      auth_queryparam  = if username.nil? or password.nil? then "" else "&u=#{username}&p=#{password}" end
      buffer_size      = config[:buffer_size]
      buffer_max_age   = config[:buffer_max_age]
      proxy_mode       = config[:proxy_mode]

      string = "#{protocol}://#{hostname}:#{port}/write?db=#{database}&precision=#{precision}#{rp_queryparam}#{auth_queryparam}"
      uri = URI(string)
      http = Net::HTTP::new(uri.host, uri.port)
      if ssl
        http.ssl_version = :TLSv1
        http.use_ssl = true
        http.verify_mode = if ssl_verify then OpenSSL::SSL::VERIFY_PEER else OpenSSL::SSL::VERIFY_NONE end
        http.ca_file = ssl_ca_file
      end

      @handlers ||= Hash.new
      @handlers[name] = {
        "http" => http,
        "uri" => uri,
        "buffer" => [],
        "buffer_flushed" => Time.now.to_i,
        "buffer_size" => buffer_size,
        "buffer_max_age" => buffer_max_age,
        "proxy_mode" => proxy_mode
      }

      @logger.info("#{name}: successfully initialized handler: hostname: #{hostname}, port: #{port}, database: #{database}, uri: #{uri.to_s}, username: #{username}, buffer_size: #{buffer_size}, buffer_max_age: #{buffer_max_age}")
      return config
    end

    def post_init
      main_config = create_config(@@extension_name, @@default_config)
      if settings[name].key?(:additional_handlers)
        settings[name][:additional_handlers].each {|h| create_config(h, main_config)}
      end
    end

    def run(event)
      begin
        @logger.debug("event: #{event}")
        event = JSON.parse(event)

        handler = @handlers[@@extension_name]
        unless event["check"]["handlers"].nil?
          event["check"]["handlers"].each {|x|
            if @handlers.has_key?(x)
              @logger.debug("found additional handler: #{x}")
              handler = @handlers[x]
              break
            end
          }
        end

        if buffer_too_old?(handler) or buffer_too_big?(handler)
          flush_buffer(handler)
        end

        output = event["check"]["output"]

        if not handler["proxy_mode"]
          client_tags = event["client"]["tags"] || Hash.new
          check_tags = event["check"]["tags"] || Hash.new
          tags = create_tags(client_tags.merge(check_tags))
        end

        output.split(/\r\n|\n/).each do |point|
            if not handler["proxy_mode"]
              measurement, field_value, timestamp = point.split(/\s+/)

              if not is_number?(timestamp)
                @logger.debug("invalid timestamp, skipping line in event #{event}")
                next
              end

              # Get event output tags
              if measurement.include?('eventtags')
                only_measurement, tagstub = measurement.split('.eventtags.',2)
                event_tags = Hash.new()
                tagstub.split('.').each_slice(2) do |key, value|
                  event_tags[key] = value
                end
                measurement = only_measurement
                tags = create_tags(client_tags.merge(check_tags).merge(event_tags))
              end

              point = "#{measurement}#{tags} value=#{field_value} #{timestamp}"
            end

            handler["buffer"].push(point)
            @logger.debug("#{@@extension_name}: stored point in buffer (#{handler['buffer'].length}/#{handler['buffer_size']})")
        end
        yield 'ok', 0
      rescue => e
        @logger.error("#{@@extension_name}: unable to handle event #{event} - #{e}")
        yield 'error', 2
      end
    end

    def create_tags(tags)
        begin
            # sorting tags alphabetically in order to increase influxdb performance
            sorted_tags = Hash[tags.sort]

            tag_string = ""

            sorted_tags.each do |tag, value|
                next if value.to_s.empty? # skips tags without values
                tag_string += ",#{tag}=#{value}"
            end

            @logger.debug("#{@@extension_name}: created tags: #{tag_string}")
            tag_string
        rescue => e
            @logger.debug("#{@@extension_name}: unable to create tag string from #{tags} - #{e.backtrace.to_s}")
            ""
        end
    end

    def send_to_influxdb(handler)
      payload = handler["buffer"].join("\n")
      request = Net::HTTP::Post.new(handler['uri'].request_uri)
      request.body = payload

      @logger.debug("#{@@extension_name}: writing payload #{payload} to endpoint #{handler['uri'].to_s}")
      response = handler["http"].request(request)
      @logger.debug("#{@@extension_name}: influxdb http response code = #{response.code}, body = #{response.body}")
    end

    def flush_buffer(handler)
      send_to_influxdb(handler)
      handler["buffer"] = []
      handler["buffer_flushed"] = Time.now.to_i
    end

    def buffer_too_old?(handler)
      buffer_age = Time.now.to_i - handler["buffer_flushed"]
      buffer_age >= handler["buffer_max_age"]
    end

    def buffer_too_big?(handler)
      handler["buffer"].length >= handler["buffer_size"]
    end

    def validate_config(name, config)
      if config.nil?
        raise ArgumentError, "no configuration for #{name} provided. exiting..."
      end

      ["hostname", "database"].each do |required_setting|
        if config.has_key?(required_setting)
          raise ArgumentError, "required setting #{required_setting} not provided to extension. this should be provided as json element with key #{name}. exiting..."
        end
      end
    end

    def is_number?(input)
      true if Integer(input) rescue false
    end
  end
end
