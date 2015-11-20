#!/usr/bin/env ruby

require 'net/http'
require 'timeout'
require 'multi_json'

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
      @BUFFER_SIZE = influxdb_config[:buffer_size] || 100

      @uri = URI("#{protocol}://#{hostname}:#{port}/write?db=#{database}")
      @http = Net::HTTP::new(@uri.host, @uri.port)         
      @buffer = []

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

    def create_tags(tags)
        begin
            # sorting tags alphabetically in order to increase InfluxDB performance
            sorted_tags = Hash[tags.sort]

            tag_string = "" 
            sorted_tags.each do |tag, value|
                tag_string += ",#{tag}=#{value}"
            end

            @logger.debug("#{@@extension_name}: created tags: #{tag_string}")
            tag_string
        rescue => e
            @logger.error("#{@@extension_name}: unable to create tag string from #{tags} - #{e.backtrace.to_s}")
            ""
        end
    end

    def send_to_influxdb(payload)
        request = Net::HTTP::Post.new(@uri.request_uri)
        request.body = payload 
        request.basic_auth(@username, @password)

        @logger.debug("#{@@extension_name}: writing payload #{payload} to endpoint #{@uri.to_s}")

        Thread.new do 
          response = @http.request(request)
          @logger.debug("#{@@extension_name}: influxdb http response code = #{response.code}, body = #{response.body}")
          request.finish
        end
    end
    
    def run(event)
      begin
        event = MultiJson.load(event)
        tags = create_tags(event[:client][:tags])       
        output = event[:check][:output]

        output.split(/\r\n|\n/).each do |line|
            measurement, field_value, timestamp = line.split(/\s+/)

            begin
                timestamp = Integer(timestamp) * (10 ** 9) # convert to nano
            rescue => e
                @logger.error("#{@@extension_name}: invalid timestamp: #{timestamp} in event #{event}")
                next
            end
            
            point = "#{measurement}#{tags} value=#{field_value} #{timestamp}" 

            if @buffer.length >= @BUFFER_SIZE
                payload = @buffer.join("\n")
                send_to_influxdb(payload)
                @buffer = []
            else
                @buffer.push(point)
                logger.debug("#{@@extension_name}: stored point in buffer (#{@buffer.length}/#{@BUFFER_SIZE})")
            end
        end
      rescue => e
        @logger.error("#{@@extension_name}: unable to post payload to influxdb for event #{event} - #{e.backtrace.to_s}")
      end

      yield("#{@@extension_name}: handler finished", 0)
    end
  end
end
