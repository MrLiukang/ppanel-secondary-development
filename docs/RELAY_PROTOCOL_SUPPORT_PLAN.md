# Relay 多协议支持与统一 Sidecar 开发方案

版本：v1.0

日期：2026-07-12

## 1. 目标

在现有 PPanel 中转订阅能力上增加更多上游协议，同时保持“一个订阅组不创建一个容器”的统一 sidecar 架构。

目标链路：

```text
客户端
  -> PPanel 节点入口端口
  -> ppnode relay inbound
  -> 统一 ppanel-relay-sidecar 本地 SOCKS
  -> 对应协议客户端
  -> 上游节点
```

新增协议必须同时满足四个条件：

1. 能从订阅中正确解析；
2. 能由统一 sidecar 启动并转发；
3. 能进行协议级健康检查；
4. 只有健康节点才同步到节点管理和用户订阅。

## 2. 当前基线

当前统一 sidecar 已支持：

| 协议 | 订阅解析 | sidecar 运行 | 健康检查 | 节点同步 |
| --- | --- | --- | --- | --- |
| AnyTLS | 已支持 | 已支持 | 已支持 | 已支持 |
| VLESS + TLS | 已支持 | 已支持 | 已支持 | 已支持 |
| VLESS + XHTTP | 已支持 | 已支持 | 已支持 | 已支持 |

当前仅解析但没有完整运行支持：

| 协议 | 当前状态 |
| --- | --- |
| Trojan | 可解析，未接入 sidecar |
| Shadowsocks | 未完成统一 sidecar 适配 |
| VMess | 未完成统一 sidecar 适配 |
| Hysteria/Hysteria2 | 未完成统一 sidecar 适配 |
| TUIC | 未完成统一 sidecar 适配 |
| SOCKS/HTTP 上游 | 未完成统一 sidecar 适配 |

## 3. 协议支持优先级

### P0：Trojan

优先实现 Trojan，原因是：

- 当前订阅解析器已经能够得到 Trojan 的目标地址、端口、密码、SNI 和 TLS 信息；
- 运行时可以使用 Xray outbound，不需要再引入独立容器；
- TCP 转发模型与当前 VLESS/XHTTP 类似，改造风险最低。

### P1：Shadowsocks、SOCKS、HTTP

这几类协议适合使用独立的轻量客户端或 Xray outbound：

- Shadowsocks：支持 TCP，后续补充 UDP；
- SOCKS：直接建立上游 SOCKS 链路；
- HTTP：支持 CONNECT 代理。

### P2：VMess、Hysteria2、TUIC

这些协议需要重点验证：

- Xray/sing-box 当前版本兼容性；
- UDP 传输模型；
- TLS、QUIC、Reality 或特殊 transport 参数；
- 客户端镜像体积和运行资源。

## 4. 统一 Sidecar 架构

### 4.1 容器模型

所有订阅组和协议继续运行在一个容器：

```text
ppanel-relay-sidecar
  ├── relay supervisor
  ├── anytls-client
  ├── xray
  ├── sing-box（仅在确有协议需求时加入）
  └── generated runtime configs
```

订阅组不再对应容器，而对应运行时配置域：

```text
group 1 -> 31001-31099
group 2 -> 31101-31199
group 3 -> 31201-31299
```

同一组中的规则按照规则顺序分配本地 SOCKS 端口。控制端 relay 规则只连接本地 SOCKS，不直接携带上游密码、UUID 或 SNI。

### 4.2 运行时配置

manager 每次轮询控制端后生成：

- `runtime.sh`：启动和监控各协议客户端；
- `xray.json`：VLESS、Trojan、Shadowsocks 等 Xray outbound；
- `sing-box.json`：只有 Xray 无法稳定支持的协议才使用；
- `runtime-manifest.json`：记录组 ID、规则 ID、协议、端口和配置摘要，不记录明文密码。

配置生成必须是幂等的：配置摘要不变时不重启 sidecar，配置改变时只重载对应运行时。

### 4.3 进程管理

统一 sidecar 内增加 supervisor，负责：

- 启动协议进程；
- 捕获退出状态；
- 单个规则失败时只标记该规则，不退出整个容器；
- 处理 SIGTERM 和优雅退出；
- 限制单规则重启频率，避免上游异常造成重启风暴。

初期可以继续使用生成脚本，协议数量超过三类后再切换为 Go supervisor，避免 shell 脚本承担复杂状态管理。

## 5. 数据模型改造

### 5.1 订阅规则

继续保留上游原始字段：

- `target_protocol`
- `target_address`
- `target_port`
- `target_password`
- `target_uuid`
- `target_security`
- `target_sni`
- `target_transport`
- `target_path`
- `target_xhttp_mode`
- `target_allow_insecure`

新增通用字段：

- `target_alpn`
- `target_flow`
- `target_cipher`
- `target_method`
- `target_plugin`
- `target_plugin_opts`
- `target_server_name`
- `target_udp`

字段只在对应协议的高级模式下显示，普通协议不展示无关字段。

