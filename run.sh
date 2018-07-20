#!/usr/bin/env bash

# First, read about: https://github.com/kubernetes/kops/blob/master/docs/aws.md#configure-dns
#CLUSTERNAME='cluster.example.com'
CLUSTERNAME='cluster.k8s.local'

#Kubernetes version
KUBERNETES_VER="1.10.5"

# If you want to using a gossip-based cluster with Bastion, read about: https://github.com/kubernetes/kops/blob/master/docs/examples/kops-tests-private-net-bastion-host.md#adding-a-bastion-host-to-our-cluster
BASTION=false

# Networking, read about: https://github.com/kubernetes/kops/blob/master/docs/networking.md
NETWORKING="weave"
VPC_CIDR='172.50.0.0/16'

NODE_COUNT=3
MASTER_COUNT=3

# For kubernetes files
TMP_KUBE='./kops'

# My IP address
MYIP="$(curl -s https://diagnostic.opendns.com/myip)/32"


PARAM="$1"

usage() {
    echo -e "Usage:"
    echo -e "  $0 setup       Install the latest version of Terraform, Kops, Kubectl and Jq."
    echo -e "  $0 provision   Terraforming on AWS and provisioning the kubernetes cluster."
    echo -e "  $0 endpoint    Get endpoint of load balancer."
    echo -e "  $0 destroy     Destroy all cluster and terraforming."
    exit 1
}

setup() {
    # Install Terraform
    if ! [ -x "$(command -v terraform)" ]; then
      wget -qO- https://releases.hashicorp.com/terraform/0.11.7/terraform_0.11.7_linux_amd64.zip | bsdtar -xvf-
      chmod u+x ./terraform; sudo mv ./terraform /usr/local/bin/terraform
      exit 0
    fi
    # Install Kops
    if ! [ -x "$(command -v kops)" ]; then
      curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
      chmod +x ./kops-linux-amd64; sudo mv ./kops-linux-amd64 /usr/local/bin/kops
      exit 0
    fi
    # Install Kubectl 1.10.3
    if ! [ -x "$(command -v kubectl)" ]; then
      curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.10.3/bin/linux/amd64/kubectl
      chmod +x ./kubectl; sudo mv ./kubectl /usr/local/bin/kubectl
      exit 0
    fi
    # Install JQ
    if ! [ -x "$(command -v jq)" ]; then
      curl -LO https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
      chmod +x ./jq-linux64; sudo mv ./jq-linux64 /usr/local/bin/jq
      exit 0
    fi

}

