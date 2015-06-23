#!/usr/bin/env ruby
# coding: utf-8

#require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'net/http'
require 'timeout'

module Sensu::Extension
  class Influx < Handler

    def name
      'influxdb_extension'
    end

    def description
      'outputs metrics to InfluxDB'
    end

    def post_init
      influx_config = settings['influx']
      @timeout = influx_config['timeout'] || 15
    end

    def extract_key_value(data)
      key,value = data.split(/\s+/)
      value = value.match('\.').nil? ? Integer(value) : Float(value) rescue value.to_s
      "#{key}=#{value}"
    end
    
    def convert_fields(output)
      begin
          lines = output.split(/\n/)
          lines.map(&method(:extract_key_value)).join(",")
      rescue => e
          @logger.error("influxdb_extension: unable to convert output to influxdb fields #{e.backtrace.to_s}")
      end
    end
 
    def run(event)
      begin
        event = MultiJson.load(event)
        measurement = event[:check][:name]
        output = event[:check][:output]
        fields = convert_fields(output)
        
        incoming_tags = event[:client][:tags] 
        tags = incoming_tags.each { |key, value| "#{key}=#{value}" }.join(",")

        payload = "#{measurement},#{tags} #{fields}"

      rescue => e
        @logger.error("influxdb_extension: failed to create influxdb payload - #{e.backtrace.to_s}")
      end

      begin

      rescue => e
        @logger.error("influxdb_extension: unable to post payload to influxb - #{e.backtrace.to_s}")
      end

      yield("influxdb_extension: Handler finished", 0)
    end

  end
end
