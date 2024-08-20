# ChatQnA Performance Test Specification for V0.9

This is the test spec for OPEA v0.9. 

## Hardware and software spec

The test runs on 4 same Gaudi nodes with below hardware and software installed:

| Hardware   | Type         |
| ---------- | ------------------ |
| CPU | Intel ICX 8368 2Socket 38 Cores  |
| GPU | 8 Gaudi2 AI Training Accelerators |
| Memory | 1024GB |

| Software   | Version         |
| ---------- | ------------------ |
| OS | Ubuntu 22.04.4 LTS  |
| Kernel | 5.15.0-113-generic |
| Kubernetes | v1.29.6 |
| Containerd | 1.7.19 |
| Calico | v3.28.0 |

## K8s preparation

4 Gaudi nodes compose a 4-node Kubernetes cluster.  K8s cluster has below prerequisites:
- Every node has direct internet access
- In master node, kubectl is installed and have the access to K8s cluster
- In master node, Python 3.8+ is installed to run stress tool.

```
$ kubectl get nodes
NAME                STATUS   ROLES           AGE   VERSION
k8s-master          Ready    control-plane   35d   v1.29.6
k8s-work1           Ready    <none>          35d   v1.29.5
k8s-work2           Ready    <none>          35d   v1.29.6
k8s-work3           Ready    <none>          35d   v1.29.6
```

## Stress tool preparation

The test uses the [stress tool](https://github.com/opea-project/GenAIEval/tree/main/evals/benchmark) to do performance test. We need to set up stress tool at the master node of Kubernetes which is k8s-master.

```
# on k8s-master node
git clone https://github.com/opea-project/GenAIEval.git
cd GenAIEval
python3 -m venv stress_venv
source stress_venv/bin/activate
pip install -r requirements.txt
```

### Test configurations

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
| Node account | Concurrent | Query number |
| ---------- | ------------------ |
| 1 | 5 | 640 |
| 2 | 5 | 1280 |
| 4 | 5 | 2560 |

More detailed configuration can be found in configuration file [benchmark.yaml](../../.github/scripts/benchmark.yaml).

### Single node test

#### 1. Preparation

We mark three node unschedulable to get a single node K8s cluster by:
```
kubectl cordon k8s-worker1 k8s-worker2 k8s-worker3
```

#### 2. Install ChatQnA

We have created the [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark/single_gaudi) for single node K8s cluster. We need to check out and apply to K8s.

```
# on k8s-master node
git clone https://github.com/opea-project/GenAIExamples.git
cd GenAIExamples/ChatQnA/benchmark/single_gaudi
kubectl apply -f .
```
#### 3. Run tests

TODO: need to confirm
```
python stress_benchmark.py -f data.txt -s localhost:8888 -c 50 -d 30m -t chatqna
```
#### 4. Data collection

TBD

#### 5. Clean up

```
# on k8s-master node
cd GenAIExamples/ChatQnA/benchmark/single_gaudi
kubectl delete -f .
kubectl uncordon k8s-worker1 k8s-worker2 k8s-worker3
```

### Two node test

#### 1. Preparation

```
kubectl cordon k8s-worker2 k8s-worker3
```

#### 2. Install ChatQnA

We have created the [BKC manifest](https://github.com/opea-project/GenAIExamples/tree/main/ChatQnA/benchmark/two_gaudi) for two node K8s cluster. We need to check out and apply to K8s.
```
# on k8s-master node
git clone https://github.com/opea-project/GenAIExamples.git
cd GenAIExamples/ChatQnA/benchmark/two_gaudi
kubectl apply -f .
```
#### 3. Run tests

TODO: need to confirm
```
python stress_benchmark.py -f data.txt -s localhost:8888 -c 50 -d 30m -t chatqna
```
#### 4. Data collection

TBD


#### 5. Clean up

```
cd GenAIExamples/ChatQnA/benchmark/two_gaudi
kubectl delete -f .
kubectl uncordon k8s-worker2 k8s-worker3
```

### Four node test

TBD