### 5.2 规则状态表

建议新增 `relay_subscription_group_rule_status`：

| 字段 | 说明 |
| --- | --- |
| `id` | 主键 |
| `group_id` | 订阅组 ID |
| `rule_id` | 规则 ID |
| `protocol` | 协议 |
| `status` | healthy/unhealthy/disabled |
| `last_check_at` | 最近检查时间 |
| `last_success_at` | 最近成功时间 |
| `failure_count` | 连续失败次数 |
| `last_error` | 最近错误摘要 |
| `runtime_port` | sidecar 本地 SOCKS 端口 |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

节点管理只同步 `status=healthy` 的记录。

## 6. 健康检查方案

健康检查分三层：

### 第一层：本地运行时

- 本地 SOCKS 端口是否监听；
- 对应协议进程是否存活；
- Xray/sing-box 配置是否加载成功。

### 第二层：上游协议握手

- AnyTLS：AnyTLS 握手和认证；
- VLESS/Trojan：TLS + 协议认证；
- Shadowsocks：加密握手；
- Hysteria2/TUIC：QUIC/认证握手。

### 第三层：实际请求

- 通过本地 SOCKS 请求可配置探测地址；
- 默认地址为 `http://www.google.com/generate_204`；
- 支持管理员配置备用探测地址；
- 连续失败达到阈值后才禁用节点，避免临时网络抖动导致节点闪烁。

## 7. 开发计划

### 阶段一：协议适配抽象

- 抽象 `ProtocolRuntime` 接口：`Validate`、`Render`、`Start`、`Probe`；
- 将现有 AnyTLS 和 VLESS 迁移到统一接口；
- 生成统一 runtime manifest；
- 增加协议和规则级日志字段。

验收：现有 AnyTLS、VLESS/XHTTP 行为不变，统一 sidecar 仍只有一个容器。

### 阶段二：Trojan 支持

- 完善 Trojan URI/YAML 字段解析；
- 生成 Xray Trojan outbound；
- 接入 TLS、SNI、ALPN、allowInsecure；
- 接入健康检查和节点同步；
- 增加单元测试、配置测试和端到端测试。

验收：Trojan 上游可从订阅导入，连接成功才进入节点管理，失败节点不展示给用户。

### 阶段三：Shadowsocks、SOCKS、HTTP

- 增加各协议字段校验；
- 优先使用 Xray outbound，减少外部二进制；
- 增加 TCP 探测；
- 后续再单独验收 UDP。

验收：每种协议至少有一个可用样例和一个错误配置样例，错误规则不能影响其他协议。

### 阶段四：VMess、Hysteria2、TUIC

- 评估 Xray 与 sing-box 的协议覆盖；
- 只为确有必要的协议引入 sing-box；
- 增加 QUIC、UDP、TLS 和资源占用测试；
- 完善 sidecar supervisor 的进程隔离。

验收：单个协议进程异常不会影响其他订阅组，容器重启后规则可恢复，UDP 业务有实际测试结果。

### 阶段五：前端和运维完善

- 协议能力矩阵和配置表单；
- 规则状态、失败原因、最近检查时间；
- 手动重试单条规则；
- 订阅组批量刷新和批量应用；
- sidecar 运行状态和容器日志入口；
- 自动更新、失败重试和告警。

## 8. 验收计划

### 功能验收

- 新增协议可以从 URI、YAML、Base64 订阅中解析；
- 多个订阅组同时应用后，所有入口端口同时监听；
- 同一 sidecar 中同时运行 AnyTLS、VLESS 和新增协议；
- 一个协议失败不会导致其他协议节点消失；
- 健康节点出现在节点管理和用户订阅中；
- 失败节点不进入用户订阅；
- 规则更新不会重复创建节点。

### 协议验收

每个协议至少准备：

- 一个有效上游；
- 一个错误密码或 UUID；
- 一个错误 SNI/TLS 配置；
- 一个不可达地址；
- 一个 UDP 用例（协议支持 UDP 时）。

### 容器验收

- `docker ps` 中只有一个 `ppanel-relay-sidecar`；
- sidecar 重启后全部有效规则自动恢复；
- 配置未变化时不重复重启；
- 单规则失败不会导致容器退出；
- 容器资源使用符合单机部署预算；
- Docker Compose 停止、启动、升级流程可重复。

### 回归验收

- 原有节点订阅不受影响；
- 原有商品节点选择不出现 `undefined`；
- 管理端保存和刷新不丢失规则；
- node 拉取配置后能正确重载；
- 数据库迁移可重复执行；
- 订阅解析失败时不覆盖上一份可用规则。

## 9. 交付标准

一个协议只有在以下内容全部完成后，才能标记为“已支持”：

1. 后端解析测试；
2. sidecar 配置生成测试；
3. 协议握手健康检查；
4. 节点同步测试；
5. Docker 运行测试；
6. 至少一个真实上游端到端测试；
7. 前端配置界面和错误提示；
8. 文档、回滚方案和已知限制。
