Must Gather Review
===========================================

DESCRIPTION
------------

The purpose of this script is to quickly search logs for known issues in an OpenShift must-gather.

PREREQUISITES
------------

LINUX:
This script requires [yq](https://github.com/kislyuk/yq) and jq. yq can be obtained from the github page or installed by running `pip3 install yq` and the jq package is avaiable in all common Linux Distributions.

MACOS:
The macos script requires [yq](https://github.com/kislyuk/yq), [gnu grep](https://formulae.brew.sh/formula/grep), [bc from brew](https://formulae.brew.sh/formula/bc#default), and [jq from brew](https://formulae.brew.sh/formula/jq#default).
macos includes bc, but during testings I found that calculations of `etcd` times were up to 50% faster using bc from brew.

CONTRIBUTING
------------

There are three ways to contribute to this script by either adding a string to an additional function, adding a search of a new pod in the same function/namespace, or adding a new function.

To add an additional string please update the relevant array in the function, e.g. etcd_etcd_errors_arr.

To add an additional search in an existing function please use the following example:

```bash
# <container_name> pod errors
<function/namespace_name>_<container_name>_errors_arr=("string_1" "string_2")

for i in namespaces/openshift-<namespace_name>/pods/<podname_*>/<container_name>/<container_name>/logs/current.log; do
  for val in "${<function/namespace_name>_<container_name>_errors_arr[@]}"; do
    if [[ "$(grep -wc "$val" "$i")" != "0" ]]; then
     etcd_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(grep -wc "$val" "$i")")
    fi
  done
done
```

To add a new function use the following example. If you are having issues with the output please reach out to the repository maintainers for assistance.

```bash
<function/namespace_name>(){

# set column names
<function/namespace_name>_output_arr=("NAMESPACE|POD|ERROR|COUNT")

# <container_name> pod errors
<function/namespace_name>_<container_name>_errors_arr=("string_1" "string_2")

for i in namespaces/openshift-<namespace_name>/pods/<podname_*>/<container_name>/<container_name>/logs/current.log; do
  for val in "${<function/namespace_name>_<container_name>_errors_arr[@]}"; do
    if [[ "$(grep -wc "$val" "$i")" != "0" ]]; then
     etcd_output_arr+=("$(echo "$i" | awk -F/ '{ print $2 }')|$(echo "$i" | awk -F/ '{ print $4 }')|$(echo "$val")|$(grep -wc "$val" "$i")")
    fi
  done
done
done

printf '%s\n' "${<function/namespace_name>_output_arr[@]}" | column -t -s '|'
printf "\n"

unset <function/namespace_name>_output_arr

}
```

INSTALLATION
------------
* Copy mg-review.sh to a location inside of your $PATH

USAGE
------------

```bash
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
```

SAMPLE OUTPUT
------------

```bash
$ mg-review.sh --all
NAMESPACE       POD                      ERROR                                 COUNT
openshift-etcd  etcd-ocp-85wpv-master-0  took too long                         2331
openshift-etcd  etcd-ocp-85wpv-master-0  local node might have slow network    6
openshift-etcd  etcd-ocp-85wpv-master-0  elected leader                        1
openshift-etcd  etcd-ocp-85wpv-master-0  lost leader                           1
openshift-etcd  etcd-ocp-85wpv-master-1  took too long                         14177
openshift-etcd  etcd-ocp-85wpv-master-1  local node might have slow network    14
openshift-etcd  etcd-ocp-85wpv-master-1  elected leader                        7
openshift-etcd  etcd-ocp-85wpv-master-1  lost leader                           6
openshift-etcd  etcd-ocp-85wpv-master-1  failed to send out heartbeat on time  4310
openshift-etcd  etcd-ocp-85wpv-master-2  took too long                         10008
openshift-etcd  etcd-ocp-85wpv-master-2  local node might have slow network    8
openshift-etcd  etcd-ocp-85wpv-master-2  elected leader                        9
openshift-etcd  etcd-ocp-85wpv-master-2  lost leader                           8
openshift-etcd  etcd-ocp-85wpv-master-2  failed to send out heartbeat on time  484

Stats about last 500 etcd 'took long' messages: etcd-ocp4-85wpv-master-0
	Max: 1393.604461ms
	Min: 200.102143ms
	Avg: 361ms
	Expected: 200ms

Stats about last 500 etcd 'took long' messages: etcd-ocp4-85wpv-master-1
	Max: 1402.816156ms
	Min: 200.220565ms
	Avg: 327ms
	Expected: 200ms

Stats about last 500 etcd 'took long' messages: etcd-ocp4-85wpv-master-2
	Max: 5749.69575ms
	Min: 200.196156ms
	Avg: 572ms
	Expected: 200ms

etcd DB Compaction times: etcd-ocp4-85wpv-master-0
	Max: 453.066099ms
	Min: 165.595496ms
	Avg: 182ms

etcd DB Compaction times: etcd-ocp4-85wpv-master-1
	Max: 548.300888ms
	Min: 164.605164ms
	Avg: 182ms

etcd DB Compaction times: etcd-ocp4-85wpv-master-2
	Max: 453.216023ms
	Min: 166.309408ms
	Avg: 183ms

NAMESPACE                 POD                                ERROR                            COUNT
openshift-kube-apiserver  kube-apiserver-ocp4-85wpv-master-0  timeout or abort while handling  1
openshift-kube-apiserver  kube-apiserver-ocp4-85wpv-master-1  timeout or abort while handling  264
openshift-kube-apiserver  kube-apiserver-ocp4-85wpv-master-2  timeout or abort while handling  30

NAMESPACE                 POD                                          ERROR                                                                        COUNT
openshift-kube-scheduler  openshift-kube-scheduler-ocp4-85wpv-master-2  net/http: request canceled (Client.Timeout exceeded while awaiting headers)  1

NAMESPACE      POD                ERROR                   COUNT
openshift-dns  dns-default-66kzc  i/o timeout             171
openshift-dns  dns-default-66kzc  client connection lost  11
openshift-dns  dns-default-8s8md  i/o timeout             7119
openshift-dns  dns-default-gtzbq  i/o timeout             6201
openshift-dns  dns-default-gtzbq  client connection lost  3
openshift-dns  dns-default-lns6x  i/o timeout             20
openshift-dns  dns-default-q6wql  i/o timeout             1
openshift-dns  dns-default-q6wql  client connection lost  3
openshift-dns  dns-default-s6pnv  client connection lost  3

NAMESPACE          POD                              ERROR                                         COUNT
openshift-ingress  router-default-85fdd489f9-mnw5w  unable to find service                        2
openshift-ingress  router-default-85fdd489f9-mnw5w  Failed to make webhook authenticator request  3
openshift-ingress  router-default-85fdd489f9-zwjlm  unable to find service                        2
openshift-ingress  router-default-85fdd489f9-zwjlm  Failed to make webhook authenticator request  1

NAMESPACE                 POD                               ERROR                                                 COUNT
openshift-authentication  oauth-openshift-85b74fff74-fxrbb  the server is currently unable to handle the request  1
openshift-authentication  oauth-openshift-85b74fff74-gwrzn  the server is currently unable to handle the request  2
openshift-authentication  oauth-openshift-85b74fff74-gwrzn  Client.Timeout exceeded while awaiting headers        1
openshift-authentication  oauth-openshift-85b74fff74-zqgq5  the server is currently unable to handle the request  1

NAMESPACE                          POD                                         ERROR                                                 COUNT
openshift-kube-controller-manager  kube-controller-manager-ocp-85wpv-master-2  the server is currently unable to handle the request  104

Total Unsigned CSRs: 49
```

AUTHOR
------
Morgan Peterman
