sensu-influxdb-extension
========================

Sensu extension for sending metrics with graphite data-format to InfluxDB (>=0.9).

For each sensu-event it receives, it will split the sensu-output into _fields_** and extract tags
defined on the sensu-client configuration into tags. The checks name will be used as the measurement name.

###sensu-client tags => tags

```javascript
{
    "client": {
        "name": "slam_dev_e34jbsl01543",
        "address": "my-app-in-env.domain.tld",
        "subscriptions": [],
        "tags": {
            "environment": "dev",
            "application": "myapp",
            "hostname": "my-app-in-env.domain.tld"
        }
    }
}
```
=>   'environment=dev,application=myapp,hostname=my-app-in-env.domain.tld'

If no tags are defined on the client, it will by default create the tag _hostname_** using the clients address.

###sensu-output (graphite data-format) => fields

Graphite data-format = '<metric_path> <value> <timestamp>\n'

```
key_a 1337 1435216969
key_b 6969 1435216969    =>    'key_a=1337,key_b=6969,key_c=1234'
key_c 1234 1435216969
```

###sensu-check name => measurement

```
    "checks": {
        "cpu-metrics": {
            "type": "metric",   =>   'cpu-metrics'
             ...

```
