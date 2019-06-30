# OpenShift Container Platform 4.x UPI on AWS

## Prerequisites

* Cluster's public base domain
* Route53's Public Hosted Zone for the base domain
* AWS Administrator IAM account
  * To be accurate, IAM account which has the permission documented in the [OpenShift docs](https://docs.openshift.com/container-platform/4.1/installing/installing_aws_user_infra/installing-aws-user-infra.html#installation-aws-permissions_installing-aws-user-infra)
* `openshift-install` and `oc` commands
  * Download from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/

## Creates cluster configuration files

### Creates install-config.yaml

`$ cat .upi/install-config.yaml`

```yaml
apiVersion: v1
baseDomain: cluster.example.com # Base Domain
compute:
- hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 0
controlPlane:
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 1
metadata:
  name: upi-1 # <Cluster Name>
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ap-northeast-1
# Get pull secret from: https://cloud.redhat.com/openshift/install/aws/user-provisioned
pullSecret: '{"auths":{"cloud.openshift.com":{"auth....'
# SSH public key for machines which host OpenShift
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAA...
```

### Creates manifests

```
$ openshift-install create manifests --dir=.upi
```

```
.upi
├── manifests
│   ├── 04-openshift-machine-config-operator.yaml
│   ├── cluster-config.yaml
│   ├── cluster-dns-02-config.yml
│   ├── ...
└── openshift
    ├── 99_kubeadmin-password-secret.yaml
    ├── 99_openshift-cluster-api_master-machines-0.yaml
    ├── 99_openshift-cluster-api_master-user-data-secret.yaml
    ├── 99_openshift-cluster-api_worker-machineset-0.yaml
    ├── 99_openshift-cluster-api_worker-machineset-1.yaml
    ├── 99_openshift-cluster-api_worker-machineset-2.yaml
    ├── 99_openshift-cluster-api_worker-user-data-secret.yaml
    ├── 99_openshift-machineconfig_master.yaml
    ├── ...
```

#### Delete unused manifests

```bash
$ rm .upi/openshift/99_openshift-cluster-api_master-machines-*.yaml
$ rm .upi/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
```

### Create some files for Ignition

```bash
$ openshift-install create ignition-configs --dir=.upi
```

Now, here is .upi dir.

```
upi/
├── auth
│   ├── kubeadmin-password
│   └── kubeconfig
├── bootstrap.ign
├── master.ign
├── metadata.json
└── worker.ign
```

## Gets a Cluster ID

```bash
$ cat .upi/metadata.json | jq
{
  "clusterName": "upi-1",
  "clusterID": "xxx",
  "infraID": "upi-1-1-xxxx",
  "aws": {
    "region": "ap-northeast-1",
    "identifier": [
      {
        "kubernetes.io/cluster/upi-1-1-xxxx": "owned"
      },
      {
        "openshiftClusterID": "xxxx"
      }
    ]
  }
}

$ CLUSTER_ID=$(jq -r .infraID .upi/metadata.json)
$ echo $CLUSTER_ID
upi-1-1-xxxx
```

## Infrastructecture on AWS

![Simple Architecture Overview](./images/upi-overview.png)

### VPC、subnest and LB, DNS

```bash
$ git clone https://github.com/literalice/terraform-aws-openshift-upi
$ cd terraform-aws-openshift-upi
$ terraform init

$ cat terraform.tfvars

$ cat <<EOF > terraform.tfvars
config_dir = ".upi" # Directory that is specified in openshift-install's -dir option
blacklist_az = ["ap-northeast-1a"] # Unavailable Availability Zone in your AWS account / Region
EOF

$ terraform plan -target module.network
$ terraform apply -target module.network
```

### Creates BootStrap Node

```bash
$ terraform plan -target module.bootstrap
$ terraform apply -target module.bootstrap
```

### Creates Control Plane

```bash
$ cd terraform-aws-openshift-upi
$ terraform plan -target module.controlplane
$ terraform apply -target module.controlplane
```

### Delete unused resources

```bash
$ terraform destroy module.bootstrap
```

### Access check

```bash
$ export KUBECONFIG=.upi/auth/kubeconfig
$ oc get pods -A
$ oc status
```

### Worker nodes

Adds the MachineSet Object for worker nodes.

```yaml
# machineset-upi1-worker-ap-northeast-1b
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: upi1-xxxx # <Cluster ID>を追加
  name: upi1-xxx-worker-ap-northeast-1b # <Cluster ID>-worker-<ワーカーを作成するAZ名>
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: upi1-xxxx # Cluster IDを追加
      machine.openshift.io/cluster-api-machine-role: worker
      machine.openshift.io/cluster-api-machine-type: worker
      machine.openshift.io/cluster-api-machineset: upi1-xxx-worker-ap-northeast-1b # <Cluster ID>-worker-AZ
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: upi1-xxxx # Cluster IDを追加
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: upi1-xxx-worker-ap-northeast-1b # <Cluster ID>-worker-AZ
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/worker: ""
      providerSpec:
        value:
          ami:
            id: ami-0906ab32ecf300238
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          blockDevices:
            - ebs:
                iops: 0
                volumeSize: 120
                volumeType: gp2
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: upi1-xxx-worker-profile
          instanceType: m4.large
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ap-northeast-1b
            region: ap-northeast-1
          securityGroups:
            - filters:
                - name: tag:Name
                  values:
                    - upi1-xxx-private
          subnet:
            filters:
              - name: tag:Name
                values:
                  - upi1-xxx-private-0
          tags:
            - name: kubernetes.io/cluster/upi1-xxx # kubernetes.io/cluster/<Cluster ID>
              value: owned
          userDataSecret:
            name: worker-user-data
```

You can use the terraform module:

```bash
$ terraform apply -target module.worker
$ watch oc get nodes
```

## Access to OpenShift Web Console

```bash
$ oc get routes -n openshift-console
NAME        HOST/PORT                                                     PATH   SERVICES    PORT    TERMINATION          WILDCARD
console     console-openshift-console.apps.<Cluster Name>.<Base Domain>          console     https   reencrypt/Redirect   None
downloads   downloads-openshift-console.apps.<Base Domain>                       downloads   http    edge                 None

# You can know the password for user: `kubeadmin`
$ cat .upi/auth/kubeadmin-password 
```
