# Terraform + Kops + Kubernetes

Provision a kubernetes cluster with Terraform and Kops on Amazon Web Services.

In this example we deploy to AWS a sample of RESTFul API using **[Spring Boot Hateoas](https://github.com/spring-projects/spring-boot/tree/master/spring-boot-samples/spring-boot-sample-hateoas)**.

## Requirements:

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- [Install Kops](https://github.com/kubernetes/kops#linux)
- [Install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-via-curl)
- [Install Jq](https://stedolan.github.io/jq/download/)

Or install all depencencies with the script ruh.sh:

```bash
./run.sh setup
``` 

**Important:**

- AWS Credentials with all permission for create EC2 instances, Security Groups, Elastic Container Registry (ECR), VPC, Subnet, Internet Gateway, ELB and S3 Bucket.
- Docker 17.05 or later to build the Docker image of Spring Boot Hateoas.

## Quick Start:

Run on your machine and take the coffee break time:

```bash
./run.sh provision
```

## How it works!:

## Features: