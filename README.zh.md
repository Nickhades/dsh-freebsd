# FreeBSD 上的 dsh —— 独立覆盖层

本目录存放 **DeepSeek Harness（`dsh`）** 的 FreeBSD 层，已与上游 monorepo 解耦：
把它应用到一个干净的上游检出上，在 FreeBSD 15+ 上重新构建。

上游锚点：`dsh-v0.2.2-rc.5`（`9c2670d3bce5275e0d1610272958121af87787bb`），见
[VERSION](VERSION)。

## 为什么改成覆盖层，而不是整棵 fork

旧的 FreeBSD 发行版是 `deepseek-harness` 的完整 fork。每次上游发版都要合并几千个
提交、把被上游搬走的代码重新 port、再审计十几处散落的 FreeBSD 改动；fork 的历史让
"FreeBSD 到底改了什么" 完全看不出来。

覆盖层只保留这部分增量：

- **6 个补丁**，针对固定的上游提交（构建配置、原生 addon、jail 沙箱、平台运行时、
  无头修复、文档索引）。
- **30 个覆盖文件**，上游树里本来没有（`freebsd/` 运维脚本、setuid jail 助手源码、
  FreeBSD 手册、port）。

其余部分——agent、插件、Web UI、测试——原样来自上游。上游挪动文件时，
`scripts/apply.sh` 会直接报错，而不是悄悄丢掉某个 FreeBSD 修复。

## 环境要求（FreeBSD 15.x，amd64）

```sh
pkg install -y git node24 npm-node24 gmake python3 pkgconf bash ripgrep
npm install -g pnpm@11.28.5
```

- **Node 24** 是上游声明的版本（`engines: >=24.9`）。Node 22.19+ 也能构建和运行，
  但安装时会打印 `Unsupported engine` 警告，且必须重编原生 addon。
- **pnpm 必须用 npm 安装**，不能用 corepack。corepack 装的是原生 `@pnpm/exe`
  启动器，在 FreeBSD 上过不了身份校验
  （`Cannot verify the identity of the @pnpm/exe.freebsd-x64 native binary`）。
- **GNU make**：node-gyp 要在 FreeBSD 上编译 `node-pty`。`scripts/build.sh` 会自动
  在 PATH 前面放一个 `make -> gmake` 的 shim，系统自带的 BSD make 不影响。
- **bash** 是 `terminal-bash` 后端的运行时依赖，FreeBSD 的 `/bin/sh` 不能替代。
- **ripgrep** 提供系统 `rg`；`@vscode/ripgrep` 没有 FreeBSD 二进制，grep/glob
  工具会回退到它。

`sh scripts/check-prereqs.sh` 会逐项检查并打印缺哪个包。

## 构建

```sh
git clone <本覆盖层仓库> ~/dsh-freebsd
cd ~/dsh-freebsd
sh scripts/build.sh
```

`build.sh` 会：拉取 `UPSTREAM_TAG` → 应用覆盖层 → `pnpm install --frozen-lockfile`
→ `pnpm run build` → 校验产物。工作目录是 `.work/tree`，日志在 `.work/logs/`。

GitHub 不可达时（国内网络），用已有检出或镜像：

```sh
# 从本地已有 clone 里取出固定提交（全程不联网）
sh scripts/build.sh --from-local /path/to/deepseek-harness

# 国内镜像
DSH_NPM_REGISTRY=https://registry.npmmirror.com \
DSH_NODE_DISTURL=https://registry.npmmirror.com/-/binary/node \
sh scripts/build.sh --from-local /path/to/deepseek-harness
```

常用参数：`--tree DIR`、`--skip-install`、`--skip-build`、`--no-verify`、
`--registry URL`、`--node-disturl URL`。如果 lockfile 与打过补丁的清单不一致，
`DSH_ALLOW_LOCK_UPDATE=1` 会去掉 `--frozen-lockfile`。

## 运行

构建树：

```sh
cd .work/tree
node --expose-internals apps/cli/lib/bin.js web --host 127.0.0.1 --port 3080 --no-open
node --expose-internals apps/cli/lib/bin.js --help
```

源码树（服务脚本用的方式）：

```sh
pnpm dsh:freebsd web
```

FreeBSD 上 `--expose-internals` 是必须的：`node-addon-require-builtin` 没有
freebsd-x64 预编译包也没有源码回退，HMR 服务只能走内部 ESM loader。

## 补丁内容

| 补丁 | 内容 |
| --- | --- |
| `0001-build-config` | pnpm 的 `supportedArchitectures`（`freebsd` + `wasm32`）、sharp WASM 的 `packageExtensions`、host/client 构建的 8 GiB V8 堆、`node-pty` spawn-helper 补丁、`dsh:freebsd` 脚本、重算后的 lockfile。 |
| `0002-native-system` | `@deepseek-ai/node-addon-system-freebsd-x64`：Node-API `flock(2)` 绑定，以及产出/验证 `native/system/packages/freebsd-x64/bin/system.node` 的构建与测试矩阵。没有它，JSONL 会话存储拿不到跨进程写租约。 |
| `0003-sandbox-jail` | 把 `freebsd-jail` 接入本地沙箱 provider（平台链、静态强制、拒绝签名、runner argv/probe），用 setuid `dsh-jail-run` 后端替换 fail-closed 的 `SANDBOX_UNAVAILABLE`。 |
| `0004-platform-runtime` | 进程检查器的 FreeBSD `ps` 语法、`terminal-bash` 的 bash 硬依赖、`util/ripgrep` 的 `DSH_RIPGREP_PATH`/系统 `rg` 回退、桌面打开器探测、loader 的 FreeBSD `requireInternal` 保护、Web UI 的 Web Crypto polyfill。 |
| `0005-headless-fixes` | FreeBSD 上 sharp 的 WASM 后端在加载前要求 fd 0/1/2 可 stat，修复在这里；serving host 没有桌面打开器时，settings controller 返回文档路径而不是报错。 |
| `0006-postmortem-index` | 把记录该崩溃修复的 postmortem 收进索引。 |

