# Folio

自托管媒体库：扫描挂载的视频目录，用 TMDB 补海报与简介，在浏览器（或 Android）里播放。

生产部署是 **一个 Docker 镜像**（Folio + MariaDB），适合群晖等 NAS，也适合任意能跑 Docker 的主机。

## 功能一览

- 海报墙、资料库浏览、作品详情
- 继续观看、想看、播放列表、搜索
- 浏览器内播放；Android 客户端连同一台服务器
- 按文件名刮削（TMDB 主数据源；OMDb / TVDB 可选补充）

## 快速事实

| 项 | 值 |
|----|-----|
| HTTP 端口 | `32700` |
| 持久化数据 | 容器内 `/data`（库在 `/data/mysql`，日志在 `/data/logs`） |
| 片库挂载 | 容器内 `/media`（多个资料库用子目录，如 `/media/movies`） |
| 默认管理员 | 用户名 / 密码均为 `folio`（首次启动自动创建，请尽快修改） |

刮削相关 API Key **不在仓库里**，登录后在 **设置** 页填写，写入数据库。

## 仓库结构

| 路径 | 说明 |
|------|------|
| `Folio-Web` | Vue 3 + Vite 网页端（构建后打进服务端静态资源） |
| `Folio-Client` | Flutter Android 客户端 |
| `Folio-Server` | Spring Boot / Kotlin 后端（JDK 25） |
| `Folio-Website` | 产品官网（静态站） |
| `docker/` | 容器入口脚本 |
| `Dockerfile` | 一体镜像多阶段构建 |
| `build-image.sh` | 跨平台构建并导出 tar |
| `docker-compose.yml` | Compose 一键启动（仍是单个 `folio` 服务） |
| `.env.example` | 容器环境变量示例 |

## 构建一体镜像

**前置：** 本机已安装并启动 Docker，可执行 `docker build`。

```bash
chmod +x build-image.sh   # 首次
./build-image.sh           # 或 ./build-image.sh 0.1.0
```

按提示输入版本号（直接回车为 `0.1.0`），导出路径：`.build/folio-<Tag>.tar`。

等价命令：

```bash
docker build -t folio:0.1.0 .
mkdir -p .build
docker save folio:0.1.0 -o .build/folio-0.1.0.tar
```

Dockerfile 阶段概要：Node 编译 `Folio-Web` → JDK 25 + Gradle 打 Boot JAR → 运行镜像（JRE + MariaDB + 入口脚本）。

## 部署

### 群晖（Docker / Container Manager 图形界面）

1. **映像 → 新增**，导入 `folio-*.tar`
2. 启动时建议：
   - **端口**：主机 `32700` → 容器 `32700`
   - **卷**：可写数据目录 → `/data`；片库共享文件夹 → `/media`（ro 或 rw）
   - **环境变量**：参考 [`.env.example`](.env.example)，至少改掉 `MYSQL_PASSWORD` / `MYSQL_ROOT_PASSWORD`
3. 浏览器打开 `http://<群晖IP>:32700`，用 `folio` / `folio` 登录后：
   - 修改管理员密码
   - 在 **设置** 填写 TMDB API Key（不填无法刮削）
   - 创建资料库（路径选 `/media` 下的子目录）

旧版群晖 Docker 套件没有 Compose「项目」界面时，仍用上述图形配置；有 SSH 且安装了 `docker-compose` 时，也可用下一节的 compose 文件。

### Docker Compose

适合本机、SSH，或支持 Compose /「项目」的 NAS。先确保本机已有镜像（`build-image.sh` 或 `docker load`），再按实际路径改片库挂载。

```bash
# 可选：复制并编辑环境变量
cp .env.example .env

# 片库路径：改 compose 里 MEDIA_HOST_PATH，或在 .env 中设置
# MEDIA_HOST_PATH=/volume1/video

docker compose up -d
```

说明：

- 仍是 **一个** `folio` 容器，数据库在容器内
- 群晖上若只导入 tar、不在 NAS 构建，可去掉 compose 里的 `build: .`，避免去本地 `docker build`
- 旧版 compose 若报版本问题，可在文件顶行加 `version: "3"`

### 通用 `docker run` 示例

```bash
docker run -d --name folio --restart unless-stopped \
  -p 32700:32700 \
  -e MYSQL_PASSWORD='请改成强密码' \
  -e MYSQL_ROOT_PASSWORD='请改成强密码' \
  -v folio_data:/data \
  -v /path/to/your/videos:/media:ro \
  folio:0.1.0
```

## 本地开发

### 网页端

```bash
cd Folio-Web
npm ci
npm run dev
```

开发服务器默认 `http://127.0.0.1:5173`，`/api` 代理到后端 `32700`。

### 后端

需要 **JDK 25**，以及本机可达的 MySQL / MariaDB（开发时没有容器入口脚本，`MYSQL_*` 不生效）。

```bash
cd Folio-Server
./gradlew :app:bootRun          # Windows 也可用 gradlew.bat
```

连接串等见 `Folio-Server/app/src/main/resources/application.yml`，可用 `SPRING_DATASOURCE_*` 覆盖。

打包含前端的 JAR：

```bash
cd Folio-Server
./gradlew :app:bootJar
```

### 片库路径

服务只认 **`/media`**。部署时把宿主机片库映射到容器 `/media`。本机 `bootRun` 同样如此：Windows 上可把片库联接到当前盘的 `\media`（例如 `C:\media`）。

### Android 客户端

```bash
cd Folio-Client
flutter pub get
flutter run
```

连接已部署的 Folio 服务（同一局域网下的 `http://<主机>:32700`）。

### 官网

