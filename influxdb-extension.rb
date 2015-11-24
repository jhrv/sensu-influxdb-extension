#!/usr/bin/env ruby

require 'net/http'
require 'multi_json'

module Sensu::Extension
  class InfluxDB < Handler
    
    @@extension_name = 'influxdb-extension'

    def name
      @@extension_name
    end

    def description
      'Transforms and sends metrics to InfluxDB'
    end

    def post_init
      influxdb_config = settings[@@extension_name]
      
      validate_config(influxdb_config)
       
      hostname         = influxdb_config[:hostname] 
      port             = influxdb_config[:port] || 8086
      database         = influxdb_config[:database]
      ssl              = influxdb_config[:ssl] || false
      precision        = influxdb_config[:precision] || 's'
      retention_policy = influxdb_config[:retention_policy]
      rp_queryparam    = if retention_policy.nil? then "" else "&rp=#{retention_policy}" end
      protocol         = if ssl then 'https' else 'http' end 
      username         = influxdb_config[:username]
      password         = influxdb_config[:password]
      auth_queryparam  = if username.nil? or password.nil? then "" else "&u=#{username}&p=#{password}" end
      @BUFFER_SIZE     = influxdb_config[:buffer_size] || 100
      @BUFFER_MAX_AGE  = influxdb_config[:buffer_max_age] || 10

      @uri = URI("#{protocol}://#{hostname}:#{port}/write?db=#{database}&precision=#{precision}#{rp_queryparam}#{auth_queryparam}")
      @http = Net::HTTP::new(@uri.host, @uri.port)         
      @buffer = []
      @buffer_flushed = Time.now.to_i

      @logger.info("#{@@extension_name}: successfully initialized config: hostname: #{hostname}, port: #{port}, database: #{database}, uri: #{@uri.to_s}, username: #{username}, buffer_size: #{@BUFFER_SIZE}, buffer_max_age: #{@BUFFER_MAX_AGE}")
    end

    def run(event)
      begin
        if buffer_too_old? or buffer_too_big?
          flush_buffer
        end
        
        event = MultiJson.load(event)
        tags = create_tags(event[:client][:tags])       
        output = event[:check][:output]

        output.split(/\r\n|\n/).each do |line|
            measurement, field_value, timestamp = line.split(/\s+/)
            point = "#{measurement}#{tags} value=#{field_value} #{timestamp}" 
            @buffer.push(point)
            @logger.debug("#{@@extension_name}: stored point in buffer (#{@buffer.length}/#{@BUFFER_SIZE})")
        end
      rescue => e
        @logger.error("#{@@extension_name}: unable to post payload to influxdb for event #{event} - #{e.backtrace.to_s}")
      end

      yield("#{@@extension_name}: handler finished", 0)
    end
    

    def create_tags(tags)
        begin
            # sorting tags alphabetically in order to increase influxdb performance
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
        
        @logger.debug("#{@@extension_name}: writing payload #{payload} to endpoint #{@uri.to_s}")
        response = @http.request(request)
        @logger.debug("#{@@extension_name}: influxdb http response code = #{response.code}, body = #{response.body}")
    end

    def flush_buffer
      payload = @buffer.join("\n")
      send_to_influxdb(payload)
      @buffer = []
      @buffer_flushed = Time.now.to_i
    end

    def buffer_too_old?
      buffer_age = Time.now.to_i - @buffer_flushed
      buffer_age >= @BUFFER_MAX_AGE
    end 
    
    def buffer_too_big?
      @buffer.length >= @BUFFER_SIZE
    end 

    def validate_config(config)
      if config.nil?
        raise ArgumentError, "no configuration for #{@@extension_name} provided. exiting..."
      end

      ["hostname", "database"].each do |required_setting| 
        if config[required_setting].nil? 
          raise ArgumentError, "required setting #{required_setting} not provided to extension. this should be provided as json element with key '#{@@extension_name}'. exiting..."
        end
      end
    end
  end
end
