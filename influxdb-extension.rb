#!/usr/bin/env ruby

require 'net/http'
require 'timeout'

module Sensu::Extension
  class Influx < Handler
    
    @@extension_name = 'influxdb-extension'

    def name
      @@extension_name
    end

    def description
      'Outputs metrics to InfluxDB'
    end

    def post_init
      influxdb_config = settings[@@extension_name]
      
      validate_config(influxdb_config)
       
      hostname  = influxdb_config[:hostname] 
      port      = influxdb_config[:port] || 8086
      database  = influxdb_config[:database]
      ssl       = influxdb_config[:ssl] || false
      protocol  = if ssl then 'https' else 'http' end 
      @username = influxdb_config[:username]
      @password = influxdb_config[:password]
      @timeout  = influxdb_config[:timeout] || 15
      @CACHE_SIZE = influxdb_config[:cachesize] || 10

      @uri = URI("#{protocol}://#{hostname}:#{port}/write?db=#{database}")
      @http = Net::HTTP::new(@uri.host, @uri.port)         
      @cache = []

      @logger.info("#{@@extension_name}: Successfully initialized config: hostname: #{hostname}, port: #{port}, database: #{database}, username: #{@username}, timeout: #{@timeout}")
    end
    
    def validate_config(config)
      if config.nil?
        raise ArgumentError, "No configuration for #{@@extension_name} provided. Exiting..."
      end

      ["hostname", "database"].each do |required_setting| 
        if config[required_setting].nil? 
          raise ArgumentError, "Required setting #{required_setting} not provided to extension. This should be provided as JSON element with key '#{@@extension_name}'. Exiting..."
        end
      end
    end

    def create_tags(event)
      begin
        if event[:client].has_key?(:tags)
          # sorting tags alphabetically in order to increase InfluxDB performance
          incoming_tags = Hash[event[:client][:tags].sort]
          tag_strings = []
          incoming_tags.each { |key,value| tag_strings << "#{key}=#{value}" }
          tag_strings.join(",")
        end
      rescue => e
        @logger.error("#{@@extension_name}: unable to create tags from event data #{e.backtrace.to_s}")
      end
    end

    def is_number?(input)
      true if Float(input) rescue false
    end

    def create_payload(output, tags)
      begin
        points = []

        output.split(/\r\n|\n/).each do |line|
            measurement, field_value, timestamp = line.split(/\s+/)
            begin
              timestamp_nano = Integer(timestamp) * (10 ** 9)
              field_value = is_number?(field_value) ? field_value.to_f : field_value
              point = "#{measurement},#{tags} value=#{field_value} #{timestamp_nano}" 
              points << point
            rescue => e
              @logger.debug("skipping invalid timestamp #{timestamp}")
            end
        end
        
        points.join("\n")
      rescue => e
        @logger.error("#{@@extension_name}: unable to create payload from output #{output} and tags #{tags}: #{e.backtrace.to_s}")
      end
    end

    
    def handle(points)
      if @cache.length >= @CACHE_SIZE
        #complete_payload = @cache.join('')
        @logger.debug("cache is full, sending payload #{@cache} to influxdb")
        
        request = Net::HTTP::Post.new(@uri.request_uri)
        request.body = @cache
        request.basic_auth(@username, @password)

        @logger.debug("#{@@extension_name}: writing payload #{@cache} to endpoint #{@uri.to_s}")

        # check if we still need to do this with batching, and or if this should be replaced with a more highlevel library for handling threads
        Thread.new do 
          @http.request(request)
          request.finish
        end

        @cache = []
      else
        logger.debug("Cache length is #{@cache.length}, will add until #{@CACHE_SIZE}")
        @cache.push(points)
      end
    end
    
    def run(event)
      begin
        event = MultiJson.load(event)
        tags = create_tags(event)       
        @logger.debug("created tags: #{tags}")
        payload = create_payload(event[:check][:output], tags)
        handle(payload)
      rescue => e
        @logger.error("#{@@extension_name}: unable to post payload to influxdb - #{e.backtrace.to_s}")
      end

      yield("#{@@extension_name}: Handler finished", 0)
    end

  end
end
