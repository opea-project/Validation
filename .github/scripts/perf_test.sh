#!/bin/bash

set -xe
nodelabel="node-type=opea-benchmark"
nodeunlabel="node-type-"
namespace="default"
mode=${MODE:-"with_rerank:tuned"}
example=${EXAMPLE:-"chatqna"}
node_num=${NODE_NUM:-1}
export LOAD_SHAPE=${LOAD_SHAPE:-"constant"}
export CONCURRENT_LEVEL=${CONCURRENT_LEVEL:-5}
export ARRIVAL_RATE=${ARRIVAL_RATE:-1.0}
export MODEL_DIR=${MODEL_DIR:-"/home/sdp/.cache/huggingface/hub"}

function label() {
    echo "Label the node."

    cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    node_count=$(kubectl get nodes --no-headers | wc -l)

    # get control plane name
    cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o custom-columns=NAME:.metadata.name --no-headers)
    if [ -z "$cluster_control_plane_name" ]; then
        cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/master -o custom-columns=NAME:.metadata.name --no-headers)
    fi

    label_count=0
    for node_name in $cluster_node_names; do
        if [ "$node_name" == "$cluster_control_plane_name" ] && [ "$node_num" -lt "$node_count" ]; then
            continue
        fi
        kubectl label nodes $node_name $nodelabel --overwrite
        label_count=$((label_count+1))
        if [ "$label_count" -ge "$node_num" ]; then
            break
        fi
    done
}

function unlabel() {
    echo "Unlabel the node."

    cluster_node_names=$(kubectl get nodes -l $nodelabel -o custom-columns=NAME:.metadata.name --no-headers)
    for node_name in $cluster_node_names; do
        kubectl label nodes $node_name $nodeunlabel
    done
}

function installChatQnA() {
    echo "Install ChatQnA."

    echo "Generate helm charts value for test."
    script_path="../GenAIExamples/ChatQnA/benchmark/performance/kubernetes/intel/gaudi"
    pushd $script_path
    cmd="python deploy.py --hf-token $HF_TOKEN --model-dir $MODEL_DIR --num-nodes $node_num --create-values-only"
    if [[ $mode == *"with_rerank"* ]]; then
        cmd="$cmd --with-rerank"
    fi
    if [[ $mode == *"tuned"* ]]; then
        cmd="$cmd --tuned"
    fi
    eval $cmd
    values_file=$(ls -t *-values.yaml | head -n 1)
    popd

    echo "Setting for development test."
    helm_charts_path="../GenAIInfra/helm-charts"
    hw_values_file="gaudi-values.yaml"
    cp $script_path/$values_file $helm_charts_path/chatqna
    pushd $helm_charts_path
    if [[ -n $IMAGE_REPO ]]; then
        find ./ -name '*value.yaml' -type f -exec sed -i "s#repository: opea/*#repository: ${IMAGE_REPO}/opea/#g" {} \;
    fi
    find ./ -name '*value.yaml' -type f -exec sed -i "s#tag: latest#tag: ${IMAGE_TAG}#g" {} \;
    #find ./ -name '*value.yaml' -type f -exec sed -i "s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#g" {} \;

    echo "Print helm chart values..."
    echo "cat chatqna/$hw_values_file..."
    cat chatqna/$hw_values_file
    echo "============"
    echo "cat chatqna/$values_file..."
    cat chatqna/$values_file
    echo "============"

    echo "Deploy ChatQnA."
    helm dependency update chatqna
    helm install chatqna chatqna -f chatqna/$hw_values_file -f chatqna/$values_file
    wait_until_all_pod_ready $namespace 300s
    popd
    sleep 120s

    echo "Setup benchmark database."
    db_host=$(kubectl -n $namespace get svc chatqna-redis-vector-db -o jsonpath='{.spec.clusterIP}')
    pip install redisvl
    rvl index info --host ${db_host} -i rag-redis
    rvl index delete --host ${db_host} -i rag-redis
    #Prepare dataset
    dataprep_host=$(kubectl -n $namespace get svc chatqna-data-prep -o jsonpath='{.spec.clusterIP}')
    pushd ../GenAIEval/evals/benchmark/data
    if [[ $mode == *"without_rerank"* ]]; then
        curl -X POST "http://${dataprep_host}:6007/v1/dataprep" \
           -H "Content-Type: multipart/form-data" \
           -F "files=@./upload_file_no_rerank.txt"
    else
        curl -X POST "http://${dataprep_host}:6007/v1/dataprep" \
           -H "Content-Type: multipart/form-data" \
           -F "files=@./upload_file.txt"
    fi
    popd
}

function uninstallChatQnA() {
    echo "Uninstall ChatQnA."
    helm uninstall chatqna
}

