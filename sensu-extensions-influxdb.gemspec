# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "sensu-extensions-influxdb"
  spec.version       = "2.0.1"
  spec.authors       = ["Johnny Horvi", "Terje Sannum"]
  spec.email         = ["johnny@horvi.no", "terje@offpiste.org"]

  spec.summary       = "InfluxDB extension for Sensu"
  spec.description   = "InfluxDB extension for Sensu"
  spec.homepage      = "https://github.com/jhrv/sensu-influxdb-extension"

  spec.files         = Dir.glob('{bin,lib}/**/*') + %w(LICENSE README.md CHANGELOG.md)
  spec.require_paths = ["lib"]

  spec.add_dependency "sensu-extension"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "sensu-logger"
  spec.add_development_dependency "sensu-settings"
end
