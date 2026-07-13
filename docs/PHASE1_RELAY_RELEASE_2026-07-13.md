# PPanel 中转订阅第一阶段发布记录

更新时间：2026-07-13

## 1. 发布范围

本阶段在现有 PPanel 上完善订阅中转能力，不重写原有 Xray Settings、节点管理、商品和订阅系统。

目标链路：

```text
客户端
  -> 入口服务器上的 PPanel Node 监听端口
  -> relay rule
  -> 统一 ppanel-relay-sidecar 的本地 SOCKS 端口
  -> AnyTLS / VLESS / Trojan / Shadowsocks 上游
  -> 公网
```

## 2. 本轮完成的工作

### 2.1 Backend

- 订阅预览和应用增加 5 分钟有效的 `preview_token`。
- Token 绑定订阅组、URL、端口范围、当前 revision 和规则摘要；修改任何字段后必须重新预览。
- Node 内部接口认证改为 `HMAC-SHA256(NodeSecret, server_id)`，不同服务器不能复用认证 token。
- 生产配置显式关闭 `AllowLegacyNodeSecret`，不再接受可访问任意服务器的旧全局密钥。
- 订阅组 Apply、Save、Delete、Sync 和节点配置 override 更新增加数据库级服务器锁，避免并发覆盖。
- 节点表增加 `relay_group_id`、`relay_rule_id` 显式所有权列，不再依赖可编辑标签判断归属。
- 增加 MySQL、PostgreSQL、SQLite 所有权迁移和旧标签回填。
- 管理员普通编辑/删除接口拒绝直接修改托管中转节点。
- 删除服务器时同步清理订阅组和托管节点。
- 修复禁用后重新启用不能重建、最后一个节点删除后缓存未清空、数据库错误被吞掉等问题。
- 统一协议能力校验，预览和应用使用同一套规则。
- 当前支持的上游范围：AnyTLS、Trojan TCP/TLS、Shadowsocks TCP 无插件、VLESS TCP 和基础 XHTTP。
- 对尚未实现的 Reality、WS、gRPC、flow、fingerprint、ALPN、自定义 XHTTP extra、SS 插件等组合明确拒绝，避免生成表面成功但不能运行的节点。

主要提交：`69b8a66 fix: harden relay subscription lifecycle`

### 2.2 统一 Sidecar Manager

- 同一服务器的订阅组集中在一个 `ppanel-relay-sidecar` 容器中运行。
- 配置摘要不变时不重启运行时。
- 新配置构建、校验、启动或监听确认失败时保留旧进程和旧状态。
- 停止失败时保留 PID、配置和状态文件，避免把仍运行的旧实例误报为已删除。
- 新进程只有在 PID 身份和 SOCKS 监听均确认后才提交状态。
- 升级时识别旧版 `port=0` state 和单字段 PID 文件；先删除专用旧 sidecar，再按当前进程身份格式重建，避免 reconcile 永久卡在 `invalid process identity`。
- 单个订阅组健康回报失败不阻塞其他组。
- 显式删除或禁用才停止对应运行时；临时缺字段不会误删旧运行时。
- Docker 构建固定 AnyTLS、Xray、`golang.org/x/net` 和基础镜像版本，禁止 `latest` 与动态 `go mod tidy`。

### 2.3 Frontend

- 保存或修改订阅组后清除旧预览结果，必须重新解析。
- Apply 请求携带后端返回的精确 `preview_token`。
- 节点和节点组选择互斥，提交前清理无效值，修复商品编辑中的 `undefined`。
- 提取共享订阅规则 schema、默认值和归一化逻辑，减少页面之间的重复实现。
- 协议切换时清理不适用于当前协议的字段。
- Shadowsocks 隐藏并清理插件、SNI、allow-insecure 等当前运行时不支持的字段。
- 保留 `sidecar_port` 以及 flow、fingerprint、ALPN 等合同字段；未支持字段不在界面中伪装成可用功能。

主要提交：`8ea33ad fix: align relay management workflows`

### 2.4 Node

- Node 对控制端的每个 GET/POST 请求动态生成绑定 `server_id` 的 HMAC token。
- 保留请求原有的 `server_id`、protocol 和自定义参数。
- 增加跨服务器 token 不同以及全部请求方法携带正确 token 的测试。

