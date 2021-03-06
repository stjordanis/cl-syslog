# CL-SYSLOG [![Build Status](https://travis-ci.org/mmaul/cl-syslog.svg?branch=master)](https://travis-ci.org/mmaul/cl-syslog)

Common Lisp interface to local and remote Syslog facilities.

FEATURES
========
 * Local sysloging implemented via foreign-function calls.
 * Remote syslog over UDP sockets.

DOCUMENTATION
=============
For UDP Syslog See udp-syslog.lisp documentation strings.
For local syslog see cl-syslog.lisp and variable.lisp.
Priorities and facilities documented in variable.lisp.

Examples
========
Local Syslog Example:
    * (require :cl-syslog)
      
    * (syslog:log "myprog" :local7 :info "this is the message")
   "this is the message"

    * (syslog:log "myprog" :local7 :info "this is the message" 
        syslog:+log-pid+)
   "this is the message"

    * (syslog:log "myprog" :local7 :info "this is the message" 
        (+ syslog:+log-pid+ syslog:+log-cons+))
    "this is the message"
 
Then look in your /var/log/messages or other location if you have
tweaked your /etc/syslog.conf.

Remote Syslog Example:
    (require :cl-syslog)
    ;; Create global logger
    (syslog.udp:udp-logger "127.0.0.1" 514)

    ;; Log a message
    ;; (Note: the log function is signature compatible with cl-syslog:log)
    (syslog.udp:log "MyApp" :local7 :info "this is the message")

    ;; Log using a transient logger along with ulog function
    (syslog-udp:ulog "this is the message" :logger 
      (syslog-udp:udp-logger "192.168.0.5" 514 :transient t))

    ;; Log with prirority
    (syslog.udp:ulog "this is an error" :pri :err)

