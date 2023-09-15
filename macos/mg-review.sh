#!/bin/bash

run() {

  case "$1" in
    --all)
      all
      ;;
    --events)
      events $2
      ;;
    --auth)
      auth
      ;;
    --etcd)
      etcd
      ;;
    --kubeapi)
      kube-api
      ;;
    --scheduler)
      scheduler
      ;;
    --dns)
      dns
      ;;
    --ingress)
      ingress
      ;;
    --sdn)
      sdn
      ;;
    --kubecontrol)
      kube_controller
      ;;
    --csr)
      csr
      ;;
    --podnetcheck)
      podnetcheck
      ;;
    --help)
      show_help
      ;;
    *)
      show_help
      exit 0
  esac

}

show_help(){

cat  << ENDHELP
USAGE: $(basename "$0")
must-gather-review is a simple script which searches a must-gather for known
issues and reports the namespace, pod, and the count for the errors found.

Options:
  --all          Performs all options
  --events       Displays all events in a given namespace
  --etcd         Searches for known errors in the eoptions
  --kubeapi      Searches for known errors in the kube-apiserveoptions
  --scheduler    Searches for known errors in the openshift-kube-scheduler-* pods
  --dns          Searches for known errors in dns-default-* pods
  --ingress      Searches for known errors in router-default-* pods
  --sdn          Searches for known errors in sdn-* pods
  --kubecontrol  Searches for known errors in kube-controller-manager-* pods
  --auth         Searches for known errors in oauth-openshift-* pods
  --csr          Searches for and Prints total Pending CSRs
  --podnetcheck  Searches for and Prints PodNetworkConnectivityCheck errors
  --help         Shows this help message

ENDHELP

}

dep_check(){

if [ ! $(command -v jq) ]; then
  echo "jq not found. Please install jq."
  exit 1
fi

if [ ! $(command -v yq) ]; then
  echo "yq not found. Please install yq by running pip3 install yq"
  exit 1
fi

if [ ! $(command -v ggrep) ]; then
  echo "ggrep not found. Please install ggrep by running brew install grep"
  exit 1
fi

}

all(){

  etcd

  kube-api

  scheduler

  dns

  ingress

  sdn

  auth

  kube_controller

  csr

}

events(){

if [ -f "namespaces/$1/core/events.yaml" ]; then
  events_arr=("NODE|POD|TYPE|REASON|MESSAGE")
  for i in $(yq . namespaces/$1/core/events.yaml | jq -r '.items | keys[]'); do
    events_arr+=($(yq -r . namespaces/$1/core/events.yaml | jq -r "[(select(.items[$i] | select(.type == \"Warning\")) | .items[$i].source.host), (select(.items[$i] | select(.type == \"Warning\")) | .items[$i].involvedObject.name), (select(.items[$i] | select(.type == \"Warning\")) | .items[$i].type), (select(.items[$i] | select(.type == \"Warning\")) | .items[$i].reason), (select(.items[$i] | select(.type == \"Warning\")) | .items[$i].message)] | join (\"|\")" | sed 's/ /_/g'))
  done
else
  echo "Events missing for namespace: $1"
  exit 1
fi

if [ "${#events_arr[1]}" != 0 ]; then
  printf '%s\n' "${events_arr[@]}" | column -t -s '|'
  printf "\n"
else
  echo "No warnings found in namespace: $1"
  exit
fi

unset events_arr

}

