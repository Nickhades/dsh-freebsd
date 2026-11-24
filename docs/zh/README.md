# DeepSeek Harness on FreeBSD — 中文使用手册

> 本仓库是 **DeepSeek Harness（`dsh`）0.2.2-rc.5** 的 FreeBSD 15+ 覆盖层、构建流水线和一键桌面应用。
> 它不再维护整棵 fork，只保留相对上游的 FreeBSD 增量，应用到一个干净的上游检出后重新构建。
>
> 仓库：https://github.com/Nickhades/dsh-freebsd
> 发布页：https://github.com/Nickhades/dsh-freebsd/releases/tag/v0.2.2-rc.5
> 英文 README：[README.md](../../README.md) · 中文 README：[README.zh.md](../../README.zh.md)
> 适用系统：FreeBSD 15.x amd64（已在 15.1-RELEASE-p7 验证）

## 目录

1. [这是什么](#1-这是什么)
2. [仓库结构](#2-仓库结构)
3. [环境要求](#3-环境要求)
4. [源码构建](#4-源码构建)
5. [桌面应用（一键启动）](#5-桌面应用一键启动)
6. [Jail 沙箱](#6-jail-沙箱)
7. [服务与远程访问](#7-服务与远程访问)
8. [跟随上游升级](#8-跟随上游升级)
9. [常见问题](#9-常见问题)
10. [验证记录](#10-验证记录)
11. [相关中文文档](#11-相关中文文档)

---

## 1. 这是什么

`dsh` 是 DeepSeek 的开源 agent harness（CLI + Web UI + 插件系统）。上游只支持 Linux/macOS/Windows，
本仓库提供 FreeBSD 15+ 能直接构建、运行和双击启动的完整层：

| 组成 | 说明 |
| --- | --- |
| `patches/` | 6 个补丁：构建配置、FreeBSD flock 原生 addon、jail 沙箱、平台运行时、无头修复、文档索引 |
| `overlay/` | 39 个上游没有的文件：`freebsd/` 运维脚本、setuid jail 助手 C 源码、FreeBSD 手册、port、postmortem |
| `scripts/` | 取上游、应用补丁、构建、验证、打运行时包、打包桌面应用、重生成补丁 |
| `desktop/` | 原生 WebKitGTK 桌面窗口 + 一键启动器 + 安装器 + 截图 |
| `dsh-freebsd-port/` | FreeBSD port 树（仍钉旧的 0.2.1a4 distfile，见第 9 节） |

覆盖层相对 fork 的好处：每次上游发版只需重新应用 6 个补丁；上游挪动文件时 `scripts/apply.sh`
会直接报错，而不是悄悄丢掉 FreeBSD 修复。

## 2. 仓库结构

```
dsh-freebsd/
├── VERSION                 上游 tag/commit、覆盖层版本
├── README.md / README.zh.md
├── patches/                6 个补丁 + series
├── overlay/                覆盖文件（应用补丁后复制进上游树）
│   ├── freebsd/            jail 助手、Web 启动/重启、rc.d、安装器、校验脚本
│   ├── FREEBSD.md(.zh.md)  详细运行手册
│   ├── freebsd-sandbox.md(.zh.md)
│   ├── freebsd-startup-troubleshooting.md(.zh.md)
│   └── dsh-freebsd-port/   FreeBSD port 树
├── scripts/
│   ├── check-prereqs.sh    环境检查
│   ├── fetch-upstream.sh   取固定上游提交
│   ├── apply.sh            应用补丁 + 覆盖文件
│   ├── build.sh            安装依赖 + 构建 + 验证
│   ├── verify.sh           产物/CLI/Web/jail 助手检查
│   ├── bundle.sh           生成自包含运行时包
│   ├── package-desktop.sh  生成桌面安装包
│   └── regen.sh            从工作树重生成补丁序列
├── desktop/                原生桌面应用
└── .work/                  构建产物（gitignored）
```

## 3. 环境要求

```sh
pkg install -y git node24 npm-node24 gmake python3 pkgconf bash ripgrep
npm install -g pnpm@11.28.5
```

- **Node 24** 是上游声明版本（`engines: >=24.9`）。Node 22.19+ 也能构建运行，但会打印
  `Unsupported engine` 警告。
- **pnpm 必须用 npm 安装，不要用 corepack**。corepack 装的是原生 `@pnpm/exe` 启动器，
  在 FreeBSD 上会报 `Cannot verify the identity of the @pnpm/exe.freebsd-x64 native binary`。
- **bash** 是 `terminal-bash` 后端的硬依赖，FreeBSD 的 `/bin/sh` 不能替代。
- **ripgrep** 提供系统 `rg`；`@vscode/ripgrep` 没有 FreeBSD 二进制，grep/glob 会回退到系统 rg。
- **原生桌面窗口**需要 `webkit2gtk-4.1`（本机已装）；没有时启动器回退 Chromium `--app`。
- `gmake`：`build.sh` 会自动在 PATH 前面放 `make -> gmake` 的 shim，不需要手改 PATH。

检查环境：

```sh
sh scripts/check-prereqs.sh
```

## 4. 源码构建

### 4.1 获取代码

```sh
git clone https://github.com/Nickhades/dsh-freebsd.git
cd dsh-freebsd
```

### 4.2 构建

```sh
# GitHub 可达时：脚本会克隆上游 dsh-v0.2.2-rc.5 并应用覆盖层
sh scripts/build.sh

# GitHub 不可达（国内网络）：从已有上游检出取固定提交
sh scripts/build.sh --from-local /path/to/deepseek-harness

# 国内镜像（npm + Node 头文件）
DSH_NPM_REGISTRY=https://registry.npmmirror.com \
DSH_NODE_DISTURL=https://registry.npmmirror.com/-/binary/node \
sh scripts/build.sh --from-local /path/to/deepseek-harness
```

产物在 `.work/tree-final`，日志在 `.work/logs/`。构建树里包含：

- `apps/cli/lib/bin.js`：CLI
- `apps/web/dist`：Web UI
- `native/system/packages/freebsd-x64/bin/system.node`：FreeBSD flock addon
- `freebsd/dsh-jail-run.c`：jail 助手源码

### 4.3 验证

```sh
sh scripts/verify.sh .work/tree-final --tests
```

会检查 CLI 版本、Web bundle、flock addon、jail 助手编译、定向单测，并用临时 `DSH_HOME`
在 loopback 启动 Web、要求 HTTP 200。

### 4.4 运行

```sh
cd .work/tree-final

# Web UI
node --expose-internals apps/cli/lib/bin.js web --host 127.0.0.1 --port 3080 --no-open

# CLI
node --expose-internals apps/cli/lib/bin.js --help

# 源码模式（服务脚本使用）
pnpm dsh:freebsd web
```

`--expose-internals` 在 FreeBSD 上是必须的：`node-addon-require-builtin` 没有
freebsd-x64 预编译包，也没有源码回退。

## 5. 桌面应用（一键启动）

桌面应用是原生 **WebKitGTK** 窗口（不是 Electron）：启动器自动在 loopback 起服务、等
auth token、打开窗口；关窗即停服务。第二次点击会复用已有服务再开一个窗口。

### 5.1 直接下载安装包（推荐）

```sh
curl -LO https://github.com/Nickhades/dsh-freebsd/releases/download/v0.2.2-rc.5/dsh-desktop-0.2.2-rc.5-freebsd-amd64.tar.gz
sha256 dsh-desktop-0.2.2-rc.5-freebsd-amd64.tar.gz
# 应为 9763a3d1859599b9bc0f9f3cee29098cd25596d9c8f3c7b31fbb2d11a24fdc9d

tar -xzf dsh-desktop-0.2.2-rc.5-freebsd-amd64.tar.gz
cd dsh-desktop-0.2.2-rc.5-freebsd-amd64
sh install-desktop.sh --desktop-shortcut
```

安装到当前用户（`~/.local`），不需要 root；`--desktop-shortcut` 会在 XDG 桌面目录
（中文环境通常是 `~/桌面`）放一个快捷方式。

### 5.2 从源码构建安装

```sh
sh scripts/bundle.sh .work/tree-final 0.2.2-rc.5
sh desktop/install-desktop.sh --desktop-shortcut
```

### 5.3 启动

- 桌面图标：`~/桌面/dsh-desktop.desktop`（XFCE 首次可能提示信任，选一次 Trust and Launch）
- 应用菜单：Development → **DeepSeek Harness**
- 终端：`~/.local/bin/dsh-desktop`
- 停止：`~/.local/bin/dsh-desktop --stop`

### 5.4 配置

`~/.config/dsh-desktop/env` 会在每次启动前被 source 并导出：

```sh
# 没有 setuid jail 助手时的逃生口（与手工 dsh 启动器一致）
DSH_PERMISSION_MODE=danger-full-access
# 装好助手后也可以显式指定
# DSH_JAIL_RUN_BIN=/var/dsh-jail-run
```

其他可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `DSH_DESKTOP_HOME` | harness home，默认 `~/.dsh` |
| `DSH_DESKTOP_PORT` | 首选端口，默认 3080；被占用时自动换空闲端口 |
| `DSH_DESKTOP_STATE` | 状态/日志目录，默认 `~/.local/state/dsh-desktop` |
| `DSH_DESKTOP_NO_WINDOW=1` | 只起服务不开窗（诊断用） |

### 5.5 日志与状态

```sh
~/.local/state/dsh-desktop/server.log
~/.local/state/dsh-desktop/window.log
```

### 5.6 卸载

```sh
# 源码树
sh desktop/install-desktop.sh --uninstall
# 安装包解压目录
sh install-desktop.sh --uninstall
# 如要彻底清理用户数据，再删：
# ~/.local/state/dsh-desktop  ~/.config/dsh-desktop  ~/桌面/dsh-desktop.desktop
```

### 5.7 安全说明

- Web UI 只绑定 `127.0.0.1`；非 loopback 访问会被信任围栏拒绝（HTTP 403），远程访问请用 SSH 隧道。
- 没有 setuid jail 助手时受限模式会 fail-closed。`danger-full-access` 只是文档化的逃生口，
  装好助手后请删掉 env 文件里的那一行。
- 桌面窗口使用独立 WebKitGTK 进程，不经过 Electron 或远程浏览器。

## 6. Jail 沙箱

推荐安装 setuid 助手，让 `code` / `mini` / `standard` 命令在 jail 里运行：

```sh
cd .work/tree-final
cc -O2 -Wall -ljail -o /usr/local/sbin/dsh-jail-run freebsd/dsh-jail-run.c
chmod 4755 /usr/local/sbin/dsh-jail-run

# /usr 只读时放 /var
cc -O2 -Wall -ljail -o /var/dsh-jail-run freebsd/dsh-jail-run.c
chmod 4755 /var/dsh-jail-run
export DSH_JAIL_RUN_BIN=/var/dsh-jail-run
```

助手必须放在**非 nosuid** 文件系统；不要放 `/tmp`。安装后用以下脚本验证：

```sh
sh freebsd/run-verify.sh   # 10 项隔离检查
sh freebsd/run-e2e.sh      # e2e
```

威胁模型和完整步骤见 [overlay/freebsd-sandbox.zh.md](../../overlay/freebsd-sandbox.zh.md)。

## 7. 服务与远程访问

```sh
# 安装 + 启动 + 校验（需要 root；可选装 jail 助手）
sudo sh freebsd/install-service.sh --with-jail-helper

# 日常操作
sh freebsd/dsh-web-restart.sh status|restart|stop
```

服务默认监听 `127.0.0.1:3080`。远程访问：

```sh
ssh -L 3080:127.0.0.1:3080 user@freebsd-host
# 浏览器打开 http://localhost:3080
```

不要在服务前面挂反向代理或用 LAN IP，信任围栏会返回 403。

## 8. 跟随上游升级

1. 改 `VERSION`：`UPSTREAM_TAG`、`UPSTREAM_COMMIT`，递增 `OVERLAY_VERSION`。
2. 对新树跑 `sh scripts/build.sh`。若上游挪动了被补丁的文件，`apply.sh` 会指名哪个补丁打不上。
3. 在 git 工作树里解冲突（clone 上游 → 应用 → 修 → 提交）。
4. `sh scripts/regen.sh <tree>` 重生成补丁序列和覆盖文件；`--check` 只报告漂移不写入。
5. 重新构建，跑 `sh scripts/verify.sh .work/tree-final --tests`。

## 9. 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| `Cannot verify the identity of the @pnpm/exe.freebsd-x64 native binary` | pnpm 来自 corepack；删除后 `npm install -g pnpm@11.28.5` |
| `Unsupported engine` 警告 | Node 低于 24.9；仍可构建，建议装 `node24` |
| `FATAL ERROR: Ineffective mark-compacts near heap limit`（exit 134） | V8 堆上限，不是内核 OOM；构建已固定 8 GiB，先关掉吃内存的进程 |
| `tsc -b` 在已不存在的包上报错 | 复用的树残留 `node_modules`/`lib` 空壳；换新的 `.work/tree-final` 或 `pnpm run clean` |
| grep/glob 报找不到 rg | `pkg install ripgrep`，覆盖层会回退系统 `rg` |
| `SANDBOX_UNAVAILABLE` | 没装 setuid `dsh-jail-run`；见第 6 节，或临时用 `danger-full-access` |
| 双击桌面图标没反应 | 首次先选 Trust and Launch；查看 `~/.local/state/dsh-desktop/server.log` |
| 桌面窗口空白 | 确认 `webkit2gtk-4.1` 已装；缺窗口二进制时启动器会用 Chromium `--app` |
| 端口 3080 被占用 | 启动器自动换空闲端口；不影响已运行实例 |
| port 的 distfile 版本旧 | `dsh-freebsd-port/` 仍钉 0.2.1a4；新的运行时包和 pkg-plist 碎片可由 `scripts/bundle.sh` 生成，需上传 release 后更新 port |

## 10. 验证记录

2026-11-24 在 **FreeBSD 15.1-RELEASE-p7 amd64**（16 核 / 16 GB，Node 22.23.5，
pnpm 11.28.5）上从干净上游 `dsh-v0.2.2-rc.5` 重建：

- `pnpm install` 复用 1428 个 store 包，并用 FreeBSD 头文件编译 `node-pty`
- `pnpm run build`：**10/10 gate**，**371 个 client artifact**
- 暖缓存构建 213 s；冷启动端到端 360 s
- `scripts/verify.sh --tests` 全 PASS：CLI `0.2.2-rc.5`、Web bundle、flock addon、
  jail 助手 `-ljail` 编译、定向测试、loopback HTTP 200
- 桌面窗口在原生 WebKitGTK 中渲染出完整 UI（截图：[desktop/screenshot.png](../../desktop/screenshot.png)）
- 发布包：`dsh-desktop-0.2.2-rc.5-freebsd-amd64.tar.gz`，155,808,809 B，
  SHA256 `9763a3d1859599b9bc0f9f3cee29098cd25596d9c8f3c7b31fbb2d11a24fdc9d`

## 11. 相关中文文档

- [README.zh.md](../../README.zh.md)：仓库总览
- [overlay/FREEBSD.zh.md](../../overlay/FREEBSD.zh.md)：FreeBSD 安装与运行手册
- [overlay/freebsd-sandbox.zh.md](../../overlay/freebsd-sandbox.zh.md)：jail 沙箱部署与运维
- [overlay/freebsd-startup-troubleshooting.zh.md](../../overlay/freebsd-startup-troubleshooting.zh.md)：启动排错
- [overlay/dsh-freebsd-port/README.zh.md](../../overlay/dsh-freebsd-port/README.zh.md)：port 打包

## License

MIT，见 [LICENSE](../../LICENSE)。上游代码版权归 DeepSeek 及贡献者所有。
