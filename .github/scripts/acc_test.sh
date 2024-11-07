#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

ip_address=$(hostname -I | awk '{print $1}')
WORKPATH=$PWD

function launch_service(){
    cd $WORKPATH/GenAIExamples/$1/tests/
    if [[ "$1" == "ChatQnA" ]]; then
        if [[ "$2" == "zh" ]]; then
            head -n "$(($(wc -l < test_compose_on_gaudi.sh) - 14))" "test_compose_on_gaudi.sh" > launch_"$1"_"$2".sh
            echo "    validate_megaservice" >> launch_"$1"_"$2".sh
            echo "}" >> launch_"$1"_"$2".sh
            echo "main" >> launch_"$1"_"$2".sh
            sed -i 's/export EMBEDDING_MODEL_ID="BAAI\/bge-base-en-v1.5"/export EMBEDDING_MODEL_ID="BAAI\/bge-base-zh-v1.5"/' launch_"$1"_"$2".sh
            sed -i 's/export LLM_MODEL_ID="Intel\/neural-chat-7b-v3-3"/export LLM_MODEL_ID="Qwen\/Qwen2-7B-Instruct"/' launch_"$1"_"$2".sh
            bash launch_"$1"_"$2".sh
        else
            head -n "$(($(wc -l < test_compose_on_gaudi.sh) - 14))" "test_compose_on_gaudi.sh" > launch_"$1"_"$2".sh
            echo "    validate_megaservice" >> launch_"$1"_"$2".sh
            echo "}" >> launch_"$1"_"$2".sh
            echo "main" >> launch_"$1"_"$2".sh
            bash launch_"$1"_"$2".sh
        fi
    else
        if [[ "$1" == "CodeGen" ]]; then sed -i 's/--max-total-tokens 2048/--max-total-tokens 4096/g' $WORKPATH/GenAIExamples/$1/docker_compose/intel/hpu/gaudi/compose.yaml; fi
        head -n "$(($(wc -l < test_compose_on_gaudi.sh) - 10))" "test_compose_on_gaudi.sh" > launch_"$1".sh
        echo "    validate_megaservice" >> launch_"$1".sh
        echo "}" >> launch_"$1".sh
        echo "main" >> launch_"$1".sh
        bash launch_"$1".sh
    fi
}
function eval_prepare(){
    if [[ "$1" == "ChatQnA" && "$2" == "en" ]]; then
        cd $WORKPATH/GenAIEval/
        DPATH=$PWD
        export PYTHONPATH=$PYTHONPATH:$DPATH
        export PATH=$PATH:/bin:/usr/bin
        # cd $WORKPATH/GenAIEval/evals/evaluation/rag_eval/examples
        # # docker run -tid -p 9001:80 --runtime=habana -e HABANA_VISIBLE_DEVICES=1,2 -e HABANA_VISIBLE_MODULES=6,7 -e
        # docker run -tid -p 8005:80 --runtime=habana -e HABANA_VISIBLE_DEVICES=all -e PT_HPU_ENABLE_LAZY_COLLECTIVES=true -e OMPI_MCA_btl_vader_single_copy_mechanism=none -e HF_TOKEN=${HF_TOKEN} --cap-add=sys_nice --ipc=host ghcr.io/huggingface/tgi-gaudi:2.0.1 --model-id mistralai/Mixtral-8x7B-Instruct-v0.1 --max-input-tokens 2048 --max-total-tokens 4096 --sharded true --num-shard 2
    elif [[ "$1" == "FaqGen" ]]; then
        export FAQ_ENDPOINT="http://${ip_address}:9000/v1/faqgen"
        cd $WORKPATH/GenAIExamples/$1/benchmark/accuracy
        sed -i 's/f = open("data\/sqv2_context.json", "r")/f = open("\/data2\/opea-dataset\/FaqGen\/sqv2_context.json", "r")/g' generate_FAQ.py
        sed -i 's/f = open("data\/sqv2_context.json", "r")/f = open("\/data2\/opea-dataset\/FaqGen\/sqv2_context.json", "r")/g' evaluate.py
        sed -i 's/1204/120/g' generate_FAQ.py
        sed -i 's/1204/120/g' post_process_FAQ.py
        sed -i 's/1204/120/g' evaluate.py
        [ ! -d "$WORKPATH/GenAIExamples/$1/benchmark/accuracy/data/result" ] && mkdir -p $WORKPATH/GenAIExamples/$1/benchmark/accuracy/data/result
        python generate_FAQ.py
        python post_process_FAQ.py
        # # max_input_tokens=3072
        # # max_total_tokens=4096
        # # port_number=8082
        # # model_name="mistralai/Mixtral-8x7B-Instruct-v0.1"
        # # volume="./data"
        # # docker run -dit --rm --name="tgi_Mixtral" -p $port_number:80 -v $volume:/data --runtime=habana -e HUGGING_FACE_HUB_TOKEN=$HUGGING_FACE_HUB_TOKEN -e HABANA_VISIBLE_DEVICES=all -e OMPI_MCA_btl_vader_single_copy_mechanism=none -e PT_HPU_ENABLE_LAZY_COLLECTIVES=true --cap-add=sys_nice --ipc=host -e HTTPS_PROXY=$https_proxy -e HTTP_PROXY=$https_proxy ghcr.io/huggingface/tgi-gaudi:2.0.5 --model-id $model_name --max-input-tokens $max_input_tokens --max-total-tokens $max_total_tokens --sharded true --num-shard 2
        # docker run -tid -p 8082:80 --runtime=habana -e HABANA_VISIBLE_DEVICES=all -e PT_HPU_ENABLE_LAZY_COLLECTIVES=true -e OMPI_MCA_btl_vader_single_copy_mechanism=none -e HF_TOKEN=${HF_TOKEN} --cap-add=sys_nice --ipc=host ghcr.io/huggingface/tgi-gaudi:2.0.5 --model-id mistralai/Mixtral-8x7B-Instruct-v0.1 --max-input-tokens 3072 --max-total-tokens 4096 --sharded true --num-shard 2
        # sleep 600
        export LLM_ENDPOINT="http://${ip_address}:8008"
        curl http://${ip_address}:8008/generate \
          -X POST \
          -d '{"inputs":"What is Deep Learning?","parameters":{"max_new_tokens":128}}' \
          -H 'Content-Type: application/json'
    fi
}