etcd(){

#Check to make sure the openshift-etcd namespace exits
if [ ! -d "namespaces/openshift-etcd/pods/" ]; then
  echo -e "openshift-etcd not found.\n"
  return 1
fi

# set column names
etcd_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# etcd pod errors
etcd_etcd_errors_arr=("waiting for ReadIndex response took too long, retrying" "etcdserver: request timed out" "slow fdatasync" "\"apply request took too long\"" "\"leader failed to send out heartbeat on time; took too long, leader is overloaded likely from slow disk\"" "local no
de might have slow network" "elected leader" "lost leader" "wal: sync duration" "the clock difference against peer" "lease not found" "rafthttp: failed to read" "server is likely overloaded" "lost the tcp streaming" "sending buffer is full" "health errors")

for i in namespaces/openshift-etcd/pods/etcd*/etcd/etcd/logs/current.log; do
  for val in "${etcd_etcd_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     etcd_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#etcd_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${etcd_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset etcd_output_arr

for i in namespaces/openshift-etcd/pods/etcd*/etcd/etcd/logs/current*.log; do
    expected=$(ggrep -m1 'took too long.*expec' "$i" | ggrep -o "\{.*\}" | jq -r '."expected-duration"' 2>/dev/null)
    if ggrep 'took too long.*expec' "$i" > /dev/null 2>&1;
    then

      first=$(ggrep -m1 'took too long.*expec' "$i" 2>/dev/null | awk '{ print $1}')
      last=$(ggrep 'took too long.*expec' "$i" 2>/dev/null | tail -n1 | awk '{ print $1}')

      for x in $(ggrep 'took too long.*expec' "$i" | ggrep -Ev 'leader|waiting for ReadIndex response took too long' | ggrep -o "\{.*\}"  | jq -r '.took' 2>/dev/null | ggrep -Ev 'T|Z' 2>/dev/null); do
        if [[ $x =~ [1-9]m[0-9] ]];
        then
          compact_min=$(echo "scale=2;$(echo $x | ggrep -Eo '[1-9]m' | sed 's/m//')*60000" | bc)
          compact_sec=$(echo "scale=2;$(echo $x | sed -E 's/[1-9]+m//' | ggrep -Eo '[1-9]?\.[0-9]+')*1000" | bc)
          compact_time=$(echo "scale=2;$compact_min + $compact_sec" | bc)
        elif [[ $x =~ [1-9]s ]];
        then
          compact_time=$(echo "scale=2;$(echo $x | sed 's/s//')*1000" | bc)
        else
          compact_time=$(echo $x | sed 's/ms//')
        fi
        median_arr+=(${compact_time})
      done
      printf "Stats about etcd 'took long' messages: $(echo "$i" | awk -F/ '{ print $4 }')\n"
      printf "\tFirst Occurance: ${first}\n"
      printf "\tLast Occurance: ${last}\n"
      printf "\tMaximum: $(echo ${median_arr[@]} | jq -s '{maximum:max}' | jq -r '.maximum')ms\n"
      printf "\tMinimum: $(echo ${median_arr[@]} | jq -s '{minimum:min}' | jq -r '.minimum')ms\n"
      printf "\tMedian: $(echo ${median_arr[@]} | jq -s '{median:(sort|if length%2==1 then.[length/2|floor]else[.[length/2-1,length/2]]|add/2|round end)}' | jq -r '.median')ms\n"
      printf "\tAverage: $(echo ${median_arr[@]} | jq -s '{average:(add/length|round)}' | jq -r '.average')ms\n"
      printf "\tExpected: ${expected}\n"
      printf "\n"

      unset median_arr
    fi
done

for i in namespaces/openshift-etcd/pods/etcd*/etcd/etcd/logs/current*.log; do
    expected=$(ggrep -m1 'slow fdatasync' "$i" | ggrep -o "\{.*\}" | jq -r '."expected-duration"' 2>/dev/null)
    if ggrep 'slow fdatasync' "$i" > /dev/null 2>&1;
    then

      first=$(ggrep -m1 'slow fdatasync' "$i" 2>/dev/null | awk '{ print $1}')
      last=$(ggrep 'slow fdatasync' "$i" 2>/dev/null | tail -n1 | awk '{ print $1}')

      for x in $(ggrep 'slow fdatasync' "$i" | ggrep -o "\{.*\}"  | jq -r '.took' 2>/dev/null); do
        if [[ $x =~ [1-9]m[0-9] ]];
        then
          compact_min=$(echo "scale=2;$(echo $x | ggrep -Eo '[1-9]m' | sed 's/m//')*60000" | bc)
          compact_sec=$(echo "scale=2;$(echo $x | sed -E 's/[1-9]+m//' | ggrep -Eo '[1-9]?\.[0-9]+')*1000" | bc)
          compact_time=$(echo "scale=2;$compact_min + $compact_sec" | bc)
        elif [[ $x =~ [1-9]s ]];
        then
          compact_time=$(echo "scale=2;$(echo $x | sed 's/s//')*1000" | bc)
        else
          compact_time=$(echo $x | sed 's/ms//')
        fi
        median_arr+=(${compact_time})
      done
      printf "Stats about etcd 'slow fdatasync' messages: $(echo "$i" | awk -F/ '{ print $4 }')\n"
      printf "\tFirst Occurance: ${first}\n"
      printf "\tLast Occurance: ${last}\n"
      printf "\tMaximum: $(echo ${median_arr[@]} | jq -s '{maximum:max}' | jq -r '.maximum')ms\n"
      printf "\tMinimum: $(echo ${median_arr[@]} | jq -s '{minimum:min}' | jq -r '.minimum')ms\n"
      printf "\tMedian: $(echo ${median_arr[@]} | jq -s '{median:(sort|if length%2==1 then.[length/2|floor]else[.[length/2-1,length/2]]|add/2|round end)}' | jq -r '.median')ms\n"
      printf "\tAverage: $(echo ${median_arr[@]} | jq -s '{average:(add/length|round)}' | jq -r '.average')ms\n"
      printf "\tExpected: ${expected}\n"
      printf "\n"

      unset median_arr
    fi
done

for i in namespaces/openshift-etcd/pods/etcd*/etcd/etcd/logs/current*.log; do
    if ggrep -m1 "finished scheduled compaction" "$i" | ggrep '"took"'  > /dev/null 2>&1;
    then
      for x in $(ggrep "finished scheduled compaction" "$i" | ggrep -o "\{.*\}" | jq -r '.took'); do
        if [[ $x =~ [1-9]m[0-9] ]];
        then
          compact_min=$(echo "scale=2;$(echo $x | ggrep -Eo '[1-9]m' | sed 's/m//')*60000" | bc)
          compact_sec=$(echo "scale=2;$(echo $x | sed -E 's/[1-9]+m//' | ggrep -Eo '[1-9]?\.[0-9]+')*1000" | bc)
          compact_time=$(echo "scale=2;$compact_min + $compact_sec" | bc)
        elif [[ $x =~ [1-9]s ]];
        then
          compact_time=$(echo "scale=2;$(echo $x | sed 's/s//')*1000" | bc)
        else
          compact_time=$(echo $x | sed 's/ms//')
        fi
        median_arr+=(${compact_time})
      done
      printf "etcd DB Compaction times: $(echo "$i" | awk -F/ '{ print $4 }')\n"
      printf "\tMaximum: $(echo ${median_arr[@]} | jq -s '{maximum:max}' | jq -r '.maximum')ms\n"
      printf "\tMinimum: $(echo ${median_arr[@]} | jq -s '{minimum:min}' | jq -r '.minimum')ms\n"
      printf "\tMedian: $(echo ${median_arr[@]} | jq -s '{median:(sort|if length%2==1 then.[length/2|floor]else[.[length/2-1,length/2]]|add/2|round end)}' | jq -r '.median')ms\n"
      printf "\tAverage: $(echo ${median_arr[@]} | jq -s '{average:(add/length|round)}' | jq -r '.average')ms\n"
      printf "\n"

      unset median_ar
    fi
done

}

kube-api(){

#Check to make sure the openshift-kube-apiserver namespace exits
if [ ! -d "namespaces/openshift-kube-apiserver/pods/" ]; then
  echo -e "openshift-kube-apiserver not found.\n"
  return 1
fi

# set column names
kubeapi_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# kube-apiserver pod errors
kubeapi_errors_arr=("timeout or abort while handling" "Failed calling webhook" "invalid bearer token, token lookup failed" "etcdserver: mvcc: required revision has been compacted")

for i in namespaces/openshift-kube-apiserver/pods/kube-apiserver-*/kube-apiserver/kube-apiserver/logs/current.log; do
  for val in "${kubeapi_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     kubeapi_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#kubeapi_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${kubeapi_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset kubeapi_output_arr

}

scheduler(){

#Check to make sure the openshift-kube-scheduler namespace exits
if [ ! -d "namespaces/openshift-kube-scheduler/pods/" ]; then
  echo -e "openshift-kube-scheduler not found.\n"
  return 1
fi

# set column names
scheduler_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# kube-scheduler pod errors
scheduler_errors_arr=("net/http: request canceled (Client.Timeout exceeded while awaiting headers)" "6443: connect: connection refused" "Failed to update lock: etcdserver: request timed out")

for i in namespaces/openshift-kube-scheduler/pods/openshift-kube-scheduler-*/kube-scheduler/kube-scheduler/logs/current.log; do
  for val in "${scheduler_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     scheduler_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#scheduler_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${scheduler_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset scheduler_output_arr

}

dns(){

#Check to make sure the openshift-dns namespace exits
if [ ! -d "namespaces/openshift-dns/pods/" ]; then
  echo -e "openshift-dns not found.\n"
  return 1
fi

# set column names
dns_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# dns pod errors
dns_errors_arr=("TLS handshake timeout" "i/o timeout" "connection reset by peer" "client connection lost" "no route to host" "connection refused")

for i in namespaces/openshift-dns/pods/dns-default-*/dns/dns/logs/current.log; do
  for val in "${dns_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     dns_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#dns_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${dns_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset dns_output_arr

}

ingress(){

#Check to make sure the openshift-ingress namespace exits
if [ ! -d "namespaces/openshift-ingress/pods/" ]; then
  echo -e "openshift-ingress not found.\n"
  return 1
fi

# set column names
ingress_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# router pod errors
ingress_errors_arr=("unable to find service" "error reloading router: exit status 1" "connection refused" "Failed to make webhook authenticator request")

for i in namespaces/openshift-ingress/pods/router-default-*/router/router/logs/current.log; do
  for val in "${ingress_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     ingress_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#ingress_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${ingress_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset ingress_output_arr

}

sdn(){

#Check to make sure the openshift-sdn namespace exits
if [ ! -d "namespaces/openshift-sdn/pods/" ]; then
  echo -e "openshift-sdn not found.\n"
  return 1
fi

# set column names
sdn_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# sdn pod errors
sdn_errors_arr=("connection refused" "an error on the server (\"\") has prevented the request from succeeding" "Failed to get local addresses during proxy sync" "the server has received too many requests and has asked us to try again later")

for i in namespaces/openshift-sdn/pods/sdn-*/sdn/sdn/logs/current.log; do
  for val in "${sdn_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     sdn_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#sdn_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${sdn_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset sdn_output_arr

}

auth(){

#Check to make sure the openshift-authentication namespace exits
if [ ! -d "namespaces/openshift-authentication/pods/" ]; then
  echo -e "openshift-authentication not found.\n"
  return 1
fi

# set column names
auth_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# oauth-openshift pod errors
auth_errors_arr=("the server is currently unable to handle the request" "Client.Timeout exceeded while awaiting headers")

for i in namespaces/openshift-authentication/pods/oauth-openshift-*/oauth-openshift/oauth-openshift/logs/current.log; do
  for val in "${auth_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     auth_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#auth_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${auth_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset auth_output_arr

}

kube_controller(){

#Check to make sure the openshift-authekube-controller-managerntication namespace exits
if [ ! -d "namespaces/openshift-kube-controller-manager/pods/" ]; then
  echo -e "openshift-kube-controller-manager not found.\n\n"
  return 1
fi

# set column names
kube_controller_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# kube-controller-manager pod errors
kube_controller_errors_arr=("the server is currently unable to handle the request")

for i in namespaces/openshift-kube-controller-manager/pods/kube-controller-manager-*/kube-controller-manager/kube-controller-manager/logs/current.log; do
  for val in "${kube_controller_errors_arr[@]}"; do
    if [[ "$(ggrep -wc "$val" "$i")" != "0" ]]; then
     kube_controller_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(ggrep -wc "$val" "$i")")
    fi
  done
done

if [ "${#kube_controller_output_arr[1]}" != 0 ]; then
  printf '%s\n' "${kube_controller_output_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset kube_controller_output_arr

}

csr(){

#Check to make sure the openshift-authekube-controller-managerntication namespace exits
if [ ! -d  cluster-scoped-resources/certificates.k8s.io/certificatesigningrequests/ ]; then
  echo -e "No CSRs found.\n\n"
  return 1
fi

# set column names
csr_arr=("NAME|CREATED_ON|REQUESTOR")

for i in $(ls cluster-scoped-resources/certificates.k8s.io/certificatesigningrequests/*.yaml); do
  csr_arr+=("$(yq . "$i" | jq -r 2>/dev/null '[select(.status == {}) | .metadata.name, .metadata.creationTimestamp, .spec.username] | join("|")')")
done

#Subtract one line for true count
csr_total=$(( ${#csr_arr[@]} - 1 ))
printf "Total Unsigned CSRs: ${csr_total}\n"

}

podnetcheck(){

#Check to make sure the podnetworkconnectivitychecks.yaml file exits
if [ ! -d  pod_network_connectivity_check/ ]; then
  echo -e "PodNetworkConnectivityChecks not found.\n\n"
  return 1
fi

#Get Count
checks_count_len=$(yq -r . pod_network_connectivity_check/podnetworkconnectivitychecks.yaml | jq -r '.items | length')
check_count=$(( $checks_count_len - 1 ))

podnetcheck_arr=("NAME|DATE|ERROR")

#Get indexes with failures.
for i in $(seq 0 ${check_count}); do
    if yq -r . pod_network_connectivity_check/podnetworkconnectivitychecks.yaml | jq -r &>/dev/null ".items["$i"].status.failures[0].success | contains(false)"; then
      podnetcheckerrors_arr+=("$i")
    fi
done

#Get ouput from index with failures.
for i in ${podnetcheckerrors_arr[@]}; do
    podnetcheck_arr+=("$(yq -r . pod_network_connectivity_check/podnetworkconnectivitychecks.yaml | jq -r "[(.items["$i"] | select(.status.failures[0].success == false) | .metadata.name, .status.failures[0].time, .status.failures[0].message)] | join(\"|\")")")
done

if [ "${#podnetcheck_arr[1]}" != 0 ]; then
  printf '%s\n' "${podnetcheck_arr[@]}" | column -t -s '|'
  printf "\n"
fi

podnetoutage_arr=("NAME|START|END|MESSAGE|ERROR")

#Get indexes with failures.
for i in $(seq 0 ${check_count}); do
  if yq -r . pod_network_connectivity_check/podnetworkconnectivitychecks.yaml | jq -r &>/dev/null ".items[$i].status.outages[].message | contains(\"Connectivity\")"; then
    podnetoutageerrors_arr+=("$i")
  fi
done

#Get ouput from index with failures.
for i in ${podnetoutageerrors_arr[@]}; do
    podnetoutage_arr+=("$(yq -r . pod_network_connectivity_check/podnetworkconnectivitychecks.yaml | jq -r "[(.items["$i"] | .metadata.name, .status.outages[0].start, .status.outages[0].end, .status.outages[0].message, .status.outages[0].endLogs[-1].message)] | join(\"|\")")")
done

if [ "${#podnetoutage_arr[1]}" != 0 ]; then
  printf '%s\n' "${podnetoutage_arr[@]}" | column -t -s '|'
  printf "\n"
fi

unset podnetcheck_arr
unset podnetcheckerrors_arr
unset podnetoutage_arr
unset podnetoutageerrors_arr

}

main(){

#Check if in must-gather folder
if [ ! -d namespaces ]
then
    printf "WARNING: Namespaces not found.\n"
    printf "Please run $(basename "$0") from inside a must-gather folder.\n"
    printf "\n"
    show_help
    exit 1
fi

#Verify yq and jq are installed
dep_check

run "$1" "$2"

}

main "$@"