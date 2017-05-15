require "sensu/extensions/influxdb"
require "sensu/logger"

describe "Sensu::Extension::InfluxDB" do

  before do
    @extension = Sensu::Extension::InfluxDB.new
    @extension.settings = Hash.new
    @extension.settings["influxdb-extension"] = {
        :database => "test",
        :hostname => "nonexistinghost",
        :additional_handlers => ["proxy"],
        :buffer_size => 5,
        :buffer_max_age => 1
    }
    @extension.settings["proxy"] = {
        :proxy_mode => true
    }
    
    @extension.instance_variable_set("@logger", Sensu::Logger.get(:log_level => :fatal))
    @extension.post_init
  end

  it "processes minimal event" do
    @extension.run(minimal_event.to_json) do 
      buffer = @extension.instance_variable_get("@handlers")["influxdb-extension"]["buffer"]
      expect(buffer[0]).to eq("rspec value=69 1480697845")
    end
  end

  
  it "skips events with invalid timestamp" do
    event = {
      "client" => {
        "name" => "rspec"
      },
      "check" => {
        "output" => "rspec 69 invalid"
      }
    }

    @extension.run(event.to_json) do 
      buffer = @extension.instance_variable_get("@handlers")["influxdb-extension"]["buffer"]
      expect(buffer.size).to eq(0)
    end
  end

  
  it "flushes buffer when full" do
    5.times {
      @extension.run(minimal_event.to_json) do |output,status|
        expect(output).to eq("ok")
        expect(status).to eq(0)
      end
    }
    # flush buffer will fail writing to bogus influxdb
    2.times {
      @extension.run(minimal_event.to_json) do |output,status|
        expect(output).to eq("error")
        expect(status).to eq(2)
      end
    }
  end

  it "flushes buffer when timed out" do
    @extension.run(minimal_event.to_json) do end
    sleep(1)
    @extension.run(minimal_event.to_json) do end

    buffer = @extension.instance_variable_get("@handlers")["influxdb-extension"]["buffer"]
    expect(buffer.size).to eq(1)
  end

  it "sorts event tags alphabetically" do
    event = {
      "client" => {
        "name" => "rspec",
        "tags" => {
          "x" => "1",
          "z" => "1",
          "a" => "1"
        }
      },
      "check" => {
        "output" => "rspec 69 1480697845",
        "tags" => {
          "b" => "1",
          "c" => "1",
          "y" => "1"
        }
      }
    }
    
    @extension.run(event.to_json) do end

    buffer = @extension.instance_variable_get("@handlers")["influxdb-extension"]["buffer"]
    expect(buffer[0]).to eq("rspec,a=1,b=1,c=1,x=1,y=1,z=1 value=69 1480697845")
  end

  it "does not modify input in proxy mode" do
    @extension.run(minimal_event_proxy.to_json) do end

    buffer = @extension.instance_variable_get("@handlers")["proxy"]["buffer"]
    expect(buffer[0]).to eq("rspec 69 1480697845")
  end

end

def minimal_event
    event = {
      "client" => {
        "name" => "rspec"
      },
      "check" => {
        "output" => "rspec 69 1480697845"
      }
    }
end

def minimal_event_proxy
    event = {
      "client" => {
        "name" => "rspec"
      },
      "check" => {
        "handlers" => ["proxy"],
        "output" => "rspec 69 1480697845"
      }
    }
end
