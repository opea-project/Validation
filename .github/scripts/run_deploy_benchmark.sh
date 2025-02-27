#!/bin/bash
set -e
# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

function generate_config(){
    echo "Generating deploy and benchmark config..."
    example=$1
    deploy_args=$2
    benchmark_args=$3

    lower_example=$(echo "$example" | tr '[:upper:]' '[:lower:]')
    example_yaml_path="./$example/benchmark_$lower_example.yaml"
    if [ -f $example_yaml_path ]; then
        echo "Found example yaml file: $example_yaml_path"
    else
        echo "Example yaml file not found: $example_yaml_path"
        exit 1
    fi

    # update model path and hf_token
    sed -i "s#modelUseHostPath:.*#modelUseHostPath: $HOME/$MODEL_PATH#" "$example_yaml_path"
    sed -i "s/^\(\s*HUGGINGFACEHUB_API_TOKEN\):.*/\1: $HF_TOKEN/" "$example_yaml_path"

    # update other input args
    update_yaml "$example_yaml_path" "$deploy_args"
    update_yaml "$example_yaml_path" "$benchmark_args"

    echo "Print update config yaml..."
    cat "$example_yaml_path"

}

function update_yaml() {
    yaml_path=$1
    args=$2

    IFS='#' read -ra pairs <<< "$args"
    for pair in "${pairs[@]}"; do
      IFS='=' read -ra kv <<< "$pair"
      key="${kv[0]}"
      value="${kv[1]}"

      if [ "$key" = "with_rerank" ]; then
          sed -i "/teirerank:/{n;s/^\(\s*enabled\):.*/\1: $value/;}" "$yaml_path"
      else
          sed -i "s#$key:.*#$key: $value#" "$yaml_path"
      fi
    done
}

function run() {
    echo "Run deploy and benchmark..."
    example=$1
    test_mode=$2
    target_node=$3

    lower_example=$(echo "$example" | tr '[:upper:]' '[:lower:]')
    example_yaml_path="./$example/benchmark_$lower_example.yaml"
    extra_args="--test-mode ${test_mode}"
    if [ -n "$target_node" ]; then
        extra_args="$extra_args --target-node $target_node"
        echo "extra_args: $extra_args"
    fi

    python deploy_and_benchmark.py "${example_yaml_path}" $extra_args
}

function generate_report() {
    echo "Generate benchmark report..."
    output_path=$1
    output_folders=$(ls -td $output_path/benchmark_*/run_benchmark_*_output/)
    for folder in $output_folders; do
        echo -e "\nFolder: $folder"
        python ../GenAIEval/evals/benchmark/stresscli/stresscli.py report --folder $folder --format csv --output ${folder}result_report.csv
        python .github/scripts/process_csv_new.py ${folder}result_report.csv
        cat ${folder}result_report.csv
    done
}

# Process the options
case "$1" in
    --generate_config)
        pushd ../GenAIExamples
        generate_config $2 $3 $4
        popd
        ;;
    --run)
        pushd ../GenAIExamples
        run $2 $3 $4
        popd
        ;;
    --generate_report)
        generate_report $2
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac
