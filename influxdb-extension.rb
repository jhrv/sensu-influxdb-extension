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
      @username = influxdb_config[:username]
      @password = influxdb_config[:password]
      @timeout  = influxdb_config[:timeout] || 15

      @uri = URI("http://#{hostname}:#{port}/write?db=#{database}")
      @http = Net::HTTP::new(@uri.host, @uri.port)         

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
        else
          # if no tags are provided with the client, we add hostname as a tag.
          incoming_tags = {"hostname" => event[:client][:address]}
        end

        tag_strings = []
        incoming_tags.each { |key,value| tag_strings << "#{key}=#{value}" }
        tag_strings.join(",")
      rescue => e
        @logger.error("#{@@extension_name}: unable to create to tags from event data #{e.backtrace.to_s}")
      end
    end

    def is_number?(input)
      true if Float(input) rescue false
    end

    def create_payload(output, tags)
        points = []

        output.split(/\r\n|\n/).each do |line|
            measurement, field_value, timestamp = line.split(/\s+/)
            timestamp_nano = Integer(timestamp) * (10 ** 9)
            field_value = is_number?(field_value) ? field_value.to_f : field_value
            point = "#{measurement},#{tags} value=#{field_value} #{timestamp_nano}" 
            points << point
        end
        
        points.join("\n")
    end

    def run(event)
      begin
        event = MultiJson.load(event)
        tags = create_tags(event)       
        @logger.debug("created tags: #{tags}")
        payload = create_payload(event[:check][:output], tags)

        request = Net::HTTP::Post.new(@uri.request_uri)
        request.body = payload
        request.basic_auth(@username, @password)

        @logger.debug("#{@@extension_name}: writing payload #{payload} to endpoint #{@uri.to_s}")

        Thread.new do 
          @http.request(request)
          request.finish
        end

      rescue => e
        @logger.error("#{@@extension_name}: unable to post payload to influxdb - #{e.backtrace.to_s}")
      end

      yield("#{@@extension_name}: Handler finished", 0)
    end

  end
end
