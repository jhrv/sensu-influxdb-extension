sensu-influxdb-extension
========================

[Sensu](https://sensuapp.org/) extension for sending metrics with graphite data-format to [InfluxDB](https://influxdb.com/). For more arbitrary event-type data, check out [sensu-influxdb-proxy-extension](https://github.com/jhrv/sensu-influxdb-proxy-extension) instead.

For each sensu-event it receives, it will transform each line of data into a InfluxDB datapoint, containing optional tags defined on the sensu client. It will buffer up points until it reaches the configured length or maximum age (see **buffer_size** and **buffer_max_age**), and then post the data directly to the InfluxDB REST-API using the [line protocol](https://influxdb.com/docs/v0.9/write_protocols/line.html).

Example line of graphite data-format ([metric_path] [value] [timestamp]\n):

```
key_a 6996 1435216969
```

will be transformed into the following data-point ([line protocol](https://influxdb.com/docs/v0.9/write_protocols/line.html))...

```
key_a[,<sensu_client_tags>] value=6996 1435216969\n...
```

# Getting started

1) Add the *sensu-influxdb-extension.rb* to the sensu extensions folder (/etc/sensu/extensions)

2) Create your InfluxDB configuration for Sensu (or copy and edit *influxdb-extension.json.tmpl*) inside the sensu config folder (/etc/sensu/conf.d). 

Example of a minimal configuration file
```
{
    "influxdb-extension": {
        "hostname": "influxdb.mydomain.tld",
        "database": "metrics",
    }
}
```

## Full list of configuration options

| variable          | default value         |
| ----------------- | --------------------- |
| hostname          |       none (required) |
| port              |                  8086 | 
| database          |       none (required) |
| buffer_size       |           100 (lines) |
| buffer_max_age    |          10 (seconds) |
| ssl               |                 false |
| precision         |                 s (*) |
| retention_policy  |                  none |
| username          |                  none |
| password          |                  none |

(*) s = seconds. Other valid options are n, u, ms, m, h. See [influxdb docs](https://influxdb.com/docs/v0.9/write_protocols/write_syntax.html) for more details


3) Add the extension to your sensu-handler configuration 

```
"handlers": {
    "metrics": {
        "type": "set",
        "handlers": [ "influxdb-extension" ]
    }
    ...
 }

```

4) Configure your metric/check-definitions to use this handler

```
"checks": {
    "metric_cpu": {
        "type": "metric",
        "command": "/etc/sensu/plugins/metrics/cpu-usage.rb",
        "handlers": [ "metrics" ],
        ...
 }
```

5) Restart your sensu-server and sensu-client(s)


If you follow the sensu-server log (/var/log/sensu/sensu-server.log) you should see the following output if all is working correctly:

```
{"timestamp":"2015-06-21T13:37:04.256753+0200","level":"info","message":"influxdb-extension:
Successfully initialized config: hostname: ....
```

#tags (optional)

If you want to tag your InfluxDB measurements (great for querying, as tags are indexed), you can define this on the sensu-client as well as on the checks definition.

Example sensu-client definition:

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


Example check definition:

```
{
  "checks": {
    "metric_cpu": {
      "command": "/opt/sensu/embedded/bin/ruby /path/to/script.rb",
      "interval": 20,
      "standalone": true,
      "type": "metric",
      "handlers": [
        "metrics"
      ],
      "tags": {
        "mytag": "xyz"
      }
    } 
  }
}
```

... will turn into the following tags for that point: **,environment=dev,application=myapp,hostname=my-app-in-env.domain.tld,mytag=xyz**

If both the client and the check tags have the same key, the one defined on the check will overwrite/win the merge.

#performance

The extension will buffer up points until it reaches the configured **buffer_size** length or **buffer_max_age**, and then post all the points in the buffer to InfluxDB. 
Depending on your load, you will want to tune these configurations to match your environment.

Example:
If you set the **buffer_size** to 1000, and you have a event-frequency of 100 per second, it will give you about a ten second lag before the data is available through the InfluxDB query API.

**buffer_size** / event-frequency = latency 

However, if you set the **buffer_max_age** to 5 seconds, it will flush the buffer each time it exeeds this limit.

I recommend testing different **buffer_size**s and **buffer_max_age**s depending on your environment and requirements.
