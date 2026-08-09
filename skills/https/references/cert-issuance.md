---
name: cert-issuance
description: Use when issuing or renewing a Let's Encrypt wildcard cert with acme.sh via DNS-01 — covers NS lookup to identify DNS provider, creating minimum-privilege RAM/Cloudflare/DNSPod credentials with IP allowlist policy, staging dry-run, production issue with --keylength ec-256 --dnssleep 120, --install-cert to a fixed path with reloadcmd hook, --cron --force rehearsal, and acme.sh cron lifecycle. Also covers DNS-01 vs HTTP-01 trade-off (DNS-01 is default; only HTTP-01 works for ICPM-unblocked traffic). Loaded from https/SKILL.md as ref2.
---

# cert-issuance — Let's Encrypt + DNS-01 证书签发

## 加载时机

- 阶段 C 一次性签发证书
- 阶段 F 自动续期演练 / 排查续期失败
- 切换 DNS 托管商 / 给 DNS 凭证收紧权限
- HTTP-01 vs DNS-01 选型时

## 1. 确认 DNS 托管商,选对插件

```bash
dig +short NS example.com
# dig 未安装时(零安装方案):
curl -s 'https://dns.alidns.com/resolve?name=example.com&type=NS'
```

| NS 返回                            | 托管商                 | 插件        | 需要的环境变量                                 |
| ---------------------------------- | ---------------------- | ----------- | ---------------------------------------------- |
| `*.hichina.com`                  | 阿里云云解析           | `dns_ali` | `Ali_Key`、`Ali_Secret`                    |
| `*.ns.cloudflare.com`            | Cloudflare             | `dns_cf`  | `CF_Token`(Zone:DNS:Edit + Zone:Zone:Read) |
| `*.dnspod.net` / `*.dnsv*.com` | 腾讯云 DNSPod          | `dns_dp`  | `DP_Id`、`DP_Key`                          |
| 其他                               | 查 acme.sh dnsapi 列表 | ——        | 按对应文档                                     |

## 2. 创建最小权限凭证

通用原则:**用子账号 / 受限 Token,绝不用主账号密钥**。

- **阿里云**:RAM 控制台 → 身份管理 → 用户 → 创建用户 → 只勾「使用永久 AccessKey 访问」→ 立刻保存 ID 与 Secret(只显示一次)→ 添加权限 `AliyunDNSFullAccess`。若账号开启了「AccessKey 来源网络地址限制」,需把服务器公网 IP 加入白名单或关闭该限制。
- **Cloudflare**:My Profile → API Tokens → Create Token,权限 `Zone:DNS:Edit` + `Zone:Zone:Read`,Zone Resources 限定到目标域名。

更进一步可用条件策略把权限收窄到单个域名 + 单个来源 IP(示例为阿里云自定义策略):

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "alidns:DescribeDomainRecords",
        "alidns:AddDomainRecord",
        "alidns:UpdateDomainRecord",
        "alidns:DeleteDomainRecord"
      ],
      "Resource": "acs:alidns:*:*:domain/example.com",
      "Condition": {
        "IpAddress": { "acs:SourceIp": ["你的服务器IP/32"] }
      }
    }
  ]
}
```

## 3. 签发流程

```bash
# ① 安装 acme.sh(会自动写入 crontab)
curl https://get.acme.sh | sh -s email=you@example.com
source ~/.bashrc

# ② 默认 CA 切到 Let's Encrypt(acme.sh 默认是 ZeroSSL,必须显式切换)
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --register-account -m you@example.com --server letsencrypt

# ③ 载入凭证(从 600 权限的 env 文件读,不写进命令行)
set -a; source /srv/web-docker/secrets/dns.env; set +a
echo "[${Ali_Key:0:6}...]"   # ★ 确认非空再继续,空值是最常见的失败原因

# ④ staging 演练:验证 API 权限与 DNS 写入链路,不消耗正式配额
~/.acme.sh/acme.sh --issue --dns dns_ali \
  -d example.com -d '*.example.com' \
  --keylength ec-256 --dnssleep 120 --staging

# ⑤ 正式签发(仅在 ④ 输出 Cert success 后执行)
~/.acme.sh/acme.sh --issue --dns dns_ali \
  -d example.com -d '*.example.com' \
  --keylength ec-256 --dnssleep 120 --server letsencrypt

# ⑥ 安装证书 + 绑定 reload 钩子(★ 决定 90 天后续期能否自动生效)
~/.acme.sh/acme.sh --install-cert -d example.com --ecc \
  --key-file       /srv/web-docker/certs/privkey.key \
  --fullchain-file /srv/web-docker/certs/fullchain.cer \
  --reloadcmd      "docker exec nginx nginx -s reload"
```

> ❗ `*.example.com` **不包含** `example.com` 本身。裸域和通配符必须在同一条命令里用两个 `-d` 一起签,否则访问裸域会报证书不匹配。

## 4. 自动续期

```bash
# 确认 acme.sh 已装好 cron
crontab -l | grep acme
# 典型内容:0 0 * * * "$HOME/.acme.sh"/acme.sh --cron --home "$HOME/.acme.sh" > /dev/null

# 演练续期链路(强制走一遍完整流程,含 reloadcmd)
~/.acme.sh/acme.sh --cron --force --home ~/.acme.sh

# 查看所有证书与到期日
~/.acme.sh/acme.sh --list
```

Let's Encrypt 证书有效期 90 天,acme.sh 默认在到期前 30 天自动续。**必须演练一次 `--cron --force`**,确认 reload 钩子真的被触发,否则会出现「续期成功但网站仍用旧证书」的静默故障。

## 关联引用

- 主页面 [[../SKILL]]
- 骨架配置 [[skeleton-config]]
- 部署脚本 [[deploy-scripts]]
- 坑位库 [[pitfall-library]]
- 续期认证坑 → [[pitfall-library]] §9.1 证书类
- HTTP-01 vs DNS-01 决策树 → [[pitfall-library]] §11 决策树