function generate_config(){
    echo "Generate benchmark config."
    # under Example folder
    input_path="ChatQnA/benchmark/performance/kubernetes/intel/gaudi/benchmark.yaml"
    output_path="../GenAIEval/evals/benchmark/benchmark.yaml"

    single_node_user_queries=640
    test_loop=8
    user_queries=$((single_node_user_queries * node_num))
    DEFAULT_USER_QUERIES=$user_queries
    for ((i=1; i<test_loop; i++)); do
        DEFAULT_USER_QUERIES="$DEFAULT_USER_QUERIES, $user_queries"
    done
    
    CUSTOMIZE_QUERY_LIST=${USER_QUERIES:-$DEFAULT_USER_QUERIES}
    export USER_QUERIES="[$CUSTOMIZE_QUERY_LIST]"

    export DEPLOYMENT_TYPE="k8s"
    export SERVICE_IP=None
    export SERVICE_PORT=None

    envsubst < $input_path > $output_path
    cat $output_path

    # Mark test cases
    TEST_CASES=${TEST_CASES:-"e2e"}
    IFS=',' read -r -a test_cases_array <<< "$TEST_CASES"
    for test_case in "${test_cases_array[@]}"; do
        test_case=$(echo "$test_case" | xargs)
        yq eval ".test_cases.${example}.${test_case}.run_test = true" -i "$output_path"
        if [ $? -ne 0 ]; then
            echo "Unknown test case: $test_case"
        fi
    done
}

function process_result_data() {
    TEST_CASES=${TEST_CASES:-"e2e"}
    IFS=',' read -r -a test_cases_array <<< "$TEST_CASES"
    for test_case in "${test_cases_array[@]}"; do
        test_case=$(echo "$test_case" | xargs)
        process_data $TEST_OUTPUT_DIR $test_case
    done
}
function process_data() {
    # under folder GenAIEval/evals/benchmark
    outputfolder=$1
    testcase=$2
    # generate bench_target
    if [[ "$testcase" == "e2e" ]]; then
        if [[ "$random_prompt" == true ]]; then
            bench_target="${example}bench"
        else
            bench_target="${example}fixed"
        fi
    else
        if [[ "$random_prompt" == true ]]; then
            bench_target="${testcase}bench"
        else
            bench_target="${testcase}fixed"
        fi
    fi
    # get the last three folder and generate csv file
    output_csv=${TEST_OUTPUT_DIR}/${testcase}_result.csv
    latest_folders=$(ls -td "$TEST_OUTPUT_DIR"/$bench_target*/ | head -n 3)
    print_header=true
    for folder in $latest_folders; do
        echo "Folder: $folder"
        stresscli/stresscli.py report --folder $folder --format csv --output ${folder}result.csv
        if [[ "$print_header" == true ]]; then
            head -n 1 "${folder}result.csv" > "$output_csv"
            print_header=false
            cp ${folder}1_testspec.yaml ${TEST_OUTPUT_DIR}/${testcase}_testspec.yaml
        fi
        sed -n '2p' "${folder}result.csv" >> "$output_csv"
    done
    # calculate with python script
    python process_csv.py "$output_csv"
}

function wait_until_all_pod_ready() {
  namespace=$1
  timeout=$2

  echo "Wait for all pods in NS $namespace to be ready..."
  pods=$(kubectl get pods -n $namespace --no-headers -o custom-columns=":metadata.name")
  # Loop through each pod
  echo "$pods" | while read -r line; do
    pod_name=$line
    kubectl wait --for=condition=Ready pod/${pod_name} -n $namespace --timeout=${timeout}
    if [ $? -ne 0 ]; then
      echo "Pod $pod_name is not ready after waiting for ${timeout}"
      echo "Pod $pod_name status:"
      kubectl describe pod $pod_name -n $namespace
      echo "Pod $pod_name logs:"
      kubectl logs $pod_name -n $namespace
      exit 1
    fi
  done
}


function usage()
{
	echo "Usage: $0 --label --unlabel --installChatQnA --uninstallChatQnA --generate_config --process_result_data"
}

OPTIONS="-h"
LONGOPTIONS="help,label,unlabel,installChatQnA,uninstallChatQnA,generate_config,process_result_data"

if [ $# -lt 1 ]; then
	usage
	# exit 1
fi
# Parse the options
PARSED_OPTIONS=$(getopt -o "$OPTIONS" --long "$LONGOPTIONS" -n "$0" -- "$@")

#Process the options
case "$1" in
    -h|--help)
        usage
        ;;
    --label)
        label
        ;;
    --unlabel)
        unlabel
        ;;
    --installChatQnA)
        installChatQnA
        ;;
    --uninstallChatQnA)
        uninstallChatQnA
        ;;
    --generate_config)
        pushd ../GenAIExamples
        generate_config
        popd
        ;;
    --process_result_data)
        process_result_data
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
