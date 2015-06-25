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
      'outputs metrics to InfluxDB'
    end

    def post_init
      influxdb_config = settings[@@extension_name]
      
      validate_config(influxdb_config)
       
      hostname = influxdb_config[:hostname] 
      port     = influxdb_config[:port] || 8086
      database = influxdb_config[:database]
      @username = influxdb_config[:username]
      @password = influxdb_config[:password]
      @timeout  = influxdb_config[:timeout] || 15

      @uri = URI("http://#{hostname}:#{port}/write?db=#{database}")
      @http = Net::HTTP::new(@uri.host, @uri.port)         

      @logger.debug("initialized influxdb config: hostname: #{hostname}, port: #{port}, database: #{database}, username: #{@username}, timeout: #{@timeout}")
    end
    
    def validate_config(config)
      ["hostname", "database"].each do |required_setting| 
        if config[required_setting].nil? 
          raise ArgumentError, "Required setting #{required_setting} not provided to extension. This should be provided as JSON element with key '#{@@extension_name}'. Exiting..."
        end
      end
    end

    def extract_key_value(data)
      key,value = data.split(/\s+/)
      value = value.match('\.').nil? ? Integer(value) : Float(value) rescue value.to_s
      "#{key}=#{value}"
    end
    
    def create_fields(output)
      begin
        lines = output.split(/\n/)
        fields = lines.map(&method(:extract_key_value)).join(",")
        @logger.debug("found following fields: #{fields}")
        fields
      rescue => e
        @logger.error("#{@@extension_name}: unable to convert output to influxdb fields #{e.backtrace.to_s}")
      end
    end

    def create_tags(event)
      begin
        incoming_tags = event[:client][:tags]

        # if no tags are provided with the client, we add hostname as a tag.
        if incoming_tags.nil?
          incoming_tags = {"hostname" => event[:client][:address]}
        end

        tag_strings = []
        incoming_tags.each { |key,value| tag_strings << "#{key}=#{value}" }
        tags = tag_strings.join(",")
        @logger.debug("found following tags: #{tags}")
        tags
      rescue => e
        @logger.error("#{@@extension_name}: unable to create to tags from event data #{e.backtrace.to_s}")
      end
    end

    def run(event)
      begin
        event = MultiJson.load(event)

        measurement = event[:check][:name]
        tags = create_tags(event)       
        fields = create_fields(event[:check][:output])
        payload = "#{measurement},#{tags} #{fields}"

        request = Net::HTTP::Post.new(@uri.request_uri)
        request.body = payload
        request.basic_auth(@username, @password)
        @logger.debug("writing payload #{payload} to endpoint #{@uri.to_s}")
        response = @http.request(request)
      rescue => e
        @logger.error("#{@@extension_name}: unable to post payload to influxb - #{e.backtrace.to_s}")
      end

      yield("#{@@extension_name}: Handler finished", 0)
    end

  end
end
