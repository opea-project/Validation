#!/bin/bash

source config.sh

function prepare() {
    pip install argparse requests transformers
}

function cordon() {
    echo "Cordon the node."

    no_cordon_nums=$1
    need_cordon_nums=$(kubectl get nodes | wc -l)-$no_cordon_nums
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

        # 如果已经 cordon 了指定数量的节点，则退出循环
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

function installGenAIExamples{
    echo "Install GenAIExamples."

    TARGET_DIR="GenAIExamples"
    REPO_URL="https://github.com/opea-project/GenAIExamples.git"

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Directory $TARGET_DIR does not exist. Cloning repository..."
        git clone $REPO_URL
    else
        echo "Directory $TARGET_DIR already exists."
    fi
}

function uninstallGenAIExamples{
    echo "Uninstall GenAIExamples."

    TARGET_DIR="GenAIExamples"
    if [ -d "$TARGET_DIR" ]; then
        echo "Directory $TARGET_DIR exists. Deleting..."
        rm -rf $TARGET_DIR
    else
        echo "Directory $TARGET_DIR does not exist."
    fi
}

function installChatQnA() {
    echo "Install ChatQnA."
    num_gaudi=$1
    
    path="GenAIExamples/ChatQnA/benchmark/"
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
    kubectl apply -f $path/.
}

function uninstallChatQnA() {
    echo "Uninstall ChatQnA."
    num_gaudi=$1

    path="GenAIExamples/ChatQnA/benchmark/"
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

function installGenAIEval(){
    echo "Install GenAIEval."

    TARGET_DIR="GenAIEval"
    REPO_URL="https://github.com/opea-project/GenAIEval.git"
    if [ ! -d "$TARGET_DIR" ]; then
        echo "Directory $TARGET_DIR does not exist. Cloning repository..."
        git clone $REPO_URL
    else
        echo "Directory $TARGET_DIR already exists."
    fi
}

function uninstallGenAIEval(){
    echo "Uninstall GenAIEval."

    TARGET_DIR="GenAIEval"
    if [ -d "$TARGET_DIR" ]; then
        echo "Directory $TARGET_DIR exists. Deleting..."
        rm -rf $TARGET_DIR
    else
        echo "Directory $TARGET_DIR does not exist."
    fi
}

function stress_benchmark(){
    echo "Start stress benchmark."

    python GenAIEval/evals/benchmark/stress_benchmark.py -f $data_path -s $server -c $concurrency -d $duration -t $test_type
}

function four_gaudi_benchmark() {
    echo "Running four gaudi benchmark."
    cordon 4
    installChatQnA 4
    stress_benchmark
    uninstallChatQnA 4
    uncordon
}

function two_gaudi_benchmark() {
    echo "Running two gaudi benchmark."
    cordon 2
    installChatQnA 2
    stress_benchmark
    uninstallChatQnA 2
    uncordon
}

function single_gaudi_benchmark() {
    echo "Running single gaudi benchmark."
    cordon 1
    installChatQnA 1
    stress_benchmark
    uninstallChatQnA 1
    uncordon
}

function start() {
    echo "Start."
    prepare
    mkdir -p $perf_test_dir
    cd $perf_test_dir
    installGenAIExamples
    installGenAIEval
}

function cleanup() {
    echo "Cleanup."
    rm -rf $perf_test_dir
}

function usage()
{
	echo "Usage: $0 --start --single_gaudi_benchmark --two_gaudi_benchmark --four_gaudi_benchmark --cleanup"
}

OPTIONS="-h"
LONGOPTIONS="help,start,single_gaudi_benchmark,two_gaudi_benchmark,four_gaudi_benchmark,cleanup"

if [ $# -lt 1 ]; then
	usage
	# exit 1
fi
# Parse the options
PARSED_OPTIONS=$(getopt -o "$OPTIONS" --long "$LONGOPTIONS" -n "$0" -- "$@")
eval set -- "$PARSED_OPTIONS"
#Process the options

while true; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--single_gaudi_benchmark)
			single_gaudi_benchmark
			exit 0
			;;
		--two_gaudi_benchmark)
			two_gaudi_benchmark
			exit 0
			;;
        --four_gaudi_benchmark)
			four_gaudi_benchmark
			exit 0
			;;
        --cleanup)
            cleanup
            exit 0
            ;;
        --start)
            start
            exit 0
            ;;
		--)
			shift
			break
			;;
		*)
			echo "Unknown option: $1"
			usage
			exit 1
			;;
	esac
done