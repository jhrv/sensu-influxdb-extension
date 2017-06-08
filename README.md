# sensu-influxdb-extension

![Gem Version](https://badge.fury.io/rb/sensu-extensions-influxdb.svg)
![circle ci build status](https://circleci.com/gh/jhrv/sensu-influxdb-extension.png?circle-token=:circle-token)

[Sensu](https://sensuapp.org/) extension for sending metrics to [InfluxDB](https://influxdb.com/) using [line protocol](https://docs.influxdata.com/influxdb/latest/write_protocols/line_protocol_reference).

It handles both metrics on the graphite message format "key value timestamp\n" as well as line protocol directly by setting the extension in **proxy mode**. 

## How it works

For every sensu-event, it will grab the output and transform each line into a line protocol data point. The point will contain tags defined on the check and sensu client (optional).
It will buffer up points until it reaches the configured length or maximum age (see **buffer_size** and **buffer_max_age**), and then post the data directly to the [InfluxDB write endpoint](https://docs.influxdata.com/influxdb/latest/tools/api/#write).

Example line of graphite data-format ([metric_path] [value] [timestamp]\n):

will be transformed into the following data-point ([line protocol](https://influxdb.com/docs/v0.9/write_protocols/line.html))...

```
key_a[,<tags>] value=6996 1435216969\n...
```

## Proxy mode

If the extension is configured to be in proxy mode, it will skip the transformation step and assume that the data is valid [line protocol](https://docs.influxdata.com/influxdb/latest/write_protocols/line_protocol_reference).
It will not take into account any tags defined in the sensu-configuration.

## Getting started

1) Install the extension

```
sensu-install -e influxdb
```

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

### Full list of configuration options

| variable                     | default value         |
| ---------------------------- | --------------------- |
| hostname                     |       none (required) |
| port                         |                  8086 |
| database                     |       none (required) |
| proxy_mode                   |                 false |
| buffer_size                  |           100 (lines) |
| buffer_max_age               |          10 (seconds) |
| ssl                          |                 false |
| ssl_ca_file (\*)             |                  none |
| ssl_verify                   |                  true |
| precision                    |              s (\*\*) |
| retention_policy             |                  none |
| username                     |                  none |
| password                     |                  none |
| additional_handlers (\*\*\*) |                  none |

(\*) Optional file with trusted CA certificates  
(\*\*) s = seconds. Other valid options are n, u, ms, m, h. See [influxdb docs](https://influxdb.com/docs/v0.9/write_protocols/write_syntax.html) for more details  
(\*\*\*) Optional list of additional handler configurations (see below)

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

You should see the following output in the sensu-server logs if all is working correctly:

```
{"timestamp":"2015-06-21T13:37:04.256753+0200","level":"info","message":"influxdb-extension:
successfully initialized handler: hostname: ....
```

## Tags (optional)

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

The tags will be sorted alphabetically for InfluxDB performance, and tags with empty values will be skipped.

#### Event Output Tags

This extension already provides check level and client level tags and now can provide event output tags. This will help us reducing number of sensu checks and provide better flexibility and control.

Example -
Let's say we configured the sensu check output to be :

```
app.downloads.eventtags.platform.iOS 26 1476047752
app.downloads.eventtags.platform.android 52 1476047752
app.downloads.eventtags.platform.others 12 1476047752
```

The extension will split the output of the measurement on eventtags. Then it will slice the second part into tag key and values. From above example, the transformed output will be -
```
measurement = app.downloads, tags = platform => iOS , value = 26, timestamp = 1476047752 
measurement = app.downloads, tags = platform => android , value = 52, timestamp = 1476047752
measurement = app.downloads, tags = platform => others , value = 12, timestamp = 1476047752
```

You can create multiple tags also, for example :

```
app.downloads.eventtags.platform.iOS.device.iPad 92 1476047752
```
will be transformed to :
```
measurement = app.downloads, tags = platform => iOS;device => iPad , value = 92, timestamp = 1476047752 
```

The event output tags will be merged with client and check definition tags and sent to InfluxDB as usual.

## Multiple handlers

If you need to have multiple handlers, eg. for different precision, proxy mode, writing to different influx databases etc, this can be done by configuring **additional_handlers**:

```
{
  "influxdb-extension": {
    "hostname": "influxdb",
    "port": 8086,
    "database": "metrics",
    "username": "sensu",
    "password": "sensu",
    "buffer_size": 1000,
    "buffer_max_age": 10,
    "additional_handlers": ["events", "events_nano"]
  },
  "events": {
    "proxy_mode": true,
    "precision": "s"
  },
  "events_nano": {
    "proxy_mode": true,
    "precision": "n"
  }
}
```

Settings for the additional handlers will be merged with the **influxdb-extension** settings, so you only need to specify the settings you want to change for that handler.

Register the additional handlers:

```
"handlers": {
   ...
    "events": {
      "type": "set",
      "handlers": ["influxdb-extension"]
    },
    "events_nano": {
      "type": "set",
      "handlers": ["influxdb-extension"]
    }
    ...
 }

```

## Performance

The extension will buffer up points until it reaches the configured **buffer_size** length or **buffer_max_age**, and then post all the points in the buffer to InfluxDB. 
Depending on your load, you will want to tune these configurations to match your environment.

Example:
If you set the **buffer_size** to 1000, and you have a event-frequency of 100 per second, it will give you about a ten second lag before the data is available through the InfluxDB query API.

**buffer_size** / event-frequency = latency 

However, if you set the **buffer_max_age** to 5 seconds, it will flush the buffer each time it exeeds this limit.

I recommend testing different **buffer_size**s and **buffer_max_age**s depending on your environment and requirements.
