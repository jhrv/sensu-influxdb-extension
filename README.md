sensu-influxdb-extension
========================

Sensu extension for sending metrics with graphite data-format to InfluxDB (>=0.9).

For each sensu-event it receives, it will transform each line of data into a InfluxDB **measurement** containing optional tags defined on the sensu client. It will buffer up measurements until it reaches the configured length, and then post the data directly to the InfluxDB REST-API using the [line protocol](https://influxdb.com/docs/v0.9/write_protocols/line.html).

Example line of graphite data-format ([metric_path] [value] [timestamp]\n):

```
key_a 1337 1435216969
```

will be transformed into the following measurement...

```
key_a[,<sensu_client_tags>] value=1337.0 1435216969000000000\n...
```

# Getting started

1) Add the *sensu-influxdb-extension.rb* to the sensu extensions folder (/etc/sensu/extensions)

2) Create your InfluxDB configuration for Sensu (or copy and edit *influxdb-extension.json.tmpl*) inside the sensu config folder (/etc/sensu/conf.d). 

```
{
    "influxdb-extension": {
        "hostname": "influxdb.mydomain.tld",
        "port": "8086",
        "database": "metrics",
        "username": "sensu",
        "password": "m3tr1c54l1f3",
        "ssl": false,
        "buffer_size": 100
    }
}
```

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

#tags 

If you want to tag your InfluxDB measurements (great for querying, as tags are indexed), you can define this on the sensu-client.

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

... will turn into the following tags for the measurements: **,environment=dev,application=myapp,hostname=my-app-in-env.domain.tld**

#timestamps

Timestamp will be converted to nanoseconds as this is assumed by InfluxDB unless otherwise specified. 
