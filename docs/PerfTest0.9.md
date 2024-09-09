# ChatQnA Performance Test Specification for V0.9

This is the test spec for OPEA v0.9. 

## Hardware requirement

The test runs on 4 Gaudi nodes. Each node has 8 GPU accelerators.

### K8s preparation

4 Gaudi nodes compose a 4-node Kubernetes cluster.  K8s cluster has below prerequisites:
- Every node has direct internet access
- In master node, kubectl is installed and have the access to K8s cluster
- In master node, Python 3.8+ is installed to run stress tool.
- In every node, there is a local folder "/mnt/models" which will be mounted to pods as model path.

```
$ kubectl get nodes
NAME                STATUS   ROLES           AGE   VERSION
k8s-master          Ready    control-plane   35d   v1.29.6
k8s-work1           Ready    <none>          35d   v1.29.5
k8s-work2           Ready    <none>          35d   v1.29.6
k8s-work3           Ready    <none>          35d   v1.29.6
```

### Manifest preparation

We have created the [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark) for single node, two nodes and four nodes K8s cluster. In order to apply, we need to check out and configure some values.

```
# on k8s-master node
git clone https://github.com/opea-project/GenAIExamples.git
cd GenAIExamples/ChatQnA/benchmark

# replace the image tag from latest to v0.9 since we want to test with v0.9 release
IMAGE_TAG=v0.9
find . -name '*.yaml' -type f -exec sed -i "s#image: opea/\(.*\):latest#image: opea/\1:${IMAGE_TAG}#g" {} \;

# set the huggingface token
HUGGINGFACE_TOKEN=<your token>
find . -name '*.yaml' -type f -exec sed -i "s#\${HF_TOKEN}#${HUGGINGFACE_TOKEN}#g" {} \;

# set models
LLM_MODEL_ID=Intel/neural-chat-7b-v3-3
EMBEDDING_MODEL_ID=BAAI/bge-base-en-v1.5
RERANK_MODEL_ID=BAAI/bge-reranker-base
find . -name '*.yaml' -type f -exec sed -i "s#\$(LLM_MODEL_ID)#${LLM_MODEL_ID}#g" {} \;
find . -name '*.yaml' -type f -exec sed -i "s#\$(EMBEDDING_MODEL_ID)#${EMBEDDING_MODEL_ID}#g" {} \;
find . -name '*.yaml' -type f -exec sed -i "s#\$(RERANK_MODEL_ID)#${RERANK_MODEL_ID}#g" {} \;
```

### Stress tool preparation