function launch_acc(){
    cd $WORKPATH/GenAIEval/
    DPATH=$PWD
    export PYTHONPATH=$PYTHONPATH:$DPATH
    export PATH=$PATH:/bin:/usr/bin
    cd $WORKPATH/GenAIExamples/$1/benchmark/accuracy/
	if [[ "$1" == "CodeGen" ]]; then
        export CODEGEN_ENDPOINT="http://${ip_address}:7778/v1/codegen"
        export CODEGEN_MODEL="Qwen/CodeQwen1.5-7B-Chat"
        bash run_acc.sh $CODEGEN_MODEL $CODEGEN_ENDPOINT
    elif [[ "$3" == "ChatQnA" ]]; then
        sed -i 's|--docs_path MultiHop-RAG/dataset/corpus.json|--docs_path /data2/opea-dataset/ChatQnA/MultiHop-RAG/dataset/corpus.json|g' run_acc.sh
        sed -i 's|--dataset_path MultiHop-RAG/dataset/MultiHopRAG.json|--dataset_path /data2/opea-dataset/ChatQnA/MultiHop-RAG/dataset/MultiHopRAG.json|g' run_acc.sh
        sed -i '/git clone https:\/\/github.com\/yixuantt\/MultiHop-RAG.git/d' run_acc.sh
        sed -i '/git clone https:\/\/github.com\/IAAR-Shanghai\/CRUD_RAG/d' run_acc.sh
        sed -i '/mkdir data\//d' run_acc.sh
        sed -i '/cp CRUD_RAG\/data\/crud_split\/split_merged.json data\//d' run_acc.sh
        sed -i '/cp -r CRUD_RAG\/data\/80000_docs\/ data\//d' run_acc.sh
        sed -i '/python process_crud_dataset.py/d' run_acc.sh
        sed -i 's|--dataset_path ./data/split_merged.json|--dataset_path /data2/opea-dataset/ChatQnA/data/split_merged.json|' run_acc.sh
        sed -i 's|--docs_path ./data/80000_docs|--docs_path /data2/opea-dataset/ChatQnA/data/80000_docs/|' run_acc.sh
        if [[ "$3" == "en" ]]; then
            bash run_acc.sh --dataset=MultiHop
        else
            bash run_acc.sh --dataset=crud
        fi
    elif [[ "$1" == "AudioQnA" ]]; then
        export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
        bash run_acc.sh
    else
        bash run_acc.sh
    fi
}



#Process the options
case "$1" in
    --launch_acc)
        launch_acc $2 $3
        ;;
    --eval_prepare)
        eval_prepare $2 $3
        ;;
    --launch_service)
        launch_service $2 $3
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
esac