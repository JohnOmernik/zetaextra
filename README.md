<<<<<<< HEAD
# zetaextra
R&amp;D Packages for Zetago
-------------------------
These packages are for use in Zetago. 

To install on your Zeta cluster using zetago. 

- Ensure you have a Zeta cluste using https://github.com/JohnOmernik/zetago
- Install and follow directions
- From the zetago directory edit ./conf/package.conf
- Add the location of the zetaextra directory to ADD_PKG_LOC
=======
# Syslogger

Syslogger is a tool to help forward Rsyslog messages to [Apache Kafka](https://kafka.apache.org).

[Apache Kafka](https://kafka.apache.org) is a "high-performance, distributed messaging system" that is well suited for the collation of both business and system event data. Please see Jay Kreps' wonderful ["The Log: What every software engineer should know about real-time data's unifying abstraction"](http://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) for more information.

Syslogger will help you forward syslog messages to Kafka. Messages are forwarded from [rsyslog](http://www.rsyslog.com/) over a TCP connection to syslogger. Rsyslog already has a bunch of stuff to make forwarding messages as reliable as possible, handling back-pressure and writing queued messages to disk etc. For more information please see ["Reliable Forwarding of syslog Messages with Rsyslog"](http://www.rsyslog.com/doc/rsyslog_reliable_forwarding.html).

## Design
Syslogger tries to be a good Rsyslog citizen by offloading as much responsibility for handling failure to Rsyslog. 

Reliability is achieved (as much as possible when using just TCP) by synchronously sending messages to Kafka: we put as much back-pressure onto Rsyslog as possible in the event of there being a problem or delay in forwarding messages to Kafka.

Syslogger starts a TCP listener, by default, on port 1514. It also attempts to connect to ZooKeeper to retrieve the connection details for the Kafka brokers. Metrics are collected using [go-metrics](https://github.com/rcrowley/go-metrics).

## Building
Syslogger uses ZooKeeper so you'll need both the ZooKeeper library and headers available on your system.

To build on OSX (assuming you install ZooKeeper with Homebrew) you'll need:

    $ export CGO_CFLAGS='-I/usr/local/include/zookeeper'
    $ export CGO_LDFLAGS='-L/usr/local/lib'
    
And then...

    $ export GOPATH=$(pwd)
    $ export GO15VENDOREXPERIMENT=1
    $ go install syslogger

## Configuring Rsyslog
It's worth reading the Rsyslog documentation to make sure you configure Rsyslog according to your environment. If you just want to see stuff flowing on your development machine the following should suffice:

    $ActionQueueType LinkedList
    $ActionResumeRetryCount -1
    $ActionQueueFileName /tmp/syslog_queue
    $ActionQueueMaxFileSize 500M
    *.* @@localhost:1234
>>>>>>> 4c577f212deccaffaab7eeb418cc025c5d0972c5
