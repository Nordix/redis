source tests/support/benchmark.tcl


proc cmdstat {cmd} {
    return [cmdrstat $cmd r]
}

start_server {tags {"benchmark"}} {
    start_server {} {
        set master_host [srv 0 host]
        set master_port [srv 0 port]

        test {benchmark: set,get} {
            r config resetstat
            r flushall
            set cmd [redisbenchmark $master_host $master_port "-c 5 -n 10 -e -t set,get"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            assert_match  {*calls=10,*} [cmdstat set]
            assert_match  {*calls=10,*} [cmdstat get]
            # assert one of the non benchmarked commands is not present
            assert_match  {} [cmdstat lrange]
        }

        test {benchmark: full test suite} {
            r config resetstat
            set cmd [redisbenchmark $master_host $master_port "-c 10 -n 100 -e"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            # ping total calls are 2*issued commands per test due to PING_INLINE and PING_MBULK
            assert_match  {*calls=200,*} [cmdstat ping]
            assert_match  {*calls=100,*} [cmdstat set]
            assert_match  {*calls=100,*} [cmdstat get]
            assert_match  {*calls=100,*} [cmdstat incr]
            # lpush total calls are 2*issued commands per test due to the lrange tests
            assert_match  {*calls=200,*} [cmdstat lpush]
            assert_match  {*calls=100,*} [cmdstat rpush]
            assert_match  {*calls=100,*} [cmdstat lpop]
            assert_match  {*calls=100,*} [cmdstat rpop]
            assert_match  {*calls=100,*} [cmdstat sadd]
            assert_match  {*calls=100,*} [cmdstat hset]
            assert_match  {*calls=100,*} [cmdstat spop]
            assert_match  {*calls=100,*} [cmdstat zadd]
            assert_match  {*calls=100,*} [cmdstat zpopmin]
            assert_match  {*calls=400,*} [cmdstat lrange]
            assert_match  {*calls=100,*} [cmdstat mset]
            # assert one of the non benchmarked commands is not present
            assert_match {} [cmdstat rpoplpush]
        }

        test {benchmark: multi-thread set,get} {
            r config resetstat
            r flushall
            set cmd [redisbenchmark $master_host $master_port "--threads 10 -c 5 -n 10 -e -t set,get"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            assert_match  {*calls=10,*} [cmdstat set]
            assert_match  {*calls=10,*} [cmdstat get]
            # assert one of the non benchmarked commands is not present
            assert_match  {} [cmdstat lrange]

            # ensure only one key was populated
            assert_match  {1} [scan [regexp -inline {keys\=([\d]*)} [r info keyspace]] keys=%d]
        }

        test {benchmark: pipelined full set,get} {
            r config resetstat
            r flushall
            set cmd [redisbenchmark $master_host $master_port "-P 5 -c 10 -n 10010 -e -t set,get"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            assert_match  {*calls=10010,*} [cmdstat set]
            assert_match  {*calls=10010,*} [cmdstat get]
            # assert one of the non benchmarked commands is not present
            assert_match  {} [cmdstat lrange]

            # ensure only one key was populated
            assert_match  {1} [scan [regexp -inline {keys\=([\d]*)} [r info keyspace]] keys=%d]
        }

        test {benchmark: arbitrary command} {
            r config resetstat
            r flushall
            set cmd [redisbenchmark $master_host $master_port "-c 5 -n 150 -e INCRBYFLOAT mykey 10.0"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            assert_match  {*calls=150,*} [cmdstat incrbyfloat]
            # assert one of the non benchmarked commands is not present
            assert_match  {} [cmdstat get]

            # ensure only one key was populated
            assert_match  {1} [scan [regexp -inline {keys\=([\d]*)} [r info keyspace]] keys=%d]
        }

        test {benchmark: keyspace length} {
            r flushall
            r config resetstat
            set cmd [redisbenchmark $master_host $master_port "-r 50 -t set -n 1000"]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            assert_match  {*calls=1000,*} [cmdstat set]
            # assert one of the non benchmarked commands is not present
            assert_match  {} [cmdstat get]

            # ensure the keyspace has the desired size
            assert_match  {50} [scan [regexp -inline {keys\=([\d]*)} [r info keyspace]] keys=%d]
        }

        # tls specific tests
        if {$::tls} {
            test {benchmark: specific tls-ciphers} {
                r flushall
                r config resetstat
                set cmd [redisbenchmark $master_host $master_port "-r 50 -t set -n 1000 --tls-ciphers \"DEFAULT:-AES128-SHA256\""]
                if {[catch { exec {*}$cmd } error]} {
                    set first_line [lindex [split $error "\n"] 0]
                    puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                    fail "redis-benchmark non zero code. first line: $first_line"
                }
                assert_match  {*calls=1000,*} [cmdstat set]
                # assert one of the non benchmarked commands is not present
                assert_match  {} [cmdstat get]
            }

            test {benchmark: specific tls-ciphersuites} {
                r flushall
                r config resetstat
                set ciphersuites_supported 1
                set cmd [redisbenchmark $master_host $master_port "-r 50 -t set -n 1000 --tls-ciphersuites \"TLS_AES_128_GCM_SHA256\""]
                if {[catch { exec {*}$cmd } error]} {
                    set first_line [lindex [split $error "\n"] 0]
                    if {[string match "*Invalid option*" $first_line]} {
                        set ciphersuites_supported 0
                        if {$::verbose} {
                            puts "Skipping test, TLSv1.3 not supported."
                        }
                    } else {
                        puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                        fail "redis-benchmark non zero code. first line: $first_line"
                    }
                }
                if {$ciphersuites_supported} {
                    assert_match  {*calls=1000,*} [cmdstat set]
                    # assert one of the non benchmarked commands is not present
                    assert_match  {} [cmdstat get]
                }
            }
        }

        # Measure time of trimming
        # HEADSUP:
        # - Number of requests is to high to be allowed in regression.
        # - Remove printouts
        test {benchmark: xtrim} {
            r select 0
            r flushall
            r config resetstat
            r config set stream-node-max-entries 100

            # Add elements to stream
            set cmd [redisbenchmark $master_host $master_port "-n 1000000 -e XADD mystream * FIELD VALUE"]
            set time_start [clock clicks -milliseconds]
            if {[catch { exec {*}$cmd } error]} {
                set first_line [lindex [split $error "\n"] 0]
                puts [colorstr red "redis-benchmark non zero code. first line: $first_line"]
                fail "redis-benchmark non zero code. first line: $first_line"
            }
            set time_taken [expr [clock clicks -milliseconds] - $time_start]
            puts "Adding 1000000 elements takes: $time_taken ms"

            assert_match {*calls=1000000,*} [cmdstat xadd]
            assert_match {1000000} [r XLEN mystream]

            # Perform the XTRIM
            set tt [time {r XTRIM mystream MAXLEN ~ 10}]
            puts "Trim takes: $tt"
            assert_match {*calls=1,*} [cmdstat xtrim]
            assert_match {100} [r XLEN mystream]
            # puts [r XINFO STREAM mystream]

            # Trigger trimming by adding to stream
            set tt [time {r XADD mystream * "field-last" "value-last"}]
            puts "XADD takes: $tt"
            puts [r XLEN mystream]
            puts [r XINFO STREAM mystream]
        }
    }
}