provision() {

    if [ -x "$(command -v terraform)" ]; then
        echo "terraform: Terraforming on AWS"
        terraform init -input=false; terraform plan -var name="$CLUSTERNAME" -var vpc_cidr="$VPC_CIDR" -out tfplan -input=false; terraform apply -input=false tfplan
    else
        echo "Install terraform with ./run.sh setup"
    fi

    if [ -x "$(command -v terraform)" ]; then
        
        echo "kops: Create a cluster"
        kops create cluster --v 0 --name=$(terraform output cluster_name) --state=$(terraform output state_store) \
            --master-size=t2.micro --master-volume-size=16 --master-count=$MASTER_COUNT --master-zones=$(terraform output -json availability_zones | jq -r '.value|join(",")') \
            --node-size=t2.micro --node-volume-size=16 --node-count=$NODE_COUNT --zones=$(terraform output -json availability_zones | jq -r '.value|join(",")') \
            --admin-access="$MYIP" \
            --admin-access=$(terraform output -module=vpc cidr_block) \
            --ssh-access="$MYIP" \
            --ssh-access=$(terraform output -module=vpc cidr_block) \
            --vpc=$(terraform output vpc_id) \
            --network-cidr=$(terraform output -module=vpc cidr_block) \
            --networking=$NETWORKING \
            --topology=private \
            --bastion=$BASTION \
            --dns=public \
            --dns-zone=$(terraform output cluster_name) \
            --kubernetes-version="$KUBERNETES_VER" \
            --api-loadbalancer-type=public \
            --associate-public-ip=false \
            --cloud=aws \
            --ssh-public-key "~/.ssh/id_rsa.pub" \
            --cloud-labels Cluster="$CLUSTERNAME" \
            --out="$TMP_KUBE" --target=terraform
            #--image=$(terraform output ami)

        echo "kops: Updating..."
        kops update cluster --name=$(terraform output cluster_name) --state=$(terraform output state_store) --yes

        echo "kops: Create kubecfg settings for kubectl"
        kops export kubecfg --name=$(terraform output cluster_name) --state=$(terraform output state_store)

        echo "kops: For validate the cluster, you must wait 5 min"
        sleep 5m
        
        echo "kops: Validate the cluster"
        kops validate cluster --name=$(terraform output cluster_name) --state=$(terraform output state_store)

        echo "terraform: Terraforming on AWS"
        terraform init -input=false; terraform plan -var name="$CLUSTERNAME" -var vpc_cidr="$VPC_CIDR" -out tfplan -input=false; terraform apply -input=false tfplan
    else
        echo "Install kops with ./run.sh setup"
    fi

    echo "kubectl: Get all nodes including all namespaces"
    kubectl get all --all-namespaces

    if [ `sudo systemctl is-active docker` = "active" ]; then 
        echo "docker: Building a container image"
        docker build -t springboot/hateoas:latest .
    fi

    echo "docker: Login with AWS ECR"
    docker login -u AWS -p $(aws --profile default ecr --region=$(terraform output region) get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2) https://$(terraform output account_id).dkr.ecr.$(terraform output region).amazonaws.com
 
    echo "docker: Tag for docker image and push image to the repository"
    docker tag springboot/hateoas:latest $(terraform output ecr_repository)
    docker push $(terraform output ecr_repository)

    echo "kubectl: Create a secret for aws ecr authentication"
    kubectl create secret docker-registry $CLUSTERNAME \
     --docker-server=https://$(terraform output account_id).dkr.ecr.$(terraform output region).amazonaws.com \
     --docker-username=AWS \
     --docker-password="$(aws --profile default ecr --region=$(terraform output region) get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2)" \
     --docker-email="me@email.com"

    echo "bash: replace value from terraform on deployment file"
    sed "0,/^\([[:space:]]*image: *\).*/s||\1$(terraform output ecr_repository)|" < deployment-spring-hateaos.yaml.example > deployment-spring-hateaos.yml
    sed -i "/^ *imagePullSecrets:/,/^ *[^:]*:/s/name: SECRET_NAME/name: $(terraform output cluster_name)/" deployment-spring-hateaos.yml

    echo "kubectl: Create a kubernetes services and deployment"
    kubectl create -f ./deployment-spring-hateaos.yml

    echo "kubectl: For validate AWS ELB, you must wait 2 min"
    sleep 2m

    echo "Got to de url: http://$(kubectl get service/springboot-hateaos -o=json | jq -r '.status.loadBalancer.ingress | .[0].hostname')/customers"

}


destroy() {

    echo "kubectl: Destroy deployment and services"
    kubectl delete deployment/springboot-hateaos service/springboot-hateaos
    
    echo "kops: Destroy cluster"
    kops delete cluster --name=$(terraform output cluster_name) --state=$(terraform output state_store) --yes
    
    echo "terraform: Destroy terraform"
    terraform destroy -auto-approve
    
    echo "bash: Clean obsolete files"
    rm ./tfplan; rm -fr ./.terraform; rm *.yml; rm -f ./terraform.tfstate*; rm -fr "$TMP_KUBE"; ls -la

}


endpoint() {

    echo "url: http://$(kubectl get service/springboot-hateaos -o=json | jq -r '.status.loadBalancer.ingress | .[0].hostname')/customers"

}


if [ $# -eq 0 ]; then
    usage
    exit 1
else
    if [ $PARAM == setup ]; then
        setup
        exit 0
    elif [ $PARAM == provision ]; then
        provision
        exit 0
    elif [ $PARAM == endpoint ]; then
        endpoint
        exit 0
    elif [ $PARAM == destroy ]; then
        destroy
        exit 0
    else
        echo -e "Error parameters"
        usage
        exit 1
    fi
fi
