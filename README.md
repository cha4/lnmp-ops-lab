# LNMP 多服务环境与性能调优实践

> 单台虚拟机上用 Docker Compose 编排 Nginx + PHP-FPM + MySQL + Redis 四层服务，
> 完成「跑通 → 建基线 → 找瓶颈 → 调优 → 复测」的完整闭环。

## 1. 项目背景

中小企业最常见的 Web 架构就是 LNMP：Nginx 做入口，PHP-FPM 跑业务，MySQL 存数据，Redis 做缓存。
本项目把这套架构容器化，并针对一个真实页面做性能优化，目标是回答三个问题：

1. 这套环境能不能一键复现？
2. 它的承载能力上限在哪里？
3. 瓶颈出现时，怎么定位、怎么验证？

## 2. 架构

```
                浏览器 / 压测客户端
                        │
                        ▼  :8080
                ┌───────────────┐
                │  nginx 容器    │  反向代理 + 静态资源
                └───────┬───────┘
                        │ fastcgi 9000（容器名解析）
                ┌───────▼───────┐
                │   php 容器     │  PHP-FPM + OPcache
                └───┬───────┬───┘
                    │       │
        TCP 3306    │       │   TCP 6379
        ┌───────────▼──┐  ┌─▼────────────┐
        │  mysql 容器   │  │  redis 容器   │
        │  持久化数据    │  │  缓存热点数据  │
        └──────────────┘  └──────────────┘
```

## 3. 运行环境

| 项 | 版本 / 配置 |
|---|---|
| 宿主机 | Windows + VMware Workstation |
| 虚拟机 | CentOS 7.9，4 vCPU / 8 GB / 60 GB |
| Docker | 26.1.4 |
| Docker Compose | v2.27.1 |
| Nginx | 1.27.5-alpine |
| PHP | 8.2.35-fpm（含 pdo_mysql、redis 扩展、OPcache） |
| MySQL | 8.0.46 |
| Redis | 7-alpine |

## 4. 目录结构

```
/opt/lnmp
├── docker-compose.yml            # 服务编排
├── docker-compose.override.yml   # 本地覆盖（OPcache 配置挂载）
├── nginx/
│   └── default.conf              # 反向代理 + fastcgi 转发
├── php/
│   ├── Dockerfile                # php:8.2-fpm + pdo_mysql + redis
│   ├── opcache.ini               # OPcache 参数
│   └── zz-custom.conf            # PHP-FPM 进程池（覆盖默认 www.conf）
├── app/
│   └── index.php                 # 示例页面：查缓存 → 回源 → 渲染
├── sql/
│   └── init.sql                  # 建表 + 初始数据（含 SET NAMES）
└── README.md
```

## 5. 快速开始

```bash
cd /opt/lnmp
docker compose up -d
docker compose ps
curl -s http://localhost:8080 | grep 状态
```

首次启动会自动初始化数据库、构建 PHP 镜像（约 2 分钟）。

## 6. 关键配置说明

| 配置 | 作用 | 为什么这么做 |
|---|---|---|
| `fastcgi_pass php:9000` | 容器间通信 | 用**容器名**而非 IP，Docker 内置 DNS 负责解析，容器重建后地址变化也不影响 |
| `depends_on` + `healthcheck` | 启动顺序 | `depends_on` 只保证启动先后，**不保证服务就绪**；healthcheck 才是真正的就绪判断 |
| `volumes: mysql-data` | 数据持久化 | 命名卷独立于容器生命周期，`down` 后数据仍在 |
| `./app:/var/www/html` | 代码挂载 | 改代码不用重建镜像 |
| `SET NAMES utf8mb4` | 字符集 | 导入时客户端字符集不确定，会话级强制 utf8mb4 防止中文双重编码 |
| `zz-custom.conf` | 进程池 | 以 `zz-` 开头，排在 `www.conf` 之后加载，覆盖默认值 |

## 7. 性能优化过程（核心）

### 7.1 结果总览

| 阶段 | 关键改动 | QPS | P95 | P99 |
|---|---|---|---|---|
| 基线 | 默认配置（5 worker，dynamic） | 598 | 382 ms | 3014 ms |
| 第一次调优 | worker 5 → 8（static） | 950 | 136 ms | 1325 ms |
| 第二次调优 | 启用 OPcache + PDO 持久连接 | 980 | 90 ms | 1098 ms |
| 第三次调优 | 引入 Redis 缓存商品列表 | 1558 | 130 ms | 1084 ms |
| 第四次调优 | 修复 listen 队列 + worker 8 → 16 | **1700** | **125 ms** | **1082 ms** |
| 累计 | | **+184%** | **−67%** | **−64%** |

### 7.2 每一次调优的依据

**① 基线：QPS 598，P99 3014ms**

反推发现 `598 × 0.008s ≈ 5`，恰好等于 `pm.max_children` 的默认值，判断瓶颈在 PHP 进程数。

**② worker 5 → 8**

4 核机器上，8 个 worker 已能喂满 CPU；继续加到 32 反而因上下文切换而降速。
结论：`max_children` 的上限由 **CPU 核数**和**内存**共同决定，不是越大越好。

**③ OPcache + 持久连接**

QPS 几乎不变（CPU 已满），但 P95 从 136ms 降到 90ms。
结论：优化连接建立开销 ≠ 优化查询本身。

**④ Redis 缓存**

MySQL CPU 从 94% 降到 0.6%，QPS 提升 59%。
结论：把重复查询移到内存，是收益最大的一步。

**⑤ 内核队列 + worker 16**

`ListenOverflows = 101`，说明 `somaxconn=128` 导致半连接队列溢出、SYN 重传，
表现为 P99 的 2 秒尖刺。调大内核队列与 Nginx `backlog` 后尖刺消失。

## 8. 压测方法

```bash
# 预热缓存，保证响应长度一致
curl -s http://localhost:8080 > /dev/null
curl -s http://localhost:8080 > /dev/null

# 稳态压测：20000 请求、200 并发、keep-alive
ab -n 20000 -c 200 -k http://127.0.0.1:8080/
```

**读结果只看三个数**：`Requests per second`（QPS）、`95%`、`99%`。
`Failed requests` 是按响应长度判定的，页面内容变化时会产生假失败，真错误看 `Non-2xx responses`。

## 9. 三个测量陷阱（踩过的坑）

1. **`Failed requests: 19999` 是假象**：页面在"缓存命中/回源查询"两种状态下长度不同，被 ab 全判为失败。
2. **`-n 3000` 测的是启动阶段**：压测时长不足时数据偏低，必须跑到稳态（≥30 秒或上万请求）。
3. **`sed -i` 改配置容器看不到**：`sed -i` 会替换 inode，bind mount 仍指向旧文件；改完必须重建容器。

## 10. 已知问题与改进方向

- 当前是**单机压测**：`ab` 与被测服务共享 4 个 vCPU，数据偏保守，只能做前后对比。
- **单点部署**：任一容器故障即服务不可用，下一步做双节点 + 上游健康检查。
- **无 HTTPS / 域名**：实验环境未配置证书。
- **无监控**：目前靠压测报告看数据，后续接入 Prometheus + Grafana。

## 11. 技术栈

Nginx · PHP-FPM · MySQL · Redis · Docker · Docker Compose · ab · Linux 内核参数调优