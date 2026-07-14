# Azure CycleCloud + Slurm Terraform Lab

このディレクトリは、Zenn 記事「Azure CycleCloud で Slurm クラスタを展開/活用」で作成している Azure 基盤部分を、Terraform とシェルスクリプトで一括展開するための作業セットです。自動化の対象は記事の「CycleCloud サーバの初期設定」の直前までです。

## 何を自動化するか

- Resource Group
- User Assigned Managed Identity と RBAC
- VNet / Subnet / NSG
- NAT Gateway
- CycleCloud 管理用 Storage Account + Private Endpoint + Private DNS
- Azure NetApp Files account / pool / volume
- Azure Marketplace の CycleCloud VM

Terraform apply の完了後は、CycleCloud VM と前段 Azure リソースがそろった状態で停止します。記事の「4. CycleCloud サーバの初期設定」以降は、CycleCloud ポータルにアクセスして手動で進めてください。

## 事前条件

- Azure CLI でサインイン済みであること
- Terraform がインストール済みであること
- CycleCloud Marketplace イメージを利用可能なサブスクリプションであること
- Bastion / VPN / ExpressRoute など、CycleCloud VM のプライベート IP へ到達する経路があること

この環境では Terraform 1.14 系と Azure CLI 2.82 系で確認しています。

## 使い方

1. 設定ファイルを複製します。

```bash
cd /home/hikurais/cyclecloud-deploy-tf
cp config/cyclecloud.env.example.org config/cyclecloud.env
```

2. config/cyclecloud.env を環境に合わせて編集します。

3. Azure へログインします。

```bash
az login
```

4. 一発展開します。

```bash
./scripts/deploy.sh
```

このコマンドは Terraform apply 後、https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/service-principals?view=cyclecloud-8 の "Configuration" に入る手前までを実施します。

必要であれば env ファイルのパスを引数で渡せます。

```bash
./scripts/deploy.sh /path/to/your.env
```

以降の CycleCloud 初期設定と Slurm クラスタ作成は、この作業セットでは自動実行しません。

## 補助コマンド

```bash
./scripts/plan.sh
./scripts/destroy.sh
```

## デプロイ後に使う主な値

```bash
cd /home/hikurais/cyclecloud-deploy-tf/infra
terraform output
```

特に次の出力は、CycleCloud 側の手動設定時に参照できます。

- managed_identity_client_id
- storage_account_name
- cyclecloud_portal_url
- anf_mount_ip
- anf_export_path

## CycleCloud 側の次手順

1. private network 経由、または Bastion トンネル経由で CycleCloud ポータルへアクセスします。
2. その後、https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/service-principals?view=cyclecloud-8 の "Configuration" の章に沿って Slurm クラスタを作成します。

## env 変数

- `CYCLECLOUD_ADMIN_PASSWORD`: bootstrap を試す場合だけ使う値です。今回の既定フローでは未使用です。
- `SLURM_*`: 手動で Slurm クラスタを作るときの入力値として流用できます。

GPU を使わない場合は `SLURM_GPU_MAX_NODES="0"` のままで構いません。

## 参考にした記事とドキュメント

- https://zenn.dev/kaikurahky/articles/5252f707f38e2f
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/netapp_pool
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/netapp_volume
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account
- https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet