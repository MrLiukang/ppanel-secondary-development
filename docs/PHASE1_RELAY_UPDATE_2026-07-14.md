# 第一阶段中转订阅功能更新记录

更新时间：2026-07-14

## 本次完成内容

本次更新围绕“新增订阅后自动生成可用节点”和“订阅自动更新”完成了第一阶段闭环。

### 控制端

- 允许保存 `auto_update=true` 的订阅组。
- 保留订阅组的更新间隔、入口起始端口和端口步长。
- sidecar 节点查询接口被调用时，会检查到期的自动更新订阅组。
- 到期后按“拉取订阅、解析规则、签名预览、应用规则”的顺序更新。
- 每个订阅组独立处理，单个上游失败不会阻断其他订阅组。
- 更新成功后刷新订阅组规则版本和更新时间。
- 更新失败会记录订阅组错误日志和失败状态，下一轮继续重试。

### 管理端前端

- 新增或编辑订阅保存成功后，自动刷新订阅组列表。
- 自动定位刚保存的订阅组，避免同名订阅组应用到错误记录。
- 自动执行一次订阅预览和规则应用。
- 没有可用规则时提示“订阅中没有可用的中转节点”，不会提交空规则。
- 规则应用成功后，等待 sidecar 健康检查并同步节点。

### sidecar 和节点

- sidecar manager 按轮询间隔读取控制端配置。
- AnyTLS、VLESS、Trojan、Shadowsocks 规则统一进入同一个 `ppanel-relay-sidecar` 容器。
- 规则先在 sidecar 中建立本地 SOCKS 端口，再由 PPanel Node 的 relay 入口转发。
- SOCKS 健康检查成功后，控制端才创建或启用节点记录。
- 节点名称优先使用订阅规则备注，名称冲突时追加递增后缀。
- 订阅组之间使用独立 sidecar 端口池，避免端口覆盖。

## 新增订阅实际流程

```text
管理端保存订阅
  -> 自动预览并应用
  -> 控制端保存 relay_rules
  -> node 拉取新的 relay_rules
  -> sidecar manager 启动对应上游连接
  -> 本地 SOCKS 健康检查
  -> 控制端创建健康节点
  -> 节点进入节点管理和用户订阅
```

sidecar manager 默认每 30 秒轮询一次。首次应用后，节点通常需要等待一次轮询和健康检查才能出现在节点管理中。

## 自动更新流程

```text
sidecar manager 轮询
  -> GET /v2/server/:server_id/relay-subscription-groups
  -> 控制端判断 auto_update 和 update_interval
  -> 到期订阅重新拉取并应用
  -> manager 使用新规则重载对应运行实例
  -> 其他订阅组保持运行
```

自动更新不会删除其他订阅组的运行实例。规则摘要没有变化时，manager 保留原有进程；规则发生变化时，只更新对应规则。

## 端口和节点规则

- 客户端入口端口来自订阅组的 `listen_port_start + index * listen_port_step`。
- sidecar 内部端口按订阅组分段分配，例如组 1 从 31001 开始，组 2 从 31101 开始。
- sidecar 内部端口不会直接暴露给用户客户端。
- 只有健康检查成功的规则才会创建或启用节点。
- 健康检查失败的已有节点会被禁用，不会继续出现在有效节点中。

## 当前支持范围

- AnyTLS：支持密码、TCP、SNI 基础参数。
- VLESS：支持 TCP、TLS、基础 XHTTP 参数。
- Trojan：支持 TCP、TLS、密码和 SNI 基础参数。
- Shadowsocks：支持 TCP、加密方法和密码；插件能力仍按当前校验规则限制。

尚未作为第一阶段完整验收范围的内容：Reality、gRPC、复杂 WebSocket、完整 UDP 端到端、Hysteria2、TUIC、VMess。

## 验收结果

- 后端中转订阅、节点配置、健康同步测试通过。
- sidecar manager 测试通过。
- 前端 xray-settings 测试 14 项全部通过。
- 管理端 TypeScript 检查通过。
- 生产 Docker 资产静态检查和 Compose 配置检查通过。
- node 全量测试需要使用 `GOEXPERIMENT=jsonv2`，启用后通过。

## 已知限制

- 真实上游线路的 AnyTLS、Trojan、Shadowsocks 端到端连通性仍需在线上使用真实订阅逐条验证。
- 健康探测当前使用固定的 HTTP 204 地址，网络无法访问该地址时可能把实际可用节点判定为失败。
- 自动更新依赖 sidecar manager 正常运行；manager 停止时不会执行自动拉取。
- Docker 重启恢复、UDP 端到端和复杂传输组合需要继续做生产环境验收。

## 本次提交

- Backend：`279c6e1`，实现自动更新和保存后应用支持。
- Frontend：`f3a32cc`，实现新增订阅自动预览和应用。
- Root：`881d356`，更新 backend/front 子模块指针。

## 生产更新原则

线上更新只重建 `ppanel`、`admin-web`、`user-web`、`node` 和 `anytls-sidecar-manager` 镜像，保留 MySQL、Redis 以及 `/opt/ppanel` 配置和数据卷。更新完成后必须检查容器状态、manager 日志、sidecar 容器和节点健康状态。
