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
qdisc_filter_flow() {
    IF="$1"
    shift
    tc qdisc add dev "$IF" $QDISC_HANDLE prio
    echo "tc qdisc add dev "$IF" $QDISC_HANDLE prio"
    filter_parent_id=$QDISC_ID
    ID=1
    PARENT_ID="$QDISC_ID"
    input="$@"
    input=$(echo "$input" | sed 's/, /,/g')
    input=$(echo "$input" | sed 's/: /:/g')
    echo "hello"
    echo $input

    IFS=',' read -ra addresses <<< "$input"
    echo ${addresses[0]}
    echo ${addresses[1]}
    for address in "${addresses[@]}"; do
        flow=$(echo "$address" | awk -F':' '{print $1}')
        details=$(echo "$address" | awk -F':' '{print $2}')
        echo "Flow: $flow"
        echo "Details: $details"
        tbf_details="$(echo "$details" | grep -oP 'rate\s+\S+' || echo 'none')"
        echo "Rate details: $tbf_details"
        SUBQDISC_HANDLE="parent $PARENT_ID:$ID handle $(($QDISC_ID+1)):"
        filter_flow_id="$PARENT_ID:$ID"
        ((QDISC_ID++))
        if [[ "$tbf_details" != "none" ]]; then
            netem_details=$(echo "$details" | sed "s/$tbf_details//")
            if [[ "$netem_details" == "" ]]; then
                netem_details=$(echo "loss 0%")
            fi
            echo "Delay/Loss details: $netem_details"
            echo "tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $netem_details"
            tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $netem_details
            

            SUBQDISC_HANDLE2="parent $(($QDISC_ID)) handle $(($QDISC_ID+1)):"
            ((QDISC_ID++))
            echo "tc qdisc add dev "$IF" $SUBQDISC_HANDLE2 tbf burst 5kb latency 50ms $tbf_details"
            tc qdisc add dev "$IF" $SUBQDISC_HANDLE2 tbf burst 5kb latency 50ms $tbf_details
        else
            netem_details="$details"
            echo "Delay/Loss details: $netem_details"
            echo "tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $netem_details"
            tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $netem_details
            
        fi
        #echo "tc qdisc add dev "$IF" $SUBQDISC_HANDLE netem $netem_details"
        #tc filter add dev "$IF" protocol ip parent $QDISC_ID:0 prio 1 u32 match ip src $ip flowid $QDISC_ID:$ID
        IFS="-" read -r srcIP dstIP srcport dstport protocol <<< "$flow"

        priority=2
        match_lines=""

        # Check if fields are wildcards
        if [[ $srcIP != "*" ]]; then
        match_lines+="match ip src $srcIP "
        else
        ((priority+=5))
        fi

        if [[ $dstIP != "*" ]]; then
        match_lines+="match ip dst $dstIP "
        else
        ((priority+=3))
        fi

        if [[ $srcport != "*" ]]; then
        match_lines+="match ip sport $srcport 0xffff "
        else
        ((priority+=4))
        fi

        if [[ $dstport != "*" ]]; then
        match_lines+="match ip dport $dstport 0xffff "
        else
        ((priority+=2))
        fi

        if [[ $protocol != "*" ]]; then
        match_lines+="match ip protocol $protocol 0xff"
        else
        ((priority+=1))
        fi

        echo "tc filter add dev "$IF" protocol ip parent $filter_parent_id:0 prio $priority u32 $match_lines flowid $filter_flow_id"
        tc filter add dev "$IF" protocol ip parent $filter_parent_id:0 prio $priority u32 $match_lines flowid $filter_flow_id
        
        ((ID++))        
        done
    qdisc_next
}