```bash
cd Folio-Website
npm ci
npm run dev
```

## 元数据来源

刮削在登录后的 **设置** 里配置。三个接口各司其职；详情页只读本地库，打开作品时不会再请求这些 API。

### TMDB（主数据源）

海报、简介、演职员、类型、季集等目录数据只来自 TMDB。刮削时按文件名搜索，分数达到自动匹配阈值就入库。人工匹配候选也来自 TMDB。**不填 API Key 就无法刮削。**

「详情语言」决定写入的中文等文案；「搜索语言」用于按文件名检索。

### OMDb（评分与奖项）

可选。作品已有 IMDb 编号后，在刮削或人工匹配结束时补一层评分，不参与搜片名、不建目录。写入 IMDb 评分与票数、烂番茄新鲜度与观众分、Metacritic，以及奖项简述。未填 Key 则跳过。

### TVDB（仅补充）

可选，需打开开关并填写 API Key（PIN 可空）。只在 TMDB 已匹配成功后，对同一作品补中文译名、外链、评分、部分海报和当前季集信息。TMDB 未配置或匹配失败时，不会用 TVDB 建档。补充失败只记日志，不会把已匹配文件打回失败。

## 环境变量

不设置时使用「默认」列。完整示例见 [`.env.example`](.env.example)。

一体镜像里有两个进程：MariaDB 与 Folio。`MYSQL_*` 给 MariaDB 建库建账号；`SPRING_DATASOURCE_*` 给 Folio 登录。入口脚本会把 `MYSQL_USER` / `MYSQL_PASSWORD` / `MYSQL_DATABASE` 抄到对应的 `SPRING_DATASOURCE_*`，日常一般只改 `MYSQL_PASSWORD`。

注意：`/data/mysql` **已经初始化之后**，再改 `MYSQL_PASSWORD`、`MYSQL_USER`、`MYSQL_DATABASE` **不会**改掉库里已有账号。

本机 `gradlew bootRun` 时没有 MariaDB 入口脚本，请直接配 `SPRING_DATASOURCE_*`（或依赖 `application.yml` 默认值）连你自己的 MySQL。

### 容器里的 MariaDB（`MYSQL_*`）

| 变量 | 默认 | 用途 |
|------|------|------|
| `MYSQL_PASSWORD` | `folio` | 应用连接数据库的密码（首次初始化写入） |
| `MYSQL_ROOT_PASSWORD` | 与 `MYSQL_PASSWORD` 相同 | MariaDB `root` 密码 |
| `MYSQL_USER` | `folio` | 应用数据库用户名 |
| `MYSQL_DATABASE` | `folio` | 数据库名 |
| `MYSQL_DATADIR` | `/data/mysql` | 数据目录，应落在挂载的 `/data` 下 |
| `MYSQL_SOCKET` | `/run/mysqld/mysqld.sock` | 套接字路径，一般不用改 |

### Folio 登录数据库（`SPRING_DATASOURCE_*`）

容器内通常不必设置。仅在连外部库或本机直接跑后端时需要。

| 变量 | 默认 | 用途 |
|------|------|------|
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://127.0.0.1:3306/folio?...` | JDBC 地址 |
| `SPRING_DATASOURCE_USERNAME` | `folio` | JDBC 用户名 |
| `SPRING_DATASOURCE_PASSWORD` | 容器内同 `MYSQL_PASSWORD`；本机默认 `folio` | JDBC 密码 |

### 进程与探测

| 变量 | 默认 | 用途 |
|------|------|------|
| `FOLIO_FFPROBE` | `ffprobe` | 探测视频编码等；镜像已带 ffmpeg |
| `SERVER_PORT` | `32700` | HTTP 端口；改容器内端口时，端口映射右侧需一起改 |
| `JAVA_OPTS` | `-Xms256m -Xmx512m` | JVM 参数 |
| `TZ` | `Asia/Shanghai` | 容器时区（日志用）；库内时间仍为 UTC |
| `FOLIO_LOG_FILE` | 容器内 `/data/logs/folio.log`；本机默认不写文件 | 按天滚动，启动时清理 7 天前文件 |

### 设置页（保存在数据库）

登录后右上角账号菜单 → **设置**。API Key 无仓库默认值。

| 项 | 默认 | 说明 |
|----|------|------|
| TMDB API Key | 空 | 唯一匹配来源；不填无法刮削 |
| 详情语言 | `zh-CN` | TMDB 详情文案 |
| 搜索语言 | `en-US` | 按文件名搜索 |
| OMDb API Key | 空 | 可选；补评分与奖项 |
| 启用 TVDB | 关 | 可选；仅 TMDB 成功后补充 |
| TVDB API Key / PIN | 空 | 打开 TVDB 时再填；PIN 可空 |
| 自动匹配阈值 | `0.72` | 达到则直接采用 |
| 定时扫描间隔 | `10` 分钟 | 只处理新文件或内容已变的文件 |
| 目录监听 | 开 | 关掉后仍按间隔扫描 |
| 刮削并发 / 间隔 / 重试 | `8` / `2000ms` / `3` | 任务队列参数 |
| API 地址、速率、超时等 | 官方地址；各源 `30` 次/秒；超时 `10` 秒 | 设置页「高级选项」 |

### 仅构建或 Compose

| 变量 | 默认 | 用途 |
|------|------|------|
| `SKIP_WEB_BUILD` | 不跳过 | `true` 时 Gradle 不重新执行 `npm run build` |
| `FOLIO_TAG` | `0.1.0` | Compose 使用的镜像标签 |
| `MEDIA_HOST_PATH` | `/volume1/video` | Compose 挂到 `/media` 的宿主机片库路径 |
