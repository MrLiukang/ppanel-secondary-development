# PPanel 二次开发工作区梳理

当前工作区包含三个独立上游仓库，均已切换到二次开发分支：

| 本地目录 | 上游仓库 | 基准分支 | 当前分支 | 最新提交 |
| --- | --- | --- | --- | --- |
| `front` | `https://github.com/perfect-panel/frontend.git` | `main` | `codex/secondary-development` | `69bc1ad fix(auth): align Telegram admin form fields with backend config` |
| `backend` | `https://github.com/perfect-panel/backend.git` | `master` | `codex/secondary-development` | `8cbd1b2 fix(telegram): honor EnableNotify config in notification senders` |
| `node` | `https://github.com/perfect-panel/ppanel-node.git` | `master` | `codex/secondary-development` | `6c3ec13 Merge pull request #29 from perfect-panel/dev` |

## Front

前端是 Bun + Turborepo monorepo：

- `apps/user`: 用户端 Web，Vite + React 19 + TypeScript + TailwindCSS。
- `apps/admin`: 管理端 Web，Vite + React 19 + TypeScript + TailwindCSS。
- `packages/ui`: 共享 UI 组件。
- `packages/typescript-config`: 共享 TypeScript 配置。
- `docs`: VitePress 文档站。

常用命令：

```bash
bun install
bun run dev
bun run build
bun run lint
bun run check
```

单应用入口：

```bash
cd apps/user && bun run dev    # 端口 3000
cd apps/admin && bun run dev   # 端口 3001
```

二开重点通常在：

- `apps/user/src`: 用户端页面、路由、状态和 API 调用。
- `apps/admin/src`: 管理端页面、表格、配置和后台操作。
- `packages/ui`: 两端共享组件和样式规范。
- `functions` / `scripts`: OpenAPI、国际化和构建辅助脚本。

## Backend

后端是 Go 服务端，模块名 `github.com/perfect-panel/server`，核心依赖包含 Hertz、GORM、Asynq、Redis、MySQL/PostgreSQL、Stripe、Telegram Bot、OpenTelemetry。

主要目录：

- `ppanel.go`: 程序入口，调用 `cmd.Execute()`。
- `cmd`: CLI 命令、启动、迁移、版本等入口。
- `apis` / `ppanel.api`: API 定义与聚合。
- `internal/handler`: HTTP handler。
- `internal/logic`: 业务逻辑。
- `internal/model`: 数据模型。
- `internal/repository`: 数据访问。
- `internal/svc`: 服务上下文和依赖注入。
- `queue`: 异步任务。
- `scheduler`: 定时任务。
- `etc`: 配置文件。
- `script` / `generate`: 代码生成。

常用命令：

```bash
go mod download
./script/generate.sh
go test ./...
make linux-amd64
./bin/ppanel-server-linux-amd64 run --config etc/ppanel.yaml
```

二开重点通常在：

- 新 API：先改 `apis`，再运行生成脚本。
- 用户/订单/订阅/支付：优先看 `internal/logic`、`internal/model`、`internal/repository`。
- 后台任务：看 `queue`、`scheduler`。
- 配置和启动链路：看 `cmd`、`internal/config`、`internal/svc`。

## Node

节点服务是 Go + xray-core，模块名 `github.com/perfect-panel/ppanel-node`，用于对接面板并运行代理节点。

主要目录：

- `main.go`: 程序入口，调用 `cmd.Run()`。
- `cmd`: CLI 和服务启动入口。
- `conf`: 配置加载和监听。
- `node`: 节点控制器、证书、任务和面板交互。
- `core`: xray-core 入站、出站、用户和校验封装。
- `api`: 面板 API 通信。
- `limiter`: 限速逻辑。
- `common`: 公共工具。
- `scripts`: 安装和部署脚本。

常用命令：

```bash
GOEXPERIMENT=jsonv2 go build -v -o ./node -trimpath -ldflags "-s -w -buildid="
go test ./...
```

二开重点通常在：

- 面板通信协议：`api`、`node/controller.go`。
- 节点配置生成：`core/inbound`、`core/outbound`、`core/xray.go`。
- 用户同步和限速：`node/user` 相关代码、`limiter`。
- 证书和部署：`node/lego.go`、`scripts`。

## 建议开发顺序

1. 先确定改动归属：纯界面改 `front`，面板业务/API 改 `backend`，节点运行协议改 `node`。
2. 涉及前后端联动时，先从 `backend/apis` 定义接口，再生成后端代码，最后同步前端 API 调用。
3. 涉及节点同步或订阅生效问题时，按边界排查：后端写入 -> API 响应 -> 节点拉取 -> 解码/转换 -> xray 配置更新 -> ack/日志。
4. 每次改动保持在当前仓库的 `codex/secondary-development` 分支上，确认后再按需要提交和推送。