[overlay/](overlay) 下的覆盖文件：

- `freebsd/` —— jail 助手源码、Web 启动/重启脚本、rc.d 服务、一次性安装器、沙箱与
  服务校验脚本。
- `FREEBSD.md`、`freebsd-sandbox.md`、`freebsd-startup-troubleshooting.md`（含
  `.zh`）—— FreeBSD 手册。
- `dsh-freebsd-port/` —— FreeBSD port 树，保留用于打包；目前仍固定旧的 `0.2.1a4`
  distfile，需要重新托管 bundle 后才能与本覆盖层构建出的版本一致。
- 说明 FreeBSD 决策的 agent note 与 postmortem。

CI 工作流、README 品牌文案、fork 专用的 push/sync/audit 脚本刻意不带。

## Jail 沙箱（可选，需 root）

覆盖层构建的是真正的 `jail(2)` 隔离后端，而不是强制 `danger-full-access`：

```sh
# 编译并安装 setuid 助手（root）
cc -O2 -Wall -ljail -o /usr/local/sbin/dsh-jail-run freebsd/dsh-jail-run.c
chmod 4755 /usr/local/sbin/dsh-jail-run

# 助手必须放在非 nosuid 文件系统；/usr 只读时放 /var
cc -O2 -Wall -ljail -o /var/dsh-jail-run freebsd/dsh-jail-run.c
chmod 4755 /var/dsh-jail-run
export DSH_JAIL_RUN_BIN=/var/dsh-jail-run
```

助手通过探测后，本地沙箱 provider 会自动选择 `freebsd-jail`。
`freebsd/run-verify.sh` 跑独立的 10 项隔离检查，`freebsd/run-e2e.sh` 跑 e2e；
两者都需要先装好助手。威胁模型见 [freebsd-sandbox.md](freebsd-sandbox.md)。

## 服务

```sh
sh freebsd/install-service.sh --with-jail-helper   # 安装 + 启动 + 校验
sh freebsd/dsh-web-restart.sh status|restart|stop
```

服务以源码树方式运行 `pnpm dsh:freebsd web`，只绑定 `127.0.0.1`；harness 对
非 loopback 访问返回 HTTP 403，远程访问请走 SSH 隧道。

## 跟随上游升级

1. 改 [VERSION](VERSION)：`UPSTREAM_TAG`、`UPSTREAM_COMMIT`，并递增
   `OVERLAY_VERSION`。
2. 对新树跑 `sh scripts/build.sh`。上游挪过被补丁的文件时，`apply.sh` 会点名
   哪个补丁打不上。
3. 在一个 git 工作树里解冲突（clone 上游 → 应用 → 修 → 提交）。
4. `sh scripts/regen.sh <tree>` 从该树重生成补丁序列和覆盖文件；`--check` 只报告
   漂移不写入。
5. 重新构建，跑 `sh scripts/verify.sh .work/tree`。

## 验证

`sh scripts/verify.sh .work/tree` 检查 CLI 产物、Web UI bundle、FreeBSD flock
addon、jail 助手编译、`--version`，并用临时 `DSH_HOME` 在 loopback 上启动 Web
（要求打印 token 且返回 HTTP 200）。`--tests` 追加定向单测（`util/ripgrep`、
`util/native-command`、sandbox local）。

本修订记录的构建在 **FreeBSD 15.1-RELEASE-p7 amd64**、Node 22.23.5、
pnpm 11.28.5 上完成。

## 排错

| 现象 | 原因 / 处理 |
| --- | --- |
| `Cannot verify the identity of the @pnpm/exe.freebsd-x64 native binary` | pnpm 来自 corepack。删掉后 `npm install -g pnpm@11.28.5`。 |
| `Unsupported engine` 警告 | Node 低于 24.9。仍可构建；安装 `node24` 走受支持版本。 |
| `FATAL ERROR: Ineffective mark-compacts near heap limit`（exit 134） | V8 堆上限，不是内核 OOM。构建已固定 8 GiB；先关掉吃内存的进程。 |
| `tsc -b` 在已不存在的包上报错 | 复用的树里残留 `node_modules`/`lib` 空壳。换新的 `.work/tree`，或 `pnpm run clean`。 |
| grep/glob 报找不到 rg | `pkg install ripgrep`；覆盖层会回退到系统 `rg`。 |
| `SANDBOX_UNAVAILABLE` | setuid `dsh-jail-run` 没装或不可执行，见 jail 一节。 |
