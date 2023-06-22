#!/usr/bin/env bash
QDISC_ID=
QDISC_HANDLE=
tc_init() {
    QDISC_ID=1
    QDISC_HANDLE="root handle $QDISC_ID:"
}
qdisc_del() {
    tc qdisc del dev "$1" root
}
qdisc_next() {
    QDISC_HANDLE="parent $QDISC_ID: handle $((QDISC_ID+1)):"
    ((QDISC_ID++))
}
# Following calls to qdisc_netm and qdisc_tbf are chained together
# http://man7.org/linux/man-pages/man8/tc-netem.8.html
qdisc_netm() {
    IF="$1"
    shift
    tc qdisc add dev "$IF" $QDISC_HANDLE netem $@
    qdisc_next
}
# http://man7.org/linux/man-pages/man8/tc-tbf.8.html
qdisc_tbf() {
    IF="$1"
    shift
    tc qdisc add dev "$IF" $QDISC_HANDLE tbf burst 5kb latency 50ms $@
    qdisc_next
} 
qdisc_netm_filter_ip() {
    IF="$1"
    shift
    tc qdisc add dev "$IF" $QDISC_HANDLE prio
    ID=1
    
    input="$@"
    input=$(echo "$input" | sed 's/, /,/g')
    input=$(echo "$input" | sed 's/: /:/g')

    IFS=',' read -ra addresses <<< "$input"
    for address in "${addresses[@]}"; do
        SUBQDISC_HANDLE="parent $QDISC_ID:$ID handle $((100+$ID)):"
        ip=$(echo "$address" | awk -F':' '{print $1}')
        details=$(echo "$address" | awk -F':' '{print $2}')
        #echo "IP: $ip"
        #echo "Details: $details"
        tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $details
        tc filter add dev "$IF" protocol ip parent $QDISC_ID:0 prio 1 u32 match ip src $ip flowid $QDISC_ID:$ID
        ((ID++))        
        done
    qdisc_next
}

