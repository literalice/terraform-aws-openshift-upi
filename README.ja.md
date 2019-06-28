# OpenShift Container Platform 4.xをAWSに手動(UPI)でインストールする

OpenShift 4.xは、基本的にインストーラーでノードやネットワーク、LB、DNSも含めてインストール、セットアップできます。

AWS上であれば、適切な権限のあるIAMさえあれば、何も無いところからクラスタを構築できるわけです。

本来はこのようにインストーラーでインフラごと新規に構築する手順を推奨しますが、様々な事情から既に用意されたインフラ上にOpenShiftだけをインストールすることを強いられる場合もあります。

* OpenShiftインストーラーがまだ対応していないIaaS、基盤を使用している
  * というか、4.1だとAWS以外の全てですが
* ネットワーク構成や使用するOSを自分で選択、管理したい
* IaaSを操作する権限がない

このような要件のもと、OpenShift 4を既存のインフラの上に構築する手順のことを、User Provisioned Infrastructure、略してUPIと呼ぶこともあります。

一方、DNSやLB、サブネット構成も含めて全てOpenShiftのインストーラーで新規に構築する手順は、Installer Provisioned Infrastructure(IPI)と呼ばれたりします。

ここでは、OpenShiftを、AWSの上にUPIで構築する手順を紹介します。

UPIは、ユーザー自らOpenShiftをインストールするインフラを構築する手順なので、ユーザーの環境、要件によりその手順は様々です。ここで紹介する手順はその一例と思ってください。

## OpenShift 4の構築手順概要

OpenShift 4の特徴的なところは、OSも含めてOpenShift側で管理されるというところです。

つまり、OpenShift 4をホストするOSは、OpenShift 4がホストする情報を使って起動します。

これによりOpenShift 4上でOSの起動、パッチ適用なども含めて自動化されるわけですが、
じゃあ最初にクラスタを新規構築するときは、OSを起動するための情報をホストしているクラスタがまだないじゃないか、どうするんだという問題が出てくるわけですね。

この問題を解決するために、構築時のみ必要となるのがBootStrapと呼ばれる、一時的な、種となるOpenShiftのControl Planeです。