主要提交：`bb80c30 fix: bind panel authentication to server id`

### 2.5 生产部署资产

- 生产 PPanel 配置关闭旧 NodeSecret 兼容认证。
- PowerShell 和 Bash 验收脚本强制检查生产认证开关和固定依赖。
- Docker Compose 继续使用单 manager、单统一 sidecar 架构。
- 根仓库前端子模块地址修正为实际承载发布快照的 `ppanel-front-secondary`，保证 `git clone --recursive` 能检出记录的前端 SHA。

根仓库提交：`d9570dd fix: harden production relay deployment`

## 3. 修改范围

本轮提交统计：

- Backend：40 个文件，约 1894 行新增、306 行删除。
- Frontend：13 个文件，约 763 行新增、209 行删除。
- Node：2 个文件，约 175 行新增、6 行删除。
- 根仓库生产资产：Dockerfile、`ppanel.yaml`、两套验收脚本及三个子仓库快照指针。

关键目录：

```text
backend/internal/logic/admin/server/
backend/internal/logic/nodeconfig/
backend/internal/handler/server/
backend/internal/repository/
backend/initialize/migrate/
backend/tools/anytls-sidecar-manager/
front/apps/admin/src/sections/xray-settings/
front/apps/admin/src/sections/product/
node/api/panel/
docker-local/production/
scripts/verify-production-assets.*
```

## 4. 本地验收证据

2026-07-13 执行：

```text
Backend：9 个相关 Go package 全部通过。
Frontend：4 个测试文件、17 个测试全部通过。
Frontend：admin 和 user 两个生产构建通过。
Node：api/panel 测试通过。
Docker：生产资产静态检查通过，Compose config 通过。
Docker：linux/amd64 OCI 镜像构建通过。
git diff --check：各仓库通过。
```

独立代码复核发现生产模板仍允许旧全局 NodeSecret；已通过 `AllowLegacyNodeSecret: false` 修复，并加入静态验收门禁。复核未发现其他有证据的 P0/P1。

## 5. GitHub 发布位置

```text
根仓库 master：d9570dd612231680ac914fad51cc3fb1a0fee905
Backend 快照：cbb84ba01233db1ab958ee910035d943e3afca0d
Frontend 快照：1ed936ee110d2c97984faa2f252f479f9b777b42
Node 快照：5cc56d3ec9e41ae36b97b6e1fb7e883bacf82721
```

## 6. 尚未完成或仍需验证

以下项目不能由单元测试或静态构建证明，必须在生产部署后验证：

- 真实 AnyTLS、Trojan、Shadowsocks 上游通过本地 SOCKS 返回 HTTP 204。
- 客户端经公网入口端口、PPanel Node、sidecar、上游访问公网的完整链路。
- UDP 在各协议客户端中的端到端行为。
- 多实例 Backend 同时 Apply/Health 的运行态并发验证。
- 真实 MySQL/PostgreSQL 存量数据迁移结果；SQLite 迁移已有自动化测试。
- Docker/主机重启后的全部规则自动恢复。

产品层后续项：

- 订阅组页面展示最近探测时间、失败原因和连续失败次数。
- 自动更新调度器完成“定时拉取、解析、预览、原子应用”的完整闭环。
- 健康状态独立持久化、探测重试阈值和 sidecar metrics。
- VMess、Hysteria2、TUIC、SOCKS/HTTP 上游以及 Shadowsocks 插件支持。
- 规则从订阅消失后的节点回收策略。

## 7. 生产发布原则

- `/opt/ppanel` 当前为发布目录而不是 Git 工作区，不能直接 `git pull`。
- 发布前备份 `.env`、渲染后的 `ppanel.yaml`、`node.yml` 和 MySQL 数据。
- 保留现有密钥与管理员密码，不使用安装脚本重新生成。
- 先构建镜像，再按依赖顺序更新 Backend、Node、Web、Manager；数据库和 Redis 不重建数据卷。
- 更新后按“API -> Node 配置 -> 监听端口 -> 本地 SOCKS -> 上游 -> 公网入口”顺序验收。
- 任何边界失败时停止向下猜测，记录首个失败边界、日志和响应。
