#!/bin/bash

set -xe
nodelabel="node-type=chatqna-opea"
nodeunlabel="node-type-"
namespace="default"
modelpath="/mnt/models"
mode=${MODE:-"tuned/with_rerank"}
example=${EXAMPLE:-"chatqna"}

function label() {
    echo "Label the node."

    label_nums=$1
    cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    node_count=$(kubectl get nodes --no-headers | wc -l)
    #cluster_node_names="satg-opea-4node-3 satg-opea-4node-0"

    # get control plane name
    cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o custom-columns=NAME:.metadata.name --no-headers)
    if [ -z "$cluster_control_plane_name" ]; then
        cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/master -o custom-columns=NAME:.metadata.name --no-headers)
    fi

    label_count=0
    for node_name in $cluster_node_names; do
        if [ "$node_name" == "$cluster_control_plane_name" ] && [ "$label_nums" -lt "$node_count" ]; then
            continue
        fi
        kubectl label nodes $node_name $nodelabel
        label_count=$((label_count+1))
        if [ "$label_count" -ge "$label_nums" ]; then
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
    num_gaudi=$1
    
    mpath="ChatQnA/benchmark/performance/$mode/"
    if [ "$num_gaudi" -eq 1 ]; then
        mpath+="single_gaudi"
    elif [ "$num_gaudi" -eq 2 ]; then
        mpath+="two_gaudi"
    elif [ "$num_gaudi" -eq 4 ]; then
        mpath+="four_gaudi"
    elif [ "$num_gaudi" -eq 8 ]; then
        mpath+="eight_gaudi"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    if [ ! -d $mpath ]; then
        echo "Directory $mpath does not exist."
        exit 1
    fi

    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#image: opea/\(.*\):latest#image: opea/\1:${IMAGE_TAG}#g" {} \;
    if [[ -n $IMAGE_REPO ]]; then
        find $mpath/ -name '*.yaml' -type f -exec sed -i "s#image: opea/*#image: ${IMAGE_REPO}/opea/#g" {} \;
    fi
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\${HF_TOKEN}#${HF_TOKEN}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#{HF_TOKEN}#${HF_TOKEN}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(LLM_MODEL_ID)#${LLM_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(EMBEDDING_MODEL_ID)#${EMBEDDING_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(RERANK_MODEL_ID)#${RERANK_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#g" {} \;
    #find $mpath/ -name '*.yaml' -type f -exec sed -i "s#namespace: default#namespace: ${namespace}#g" {} \;
    #find $mpath/ -name '*.yaml' -type f -exec sed -i "s#.default.svc#.${namespace}.svc#g" {} \;

    if kubectl get namespace "$namespace" > /dev/null 2>&1; then
        echo "Namespace '$namespace' already exists."
    else
        kubectl create ns $namespace
    fi
    kubectl apply -f $mpath/.
    wait_until_all_pod_ready $namespace 300s
    sleep 120s

    #Clean database
    db_host=$(kubectl -n $namespace get svc vector-db -o jsonpath='{.spec.clusterIP}')
    pip install redisvl
    rvl index info --host ${db_host} -i rag-redis
    rvl index delete --host ${db_host} -i rag-redis
    #Prepare dataset
    dataprep_host=$(kubectl -n $namespace get svc dataprep-svc -o jsonpath='{.spec.clusterIP}')
    cd ../GenAIEval/evals/benchmark/data
    if [[ $mode == *"without_rerank" ]]; then
        curl -X POST "http://${dataprep_host}:6007/v1/dataprep" \
           -H "Content-Type: multipart/form-data" \
           -F "files=@./upload_file_no_rerank.txt"
    else
        curl -X POST "http://${dataprep_host}:6007/v1/dataprep" \
           -H "Content-Type: multipart/form-data" \
           -F "files=@./upload_file.txt" \
           -F "chunk_size=3800"
    fi

}

function uninstallChatQnA() {
    echo "Uninstall ChatQnA."
    num_gaudi=$1

    path="ChatQnA/benchmark/performance/${mode}/"
    if [ "$num_gaudi" -eq 1 ]; then
        path+="single_gaudi"
    elif [ "$num_gaudi" -eq 2 ]; then
        path+="two_gaudi"
    elif [ "$num_gaudi" -eq 4 ]; then
        path+="four_gaudi"
    elif [ "$num_gaudi" -eq 8 ]; then
        path+="eight_gaudi"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    if [ ! -d $path ]; then
        echo "Directory $path does not exist."
        exit 1
    fi
    kubectl delete -f $path/.
    if [ "$namespace" != "default" ]; then
        kubectl delete ns $namespace
    fi
}

function generate_config(){
    echo "Generate benchmark config"
    num_gaudi=$1
    # under Validate folder
    input_path=".github/scripts/benchmark.yaml"
    output_path="../GenAIEval/evals/benchmark/benchmark.yaml"

    if [ "$num_gaudi" -eq 1 ]; then
        DEFAULT_USER_QUERIES="4, 8, 16, 640, 640, 640, 640, 640, 640"
    elif [ "$num_gaudi" -eq 2 ]; then
        DEFAULT_USER_QUERIES="4, 8, 16, 1280, 1280, 1280, 1280, 1280, 1280"
    elif [ "$num_gaudi" -eq 4 ]; then
        DEFAULT_USER_QUERIES="4, 8, 16, 2560, 2560, 2560, 2560, 2560, 2560"
    elif [ "$num_gaudi" -eq 8 ]; then
        DEFAULT_USER_QUERIES="4, 8, 16, 5120, 5120, 5120, 5120, 5120, 5120"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    CUSTOMIZE_QUERY_LIST=${USER_QUERIES:-$DEFAULT_USER_QUERIES}
    export USER_QUERIES=$CUSTOMIZE_QUERY_LIST
    envsubst < $input_path > $output_path

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
	echo "Usage: $0 --cordon --uncordon --label --unlabel --installChatQnA --uninstallChatQnA --generate_config --process_result_data"
}

OPTIONS="-h"
LONGOPTIONS="help,cordon,uncordon,label,unlabel,installChatQnA,uninstallChatQnA,generate_config,process_result_data"

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
    --cordon)
        cordon $2
        ;;
    --uncordon)
        uncordon
        ;;
    --label)
        label $2
        ;;
    --unlabel)
        unlabel
        ;;
    --installChatQnA)
        pushd $3
        installChatQnA $2
        popd
        ;;
    --uninstallChatQnA)
        pushd $3
        uninstallChatQnA $2
        popd
        ;;
    --generate_config)
        generate_config $2
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