The test uses the [stress tool](https://github.com/opea-project/GenAIEval/tree/main/evals/benchmark) to do performance test. We need to set up stress tool at the master node of Kubernetes which is k8s-master.

```
# on k8s-master node
git clone https://github.com/opea-project/GenAIEval.git
cd GenAIEval
python3 -m venv stress_venv
source stress_venv/bin/activate
pip install -r requirements.txt
```

## Test Configurations

Workload configuration:

| Key | Value |
| ---------- | ------------------ |
| Workload | ChatQnA  |
| Tag | V0.9  |

Models configuration
| Key | Value |
| ---------- | ------------------ |
| Embedding | BAAI/bge-base-en-v1.5 |
| Reranking | BAAI/bge-reranker-base |
| Inference | Intel/neural-chat-7b-v3-3 |

Benchmark parameters
| Key | Value |
| ---------- | ------------------ |
| LLM input tokens | 1024 |
| LLM output tokens | 128 |

Number of test requests for different scheduled node number:
| Node account | Concurrency | Query number |
| ----- | -------- | -------- |
| 1 | 128 | 640 |
| 2 | 256 | 1280 |
| 4 | 512 | 2560 |

More detailed configuration can be found in configuration file [benchmark.yaml](../.github/scripts/benchmark.yaml).

## Test Steps

### Single node test

#### 1. Preparation

We add label to 1 Kubernetes node to make sure all pods are scheduled to this node:
```
kubectl label nodes k8s-worker1 node-type=chatqna-opea
```

#### 2. Install ChatQnA

Go to [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark/single_gaudi) and apply to K8s.

```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/single_gaudi
kubectl apply -f .
```
#### 3. Run tests

We copy the configuration file [benchmark.yaml](../../.github/scripts/benchmark.yaml) to `GenAIEval/evals/benchmark/benchmark.yaml` and config `test_suite_config.user_queries` and `test_suite_config.test_output_dir`.

```
export USER_QUERIES="4, 8, 16, 640"
export TEST_OUTPUT_DIR="/home/sdp/benchmark_output/node_1"
envsubst < Validation/.github/scripts/benchmark.yaml > GenAIEval/evals/benchmark/benchmark.yaml
```

And then run the benchmark tool by:
```
cd GenAIEval/evals/benchmark
python benchmark.py
```
#### 4. Data collection

All the test results will come to this folder `/home/sdp/benchmark_output/node_1` configured by the environment variable `TEST_OUTPUT_DIR` in previous steps.

#### 5. Clean up

```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/single_gaudi
kubectl delete -f .
kubectl label nodes k8s-worker1 node-type-
```
### Two node test

#### 1. Preparation

We add label to 2 Kubernetes node to make sure all pods are scheduled to this node:
```
kubectl label nodes k8s-worker1 k8s-worker2 node-type=chatqna-opea
```

#### 2. Install ChatQnA

Go to [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark/two_gaudi) and apply to K8s.
```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/two_gaudi
kubectl apply -f .
```
#### 3. Run tests

We copy the configuration file [benchmark.yaml](../../.github/scripts/benchmark.yaml) to `GenAIEval/evals/benchmark/benchmark.yaml` and config `test_suite_config.user_queries` and `test_suite_config.test_output_dir`.

```
export USER_QUERIES="4, 8, 16, 1280"
export TEST_OUTPUT_DIR="/home/sdp/benchmark_output/node_2"
envsubst < Validation/.github/scripts/benchmark.yaml > GenAIEval/evals/benchmark/benchmark.yaml
```

And then run the benchmark tool by:
```
cd GenAIEval/evals/benchmark
python benchmark.py
```

#### 4. Data collection

All the test results will come to this folder `/home/sdp/benchmark_output/node_2` configured by the environment variable `TEST_OUTPUT_DIR` in previous steps.

#### 5. Clean up

```
# on k8s-master node
kubectl delete -f .
kubectl label nodes k8s-worker1 k8s-worker2 node-type-
```
### Four node test

#### 1. Preparation

We add label to 4 Kubernetes node to make sure all pods are scheduled to this node:
```
kubectl label nodes k8s-master k8s-worker1 k8s-worker2 k8s-worker3 node-type=chatqna-opea
```

#### 2. Install ChatQnA

Go to [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark/four_gaudi) and apply to K8s.
```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/four_gaudi
kubectl apply -f .
```
#### 3. Run tests

We copy the configuration file [benchmark.yaml](../../.github/scripts/benchmark.yaml) to `GenAIEval/evals/benchmark/benchmark.yaml` and config `test_suite_config.user_queries` and `test_suite_config.test_output_dir`.

```
export USER_QUERIES="4, 8, 16, 2560"
export TEST_OUTPUT_DIR="/home/sdp/benchmark_output/node_4"
envsubst < Validation/.github/scripts/benchmark.yaml > GenAIEval/evals/benchmark/benchmark.yaml
```

And then run the benchmark tool by:
```
cd GenAIEval/evals/benchmark
python benchmark.py
```

#### 4. Data collection

All the test results will come to this folder `/home/sdp/benchmark_output/node_4` configured by the environment variable `TEST_OUTPUT_DIR` in previous steps.

#### 5. Clean up

```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/single_gaudi
kubectl delete -f .
kubectl label nodes k8s-master k8s-worker1 k8s-worker2 k8s-worker3 node-type-
```
