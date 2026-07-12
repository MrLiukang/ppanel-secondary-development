# PPanel 中转订阅与 Xray Relay 改造说明

更新时间：2026-07-12

## 1. 项目目标

本次改造将 3x-ui 常见的“同一台入口服务器按不同端口转发到不同上游节点”能力加入 PPanel，并支持从订阅导入 AnyTLS、VLESS/XHTTP 节点。

典型链路：`客户端 -> A:643 -> SG AnyTLS`、`客户端 -> A:743 -> HK AnyTLS`、`客户端 -> A:1943 -> HK VLESS/XHTTP`。

控制端负责订阅导入、规则保存、入口规则下发和节点管理；统一 relay sidecar 负责连接上游。

## 2. 已完成的功能

### 2.1 订阅导入

- 支持 HTTP/HTTPS 订阅地址。
- 支持 AnyTLS、VLESS、Trojan URI/YAML/Base64 内容解析。
- 支持订阅组起始端口和端口步长。
- 支持预览和手动应用。
- 原始规则保存在 `relay_subscription_groups.rules`，上游字段不会被入口规则覆盖。

### 2.2 控制端规则

- AnyTLS、VLESS/XHTTP 在节点侧转换为本机 SOCKS 出口。
- 每个订阅组使用独立本地端口段：组 1 为 `31001+`，组 2 为 `31101+`。
- 端口公式：`31001 + (group_id - 1) * 100`。
- 应用任意订阅组时，合并同一服务器上所有已启用订阅组，避免后应用的组覆盖先应用的组。

### 2.3 统一 sidecar

当前是一个统一容器，而不是每个订阅组一个容器：

```text
production-anytls-sidecar-manager-1 -> ppanel-relay-sidecar
                                      -> AnyTLS client
                                      -> Xray VLESS/XHTTP
```

- 容器名：`ppanel-relay-sidecar`。
- 使用 host network，内部 SOCKS 端口绑定 `127.0.0.1`。
- AnyTLS 使用现有 `anytls-client`，VLESS/XHTTP 使用 Xray。
- manager 默认每 30 秒轮询控制端，规则变化后重建统一 sidecar。

### 2.4 健康检查和节点同步

当前是“可用才进入节点管理”：

1. sidecar 启动规则。
2. manager 通过本地 SOCKS 访问 `http://www.google.com/generate_204`。
3. 探测成功的规则通过健康回报接口同步到 `nodes` 表。
4. 探测失败的规则不创建节点；已有节点会被禁用。
5. 节点标签为 `relay-group:<group_id>,relay-rule:<rule_id>`，更新不会重复创建。

节点名称使用订阅规则自身的 `remark`；当名称与现有节点冲突时自动追加 ` 2`、` 3` 等递增后缀。备注为空时才回退到订阅组名称。

线上验证：组 1 有 7 个健康节点；组 2 的 18 个 VLESS/XHTTP 上游未通过探测，因此未进入节点管理。

### 2.5 已修复的问题

- AnyTLS YAML 端口为数字类型时解析失败。
- 商品编辑时节点选择出现 `undefined`。
- 入口规则错误使用上游 `inboundTag/outboundTag`。
- 每个订阅组单独创建 sidecar 的架构问题。
- Xray 新版本移除 `tlsSettings.allowInsecure` 导致启动失败。
- 应用第二个订阅组覆盖第一个订阅组 relay 规则。
- 节点进入节点管理前没有可用性判断。

## 3. 当前生产部署

生产目录：`/opt/ppanel`。

主要容器：`production-ppanel-1`、`production-node-1`、`production-anytls-sidecar-manager-1`、`ppanel-relay-sidecar`、`production-mysql-1`、`production-redis-1`。

组 1 已验证入口端口：`643、743、843、943、1043、1143、1243`。使用真实用户 UUID、入口 SNI `fly.xexa1990.top` 测试，上述端口均返回 HTTP `204`。

## 4. 关键数据流

### 应用订阅组

```text
管理员应用
  -> POST /v1/admin/server/relay/subscription/group/apply
  -> 校验并保存 relay_subscription_groups.rules
  -> 合并所有启用订阅组
  -> 保存 server_config_overrides.relay_rules
  -> node 拉取 /v1/server/config
  -> ppnode 重载 relay inbound/outbound
```

### sidecar 运行

```text
manager
  -> GET /v2/server/:server_id/relay-subscription-groups
  -> 生成 runtime.sh 和 xray.json
  -> 启动 ppanel-relay-sidecar
  -> AnyTLS/VLESS 监听 31001+ / 31101+
```

### 健康节点同步

```text
manager
  -> 本地 SOCKS HTTP 探测
  -> POST /v2/server/:server_id/relay-subscription-groups/health
  -> 控制端创建或更新 healthy node
  -> 失败节点不创建或禁用
```

## 5. 组 1 曾经超时的根因

故障证据：控制端配置只返回组 2 的 `1943、2043...`；`ppnode` 日志只显示组 2 监听，没有 `643、743...`；节点管理中的组 1 数据仍存在，但入口没有对应端口。

原因是旧 `Apply` 逻辑直接将当前组赋给 `override.relay_rules`，后应用的组覆盖先应用的组。现在改为查询所有启用组并合并后再下发。

## 6. 未完成和后续计划

- 前端健康状态展示还不完整，目前主要通过节点是否出现在节点管理中判断。
- 订阅组页面还没有展示最近探测时间、失败原因和连续失败次数。
- 自动更新开关已保存，但“定时重新拉取、解析、应用”的调度链路仍需完善。
- 健康检查目前固定使用 `google.com/generate_204`，后续应支持可配置探测地址和 TCP/TLS/HTTP 多级探测。
- Trojan 已可解析，但还没有接入统一 sidecar 运行时。
- UDP 转发尚未完成逐节点端到端验收。
- 失败原因还没有持久化到独立状态表。
- 规则从订阅中消失后的旧节点回收策略仍需补充。

建议下一步：增加 `relay_subscription_group_rule_status` 表、前端状态面板、探测重试/阈值、sidecar metrics，以及 Trojan/UDP 测试。

## 7. 本地验证

```bash
cd backend
go test -vet=off ./internal/logic/admin/server ./internal/handler/server ./tools/anytls-sidecar-manager
git diff --check
```

```bash
docker compose -f docker-local/production/docker-compose.yml config
docker compose -f docker-local/production/docker-compose.yml up -d --build
docker ps
```

## 8. 相关提交

```text
0198925 feat: add relay subscription groups
ae10bde feat: create relay sidecars from subscription groups
76c45fa feat: run relay subscription groups in one sidecar
8b65717 feat: sync only healthy relay nodes
58805cf fix: merge relay groups when applying rules
```

## 9. 安全说明

- 生产密码、订阅 token、数据库密码不得提交到 Git。
- `PPANEL_SECRET_KEY` 仅用于 manager 和控制端内部认证。
- 外部 HTTPS 建议交给 Nginx/Cloudflare，PPanel 和 manager 只使用内部地址。
- 一键安装脚本生成随机密钥，但不会自动配置 DNS、Cloudflare 证书或防火墙。
