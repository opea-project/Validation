#!/bin/bash

data_path="GenAIEval/evals/benchmark/data.txt"
server="localhost:8888"
concurrency=50
duration="30m"
test_type="chatqna"
github_base="~/testChatQnA"

function installStressTool() {
    python3 -m venv stressbenchmark_virtualenv
    source stressbenchmark_virtualenv/bin/activate
    pip install -r GenAIEval/requirements.txt
    pip install argparse requests transformers
}

function cordon() {
    echo "Cordon the node."

    no_cordon_nums=$1
    need_cordon_nums=$(kubectl get nodes | wc -l)-$no_cordon_nums
    if [[ $need_cordon_nums -le 0 ]]; then
        echo "No need to cordon nodes."
        return
    fi
    cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o custom-columns=NAME:.metadata.name --no-headers)

    if [ -z "$control_plane_node_name" ]; then
        cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/master -o custom-columns=NAME:.metadata.name --no-headers)
    fi

    cordoned_count=0
    for node_name in $cluster_node_names; do
        if [[ $node_name == $control_plane_node_name ]]; then
            continue
        fi
        kubectl cordon $node_name
        cordoned_count=$((cordoned_count + 1))
        if [[ $cordoned_count -ge $need_cordon_nums ]]; then
            break
        fi
    done
}

function uncordon() {
    echo "Uncordon the node."

    cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    for node_name in $cluster_node_names; do
        kubectl uncordon $node_name
    done
}

function installChatQnA() {
    echo "Install ChatQnA."
    num_gaudi=$1
    
    mpath="ChatQnA/benchmark/"
    if num_gaudi -eq 1; then
        mpath += "single_gaudi"
    elif num_gaudi -eq 2; then
        mpath += "two_gaudi"
    elif num_gaudi -eq 4; then
        mpath += "four_gaudi"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    if [ ! -d $mpath ]; then
        echo "Directory $mpath does not exist."
        exit 1
    fi

    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#image: opea/\(.*\):latest#image: opea/\1:${IMAGE_TAG}#g" {} \;
    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#image: opea/*#image: ${IMAGE_REPO}/opea/#g" {} \;
    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#\$(HF_TOKEN)#${HF_TOKEN}#g" {} \;
    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#\$(LLM_MODEL_ID)#${LLM_MODEL_ID}#g" {} \;
    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#\$(EMBEDDING_MODEL_ID)#${EMBEDDING_MODEL_ID}#g" {} \;
    find $mpath/* -name '*.yaml' -type f -exec sed -i "s#\$(RERANK_MODEL_ID)#${RERANK_MODEL_ID}#g" {} \;
    #find $mpath/* -name '*.yaml' -type f -exec sed -i "s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#g" {} \;
    kubectl apply -f $mpath/.
}

function uninstallChatQnA() {
    echo "Uninstall ChatQnA."
    num_gaudi=$1

    path="ChatQnA/benchmark/"
    if num_gaudi -eq 1; then
        path += "single_gaudi"
    elif num_gaudi -eq 2; then
        path += "two_gaudi"
    elif num_gaudi -eq 4; then
        path += "four_gaudi"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    if [ ! -d $path ]; then
        echo "Directory $path does not exist."
        exit 1
    fi
    kubectl delete -f $path/.
}

function stress_benchmark(){
    echo "Start stress benchmark."
}

function generate_config(){
    echo "Generate benchmark config"
    num_gaudi=$1
    # under Validate folder
    input_path=".github/scripts/benchmark.yaml"
    output_path="../GenAIEval/evals/benchmark/benchmark_${num_gaudi}.yaml"
    test_output_dir="/home/sdp/benchmark_output/node_${num_gaudi}"

    if num_gaudi -eq 1; then
        user_queries="4, 8, 16, 32, 64, 128, 256, 512"
    elif num_gaudi -eq 2; then
        user_queries="4, 8, 16, 32, 64, 128, 256, 512, 1024"
    elif num_gaudi -eq 4; then
        user_queries="4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    envsubst < $input_path > $output_path
}


# function four_gaudi_benchmark() {
#     echo "Running four gaudi benchmark."
#     cd $github_base
#     cordon 4
#     installChatQnA 4
#     stress_benchmark
#     uninstallChatQnA 4
#     uncordon
# }

# function two_gaudi_benchmark() {
#     echo "Running two gaudi benchmark."
#     cd $github_base
#     cordon 2
#     installChatQnA 2
#     stress_benchmark
#     uninstallChatQnA 2
#     uncordon
# }

# function single_gaudi_benchmark() {
#     echo "Running single gaudi benchmark."
#     cd $github_base
#     cordon 1
#     installChatQnA 1
#     stress_benchmark
#     uninstallChatQnA 1
#     uncordon
# }

function usage()
{
	echo "Usage: $0 --install_stress_tool --single_gaudi_benchmark --two_gaudi_benchmark --four_gaudi_benchmark"
}

OPTIONS="-h"
LONGOPTIONS="help,install_stress_tool,single_gaudi_benchmark,two_gaudi_benchmark,four_gaudi_benchmark"

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
    # --install_stress_tool)
    #     installStressTool
    #     exit 0
    #     ;;
    # --single_gaudi_benchmark)
    #     single_gaudi_benchmark
    #     exit 0
    #     ;;
    # --two_gaudi_benchmark)
    #     two_gaudi_benchmark
    #     exit 0
    #     ;;
    # --four_gaudi_benchmark)
    #     four_gaudi_benchmark
    #     exit 0
    #     ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
