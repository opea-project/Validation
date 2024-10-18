#!/bin/bash
# Copyright (C) 2024 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

ip_address=$(hostname -I | awk '{print $1}')
echo $1 $2
if [[ "$1" == "CodeGen " ]]; then
    export CODEGEN_ENDPOINT="http://${ip_address}:7778/v1/codegen"
    export CODEGEN_MODEL="Qwen/CodeQwen1.5-7B-Chat"
    cat run_acc.sh
    cat main.py
    bash run_acc.sh $CODEGEN_MODEL $CODEGEN_ENDPOINT
elif [[ "$1" == "ChatQnA" ]]; then
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
    if [[ "$2" == "en" ]]; then
        bash run_acc.sh --dataset=MultiHop
    else
        bash run_acc.sh --dataset=crud
    fi
elif [[ "$1" == "AudioQnA" ]]; then
    export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
    python online_eval.py
fi
bash run_acc.sh