このあたりの内容は[GitHub](https://github.com/openshift/installer/blob/release-4.1/docs/user/overview.md)に記載がありますが、大まかに以下のような内容になっています。

![OpenShift Bootstrap](images/openshift-bootstrap.png)

* クラスタの設定情報を作成し、S3などインターネットからアクセスできる場所に置いておく
* BootStrapマシン(クラスタ構築時のみ使用される一時的なマシン)を起動する
* BootStrapマシンは、S3からクラスタ設定情報を取得し、OpenShiftマスターノード用マシンのセットアップに必要な設定情報をホスティングする
* マスターノード用マシンを起動する。このマシンは、起動処理の中でBootStrapマシンから必要な設定情報を取得する
* マスターノード用マシンは、BootStrapマシンから取得した情報を使ってetcdクラスタを構築する
* BootStrapマシンは、上記で構築されたetcdクラスタを使って、自身の中で一時的なKubernetesのControl Planeを起動する
* BootStrapマシンは、マスターノード用マシン上にKubernetesのControl Planeを立ち上げる。これが、クラスタの正式なControl Plane。
* BootStrapマシンの一時的なControl Planeは、上記で構築した正式なControl Planeに制御を渡して終了する
* BootStrapマシンは、構築された正式なControl Planeに、OpenShiftとして必要なコンポーネントコンテナをデプロイ、設定する
* BootStrapマシンをシャットダウン、または削除する

IPIの場合は、上記プロセスをインストーラーが実施してくれますが、UPIの場合は自分で実施する必要があります。

そういうわけで、以下、その手順を紹介していきます。

## 構築前に用意するもの

* 構築するクラスタのベースドメインとなる、パブリックなドメイン
* 上記のドメイン名と一致する、Route53のPublicHostedZone
* AWSのAdministoratorアカウントへのアクセス
  * 正確には、[ドキュメント](https://docs.openshift.com/container-platform/4.1/installing/installing_aws_user_infra/installing-aws-user-infra.html#installation-aws-permissions_installing-aws-user-infra)で指定されたパーミッションを持つIAMアカウントが`.aws/credentials`に設定されていること
* `openshift-install`コマンドと`oc`コマンド
  * このコマンドがない場合は、[ダウンロードページ](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/)より取得

## OpenShift 4のクラスタ設定ファイルを作成する

まず、これから構築するOpenShiftクラスタの設定情報を、`openshift-install`コマンドを使って生成します。

この設定情報には、以下のような情報が含まれています。

* OpenShiftクラスタを構成するEC2インスタンスの起動処理(UserData)
* 構築したOpenShiftクラスタにデプロイする必要がある、クラスタ制御用のコンテナのデプロイ設定
* OpenShiftクラスタを構築するための一時的な証明書

なお、最後の証明書は24時間で期限が切れるので、この生成作業から24時間以内にクラスタの構築を完了する必要があります。

### install-config.yamlを作成する

`install-config.yaml`は、非常にシンプルなクラスタの構成情報です。

このファイルには、何個ノードを作成するか、各ノードに設定するSSH公開鍵、OpenShiftのサブスクリプション管理に使用される製品キーなど、最低限の情報のみ含まれます。

* クラスタのベースドメイン。パブリックな任意のドメイン。例: `clusters.example.com`
* クラスタを識別する任意のクラスタ名。 例: `upi-1`
* マスターノードの数
* 構築先のAWSリージョン
* OpenShiftの製品管理に使用するシークレット情報。
  * 以下ページの「Pull Secret」から取得できる。 https://cloud.redhat.com/openshift/install/aws/user-provisioned
* クラスタを構成するマシンに設定する公開鍵

上記の情報を揃えて以下のようなファイルを作成し、任意のディレクトリに`install-config.yaml`という名前で保存してください。ここでは、`.upi`ディレクトリに作成します。

`$ cat .upi/install-config.yaml`

```yaml
apiVersion: v1
baseDomain: cluster.example.com # <ベースドメイン>
compute:
- hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 0 # 後で作成するので、ここではゼロを指定
controlPlane:
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 1 # マスターノードはとりあえず1つで作成
metadata:
  name: upi-1 # <クラスタ名>
networking: # 固定で以下を設定
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ap-northeast-1 # 構築先のリージョン
# https://cloud.redhat.com/openshift/install/aws/user-provisioned で取得できる、OpenShift製品管理のためのシークレット情報
pullSecret: '{"auths":{"cloud.openshift.com":{"auth....'
# クラスタを構成する各マシンに設定される、SSH公開鍵
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAA...
```

### マニフェストファイルの生成

次に、上記の`install-config.yaml`からマニフェストファイルを作成します。

このファイルには、主にクラスタ起動後にクラスタにデプロイされる、OpenShift制御用のコンテナ情報やその設定情報などが含まれます。

上記で作成した`install-config.yaml`のあるディレクトリを指定して、以下コマンドを実行します。

なお、下記コマンドを実行した時点で、`install-config.yaml`は「消費されて」削除されますので、バックアップが必要であれば事前に別ディレクトリにコピーしておいてください。

```
$ openshift-install create manifests --dir=.upi
```

なお、上記コマンドは、`install-config.yaml`の`baseDomain`と一致するPublicHostedZone (Route53)にアクセスできないと失敗するようです。

これにより、`install-config.yaml`をもとに、以下のように、OpenShiftシステムの動作に必要なKubernetesのAPIオブジェクトファイルが生成されます。

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

machinesオブジェクトやmachinesetオブジェクトは、OpenShiftクラスタが自身を構成するマシン、OSを管理するためのオブジェクトですが、
UPIでの構築ではマシンは自分で用意するので不要です。削除しておきます。

```bash
$ rm .upi/openshift/99_openshift-cluster-api_master-machines-*.yaml
$ rm .upi/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
```

### Ignitionファイルの作成

次に、マシン起動時の初期処理を定義する、Ignitionファイルを作成します。

Ignitionはcloud-initみたいなものですが、OS起動処理の、より初期のフェーズで実行されるため低レベルな部分の初期化処理が可能になっています。詳しくは以下をご参照ください。

* https://coreos.com/ignition/docs/latest/
* https://coreos.com/ignition/docs/latest/what-is-ignition.html#ignition-vs-coreos-cloudinit

ここで作成したIgnitionファイルを、これから用意するEC2インスタンスのUserDataに設定することで、OpenShiftクラスタのノードになるための処理が起動時に実行されるというわけです。

以下コマンドを実行することで、これまで作成してきた設定ファイル、APIオブジェクトを元に、Iginitionファイルを生成できます。

```bash
$ openshift-install create ignition-configs --dir=.upi
```

上記により、.upiディレクトリは以下のようになります。

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

前の手順で作成した様々なAPIオブジェクトのyamlファイルは、*.ignファイルの中にbase64でエンコードされて埋め込まれています。

埋め込まれたAPIオブジェクトファイルは、マシン起動時に、Ignitionによりマシン内のファイルシステムに展開されます。

## クラスタIDの取得

OpenShiftは、自身の管理化にあるAWSのリソースを、クラスタごとのIDのついたタグで識別します。

例えば、OpenShift上の管理用コンテナは、クラスタIDでタグ付けされたRoute53ゾーンを取得してドメイン名を管理したりします。

後段の手順でAWSのリソースを作成するときにタグ付けする必要があるため、ここでそのIDを取得し控えておきます。

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

# IDを控える
$ CLUSTER_ID=$(jq -r .infraID .upi/metadata.json)
$ echo $CLUSTER_ID
upi-1-1-xxxx
```

## AWSでインフラを作成する

クラスタの構築に必要なファイルは作成しましたので、次にOpenShiftを載せるインフラをAWSに構築していきます。

* マシン間が適切に通信できる
* 各マシンがインターネットに接続できる
* DNSに適切なエントリが追加されている
* 各マシンに適切なIAMロールが付与されている
* 各マシンのUserDataに適切なIgnition設定ファイルが設定されている

上記が満たされていればどんな構成でも構築できるんじゃないかと思いますが、今回は例としてプライベートサブネットやLBなども設定しています。

とても大雑把な図ですが、以下のようなインフラを作ってみます。

![Simple Architecture Overview](./images/upi-overview.png)

### VPC、サブネット、ロードバランサーの作成

まず、VPC、サブネットを作成します。今回の構成は以下のようなものです。

* プライベート用、パブリック用、二つのサブネットを作成
* プライベートサブネットはNAT Gatewayで、パブリックサブネットはInternet Gatewayで、それぞれインターネットに接続
* パブリックなサブネットに、マスター用の外部ロードバランサーを作成、`6443`ポートを使用
* プライベートなサブネットに、マスター用の内部ロードバランサーを作成、`22623`ポートを使用
* Route53のプライベートゾーンを作成
  * プライベートゾーンに「Key=kubernetes.io/cluster/<Cluster ID>,Value=owned / Key=Name,Value=<Cluster ID>-int"」でタグ付け
  * こうしておくと、OpenShift構築後に、OpenShiftのDNS管理機能がプライベートゾーンを見つけて、必要なDNS登録を行ってくれるので便利
* ロードバランサーをDNSに登録
  * 外部ロードバランサー: `api.<クラスタ名>.<ベースドメイン>` > 外部、内部DNSどちらも登録
  * 内部ロードバランサー: `api-int.<クラスタ名>.<ベースドメイン>` 内部DNSのみ登録

Terraformの定義ファイルを作成したので、これを適用すれば上記のネットワークが作成されます。

```bash
$ git clone https://github.com/literalice/terraform-aws-openshift-upi
$ cd terraform-aws-openshift-upi

$ cat terraform.tfvars

$ cat <<EOF > terraform.tfvars
config_dir = ".upi" # openshift-install時に--dirオプションで指定したディレクトリを設定
blacklist_az = ["ap-northeast-1a"] # お持ちのAWSアカウント、対象リージョンで、使用できないAZがある場合はここに指定する
EOF

$ terraform plan -target module.network
$ terraform apply -target module.network
```

### BootStrapノードの作成

次に、上記で作成したサブネットに、BootStrapノードを配置します。

ここでの作業は、以下の通りです。

* `openshift-install` コマンドで生成したIgnitionファイル「bootstrap.ign」を、インターネットから取得できる場所に配置する。
  * ここでは、S3に配置する。
* Red Hat CoreOSのAMI( `rhcos-410.*-hvm` )を指定し、パブリックなサブネットにEC2インスタンスを起動する
  * 以下参照のこと: [AMI一覧](https://docs.openshift.com/container-platform/4.1/installing/installing_aws_user_infra/installing-aws-user-infra.html#installation-aws-user-infra-rhcos-ami_installing-aws-user-infra)
* 以下のIgnitionファイルを作成し、UserDataに指定することで、S3からIgnitionファイルを取得できるようにする
* BootStrapノードは一時的なマスターとして動作するので、上記で作成したロードバランサーに登録する

```json
{
    "ignition": {
        "config": {
            "replace": {
                "source": "s3//<バケット名>/bootstrap.ign",
                "verification": {}
            }
        },
        "timeouts": {},
        "version": "2.1.0"
    },
    "networkd": {},
    "passwd": {},
    "storage": {},
    "systemd": {}
}
```

こちらもTerraformの定義ファイルを作成したので、 前手順に引き続き以下を適用すればBootStrapノードが作成されます。

```bash
$ terraform plan -target module.bootstrap
$ terraform apply -target module.bootstrap
```

この時点で、BootStrapノードにSSHしてログを確認してみると、以下のようにetcd起動待ちになっていることが分かります。

```
$ ssh  core@<bootstrap ip>
Red Hat Enterprise Linux CoreOS 410.8.20190627.0
WARNING: Direct SSH access to machines is not recommended.

---
This is the bootstrap node; it will be destroyed when the master is fully up.

The primary service is "bootkube.service". To watch its status, run e.g.

  journalctl -b -f -u bootkube.service
[core@ip-10-0-103-163 ~]$ journalctl -b -f -u bootkube.service
-- Logs begin at Sat 2019-06-29 01:07:44 UTC. --
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.807422       1 bootstrap.go:86] Version: 4.1.3-201906181537-dirty (b2ee2cf36a40ae41dc98d1e880faa8279e0feba2)
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.809829       1 bootstrap.go:141] manifests/machineconfigcontroller/controllerconfig.yaml
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.813866       1 bootstrap.go:141] manifests/master.machineconfigpool.yaml
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.814253       1 bootstrap.go:141] manifests/worker.machineconfigpool.yaml
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.814597       1 bootstrap.go:141] manifests/bootstrap-pod-v2.yaml
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.815050       1 bootstrap.go:141] manifests/machineconfigserver/csr-bootstrap-role-binding.yaml
Jun 29 01:10:29 ip-10-0-103-163 bootkube.sh[1407]: I0629 01:10:29.815460       1 bootstrap.go:141] manifests/machineconfigserver/kube-apiserver-serving-ca-configmap.yaml
Jun 29 01:10:30 ip-10-0-103-163 bootkube.sh[1407]: Starting etcd certificate signer...
Jun 29 01:10:37 ip-10-0-103-163 bootkube.sh[1407]: 6188a26fd32c283692a8109a415257ca4d8eceda8d1f3ce7ab331a56a2a98eea
Jun 29 01:10:37 ip-10-0-103-163 bootkube.sh[1407]: Waiting for etcd cluster...
```

前述の通り、etcdクラスタを提供するのはマスターノードです。マスターノードを作成して起動する必要があります。

### Control Planeの作成

次に、プライベートなサブネットに、マスターノードを作成し、クラスタのControl Planeを起動します。

ここでの作業は、以下の通りです。

* Red Hat CoreOSのAMI( `rhcos-410.*-hvm` )を指定し、プライベートなサブネットにEC2インスタンスを起動する
* 以下のIgnitionファイルを作成し、UserDataに指定することで、BootStrapノードからIgnitionファイルを取得できるようにする
* マスターノードをロードバランサーに登録する
* マスターノードのIPを、etcdのドメイン名としてDNSに登録する

```json
{
    "ignition": {
        "config": {
            "append": [
                {
                    "source": "https://<api-int-domain>:22623/config/master",
                    "verification": {}
                }
            ]
        },
        "security": {
            "tls": {
                "certificateAuthorities": [
                    {
                        "source": "<ca-bundle>",
                        "verification": {}
                    }
                ]
            }
        },
        "timeouts": {},
        "version": "2.2.0"
    },
    "networkd": {},
    "passwd": {},
    "storage": {},
    "systemd": {}
}
```

ここで、`<api-int-domain>`は内部ロードバランサーのIP、`<ca-bundle>`は、`.upi/master.ign`に記載されている、`data:text/plain;charset=utf-8;base64,ABC…​xYz==`という形式のBase64でエンコードされた証明書です。

正しく指定していれば、マスターノードが起動する時に、このIgnitionファイルの指定に従い、内部ロードバランサーの後ろにいるBootStrapノードから必要なリソースが取得され、Control Planeが起動されるはずです。

これも、Terraformの定義ファイルを作成したので、これを適用すればControl Planeが作成されます。

```bash
$ cd terraform-aws-openshift-upi
$ terraform plan -target module.controlplane -var "config_dir=.upi"
$ terraform apply -target module.controlplane -var "config_dir=.upi"
```

BootStrapのログを眺めて、etcdを参照できていることを確認してみます。

```
$ ssh  core@<bootstrap ip>
Red Hat Enterprise Linux CoreOS 410.8.20190627.0
WARNING: Direct SSH access to machines is not recommended.

