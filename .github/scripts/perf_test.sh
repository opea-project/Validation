#!/bin/bash

nodelabel="node-type=chatqna-opea"
nodeunlabel="node-type-"
namespace="default"
modelpath="/mnt/models"

function cordon() {
    echo "Cordon the node."

    no_cordon_nums=$1
    need_cordon_nums=$(kubectl get nodes | wc -l)-$no_cordon_nums
    if [[ $need_cordon_nums -le 0 ]]; then
        echo "No need to cordon nodes."
        return
    fi
    #cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    cluster_node_names="satg-opea-4node-3"
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

function label() {
    echo "Label the node."

    label_nums=$1
    #cluster_node_names=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    cluster_node_names="satg-opea-4node-3"

    # get control plane name
    cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o custom-columns=NAME:.metadata.name --no-headers)
    if [ -z "$control_plane_node_name" ]; then
        cluster_control_plane_name=$(kubectl get nodes -l node-role.kubernetes.io/master -o custom-columns=NAME:.metadata.name --no-headers)
    fi

    label_count=0
    for node_name in $cluster_node_names; do
        if [ $node_name == $control_plane_node_name ] && [ $label_nums -lt 4 ]; then
            continue
        fi
        kubectl label nodes $node_name $nodelabel
        cordoned_count=$((cordoned_count + 1))
        if [ $cordoned_count -ge $need_cordon_nums ]; then
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
    
    mpath="ChatQnA/benchmark/"
    if [ "$num_gaudi" -eq 1 ]; then
        mpath+="single_gaudi"
    elif [ "$num_gaudi" -eq 2 ]; then
        mpath+="two_gaudi"
    elif [ "$num_gaudi" -eq 4 ]; then
        mpath+="four_gaudi"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    if [ ! -d $mpath ]; then
        echo "Directory $mpath does not exist."
        exit 1
    fi

    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#image: opea/\(.*\):latest#image: opea/\1:${IMAGE_TAG}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#image: opea/*#image: ${IMAGE_REPO}/opea/#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#{HF_TOKEN}#${HF_TOKEN}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(HF_TOKEN)#${HF_TOKEN}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(LLM_MODEL_ID)#${LLM_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(EMBEDDING_MODEL_ID)#${EMBEDDING_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#\$(RERANK_MODEL_ID)#${RERANK_MODEL_ID}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#/home/sdp/cesg#${modelpath}#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#tei_gaudi:rerank#${IMAGE_REPO}/opea/tei_gaudi:rerank#g" {} \;
    find $mpath/ -name '*.yaml' -type f -exec sed -i "s#tgi_gaudi:2.0.1#ghcr.io/huggingface/tgi-gaudi:2.0.1#g" {} \;

    #find $mpath/* -name '*.yaml' -type f -exec sed -i "s#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#g" {} \;

    kubectl apply -f $mpath/.
    wait_until_all_pod_ready $namespace 300s
}

function uninstallChatQnA() {
    echo "Uninstall ChatQnA."
    num_gaudi=$1

    path="ChatQnA/benchmark/"
    if [ "$num_gaudi" -eq 1 ]; then
        path+="single_gaudi"
    elif [ "$num_gaudi" -eq 2 ]; then
        path+="two_gaudi"
    elif [ "$num_gaudi" -eq 4 ]; then
        path+="four_gaudi"
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

function generate_config(){
    echo "Generate benchmark config"
    num_gaudi=$1
    # under Validate folder
    input_path=".github/scripts/benchmark.yaml"
    output_path="../GenAIEval/evals/benchmark/benchmark.yaml"

    if [ "$num_gaudi" -eq 1 ]; then
        export USER_QUERIES="4, 8, 16, 32, 64, 128, 256, 512"
    elif [ "$num_gaudi" -eq 2 ]; then
        export USER_QUERIES="4, 8, 16, 32, 64, 128, 256, 512, 1024"
    elif [ "$num_gaudi" -eq 4 ]; then
        export USER_QUERIES="4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096"
    else
        echo "Unsupported number of gaudi: $num_gaudi"
        exit 1
    fi
    envsubst < $input_path > $output_path
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
	echo "Usage: $0 --cordon --uncordon --label --unlabel --installChatQnA --uninstallChatQnA --generate_config"
}

OPTIONS="-h"
LONGOPTIONS="help,cordon,uncordon,label,unlabel,installChatQnA,uninstallChatQnA,generate_config"

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
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
