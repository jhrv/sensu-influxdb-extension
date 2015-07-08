sensu-influxdb-extension
========================

Sensu extension for sending metrics with graphite data-format to InfluxDB (>=0.9).

For each sensu-event it receives, it will split the sensu-output into **measurements** and extract tags
defined on the sensu-client configuration into **tags**.
This extension uses the InfluxDB REST-API directly and does not require any extra gems to be
installed.

# Getting started

1 - Add the *sensu-influxdb-extension.rb* to the sensu extensions folder (/etc/sensu/extensions)

2 - Create your InfluxDB configuration for Sensu (or copy and edit *influxdb-extension.json.tmpl*) inside the sensu config folder (/etc/sensu/conf.d). 

```
{
    "influxdb-extension": {
        "hostname": "influxdb.mydomain.tld",
        "port": "8086",
        "database": "metrics",
        "username": "sensu",
        "password": "m3tr1c54l1f3"
    }
}
```

3 - Add the extension to your sensu-handler configuration 

```
"handlers": {
    "metrics": {
        "type": "set",
        "handlers": [ "influxdb-extension" ]
    }
    ...
 }

```

4 - Configure your metric/check-definitions to use this handler

```
"checks": {
    "metric_cpu": {
        "type": "metric",
        "command": "/etc/sensu/plugins/metrics/cpu-usage.rb",
        "handlers": [ "metrics" ],
        ...
 }
```

5 - Restart your sensu-server and sensu-client(s)

If you follow the sensu-server log (/var/log/sensu/sensu-server.log) you should see the following output if all is working correctly:

```
{"timestamp":"2015-06-21T13:37:04.256753+0200","level":"info","message":"influxdb-extension:
Successfully initialized config: hostname: ....
```

# Explanation on how the extension handles sensu-events and how this translates into InfluxDB concepts

###sensu-client tags => influxdb tags

```
{
    "client": {
        "name": "app_env_hostname",
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

... will turn into the following tags for the series: 'environment=dev,application=myapp,hostname=my-app-in-env.domain.tld'

If no tags are defined on the client, it will by default create the tag hostname using the clients address.

###sensu-output (graphite data-format) => measurements

Graphite data-format = '[metric_path] [value] [timestamp]\n'

Example output:

```
key_a 1337 1435216969
key_b 6969 1435216969
key_c 1234 1435216969
```

... will turn into the following payload written to the InfluxDB write endpoint

```
key_a,<tags> value=1337\nkey_b,<tags> value=6969\nkey_c,<tags> value=1234
```