---
This is the bootstrap node; it will be destroyed when the master is fully up.

The primary service is "bootkube.service". To watch its status, run e.g.

  journalctl -b -f -u bootkube.service
[core@ip-10-0-103-163 ~]$ journalctl -b -f -u bootkube.service

# ..何か進む
```

以下のコマンドが正常に返れば、Control Planeは起動に成功しています。

```bash
$ openshift-install wait-for bootstrap-complete --dir=.upi --log-level debug

DEBUG OpenShift Installer v4.1.3-201906191409-dirty 
DEBUG Built from commit 0b091f9396ddebcb0ab798d31eaa5b29a3c1148d 
INFO Waiting up to 30m0s for the Kubernetes API at https://api.<domain>:6443... 
INFO API v1.13.4+abe1830 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
DEBUG Bootstrap status: complete                   
INFO It is now safe to remove the bootstrap resources 
```

上記に記載があるように、この時点でBootStrapノードは削除できます。

```bash
$ terraform destroy module.bootstrap
```

### ocコマンドでAPIにアクセスできることを確認

Control Planeが起動しているので、ocコマンドでAPIにログインできるはずです。確認してみましょう。

```bash
# インストール時に作成された認証情報を使用する(oc loginしない)
$ export KUBECONFIG=.upi/auth/kubeconfig
$ oc status # OpenShift APIの準備ができるまでエラーが返る
```

これで、Control Planeがデプロイできました。

なお、この時点で、OpenShiftにデプロイされた[Operatorコンテナ](https://github.com/openshift/cluster-ingress-operator)により、インターネットからOpenShift上のアプリケーションにアクセスするためのELBやRoute53への登録が実施されています。

### ワーカーノードの用意

OpenShiftのIngress Routerなど、一部のインフラコンポーネントは、マスターノードではなくワーカーノードにデプロイされます。

```
$ oc get pods -A | grep Pending
```

このように、一部、デプロイがPendingになっているものがありますね。これらのPodは、ワーカーノードを追加しないと実行されません。

OpenShift 4では、AWSなど、[machine-api-operator](https://github.com/openshift/machine-api-operator)が対応しているプラットフォームであれば、
MachineSetオブジェクトをOpenShiftにデプロイすることで、OpenShift自身がワーカーノードを立ち上げてクラスタに追加してくれます。

[ドキュメント](https://docs.openshift.com/container-platform/4.1/machine_management/creating-machineset.html)を参考に、以下のようなMachineSetオブジェクトを追加して、ワーカーノードを追加してみましょう。

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
      machine.openshift.io/cluster-api-machineset: upi1-xxx-worker-ap-northeast-1b # <Cluster ID>-worker-<ワーカーを作成するAZ名>
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: upi1-xxxx # Cluster IDを追加
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: upi1-xxx-worker-ap-northeast-1b # <Cluster ID>-worker-<ワーカーを作成するAZ名>
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/worker: ""
      providerSpec:
        value:
          ami:
            id: ami-0906ab32ecf300238 # マスターノードと同じAMI ID
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
            id: upi1-xxx-worker-profile # <Cluster ID>-worker-profile (これまでの手順の中でterraformにより作成されている)
          instanceType: m4.large
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ap-northeast-1b
            region: ap-northeast-1
          securityGroups:
            - filters:
                - name: tag:Name
                  values:
                    - upi1-xxx-private # <Cluster ID>-private (これまでの手順の中でterraformにより作成されている)
          subnet:
            filters:
              - name: tag:Name
                values:
                  - upi1-xxx-private-0 # <Cluster ID>-private-0 (これまでの手順の中でterraformにより作成されている)
          tags:
            - name: kubernetes.io/cluster/upi1-xxx # kubernetes.io/cluster/<Cluster ID>
              value: owned
          userDataSecret:
            name: worker-user-data
```