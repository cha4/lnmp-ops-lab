# LNMP 多服务环境 · 性能调优 · 监控告警 · 故障演练

> 在单台虚拟机上用 Docker Compose 编排 Nginx + PHP-FPM + MySQL + Redis，
> 完成「跑通 → 压测 → 调优 → 监控 → 告警 → 故障演练 → 修复复验」的完整闭环。

## 1. 项目目标

1. 环境能否一键复现？
2. 承载能力上限在哪里？瓶颈是什么？
3. 出了故障能不能被发现、被定位、被降级？

## 2. 架构

| 层 | 容器 | 端口 | 职责 |
|---|---|---|---|
| 接入 | nginx | 8080 → 80 | 反向代理、静态资源、fastcgi 转发 |
| 应用 | php | 9000（仅内网） | PHP-FPM + OPcache，执行页面逻辑 |
| 数据 | mysql | 3306（仅内网） | 持久化到命名卷 `mysql-data` |
| 缓存 | redis | 6379（仅内网） | 商品列表缓存，TTL 60s |
| 监控 | prometheus / grafana / cadvisor / node-exporter | 9090 / 3000 | 采集、存储、可视化 |

请求路径：浏览器 → nginx:8080 →（fastcgi）php:9000 → mysql:3306 或 redis:6379。
容器间通过**容器名**互相访问，由 Docker 内置 DNS 解析。

## 3. 运行环境

| 项 | 版本 / 配置 |
|---|---|
| 虚拟机 | CentOS 7.9，4 vCPU / 8 GB / 60 GB |
| Docker / Compose | 26.1.4 / v2.27.1 |
| Nginx / PHP | 1.27.5-alpine / 8.2.35-fpm（pdo_mysql、redis、OPcache） |
| MySQL / Redis | 8.0.46 / 7-alpine |
| 监控 | Prometheus 2.54.1、Grafana 11.2.0、cAdvisor 0.53.0、node-exporter 1.8.2 |
| 压测 | ab (ApacheBench 2.3) |

## 4. 目录结构

```
/opt/lnmp
├── docker-compose.yml            # 服务编排
├── docker-compose.override.yml   # OPcache 挂载 + 监控组件
├── .env                          # 真实密码（不进 Git）
├── .env.example                  # 变量模板（进 Git）
├── nginx/default.conf            # 反代 + fastcgi + backlog
├── php/
│   ├── Dockerfile                # php:8.2-fpm + pdo_mysql + redis
│   ├── opcache.ini
│   └── zz-custom.conf            # 进程池：static, 16 worker
├── app/
│   ├── index.php                 # 缓存 + 降级 + 熔断
│   └── metrics.php               # 自研 Prometheus 指标端点
├── sql/init.sql
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/provisioning/datasources/prometheus.yml
├── docs/
│   ├── STATUS.md
│   └── drill-redis-degradation.md
└── README.md
```

## 5. 快速开始

```bash
cp .env.example .env      # 填入真实密码
docker compose up -d
curl -s http://localhost:8080 | grep 状态
```

- 应用：http://<ip>:8080
- Grafana：http://<ip>:3000（admin / 见 .env）
- Prometheus：http://<ip>:9090

## 6. 关键设计

| 设计 | 做法 | 原因 |
|---|---|---|
| 服务发现 | `fastcgi_pass php:9000`、`host=mysql` | 用容器名而非 IP，容器重建后地址变化不影响 |
| 启动依赖 | `depends_on` + `healthcheck` | 前者只管顺序，后者才判断“真的可用” |
| 数据持久化 | 命名卷 `mysql-data` | 容器删除数据仍在 |
| 字符集 | 建表 utf8mb4 + 连接串 charset + `SET NAMES` | 三处一致，否则双重编码 |
| 配置与秘钥 | `.env` + 环境变量 | 敏感信息不进版本库 |

## 7. 性能优化（四轮）

| 阶段 | 关键改动 | QPS | P95 | P99 |
|---|---|---|---|---|
| 基线 | 默认 5 worker / dynamic | 598 | 382 ms | 3014 ms |
| 第一轮 | worker → 8 / static | 950 | 136 ms | 1325 ms |
| 第二轮 | + OPcache + PDO 持久连接 | 980 | 90 ms | 1098 ms |
| 第三轮 | + Redis 缓存 | 1558 | 130 ms | 1084 ms |
| 第四轮 | + 内核队列 + worker 16 | **1700** | **125 ms** | **1082 ms** |
| 累计 | | **+184%** | **−67%** | **−64%** |

每一轮的依据：

- **基线反推**：`598 × 0.008s ≈ 5`，恰好等于 `pm.max_children` 默认值，锁定进程数瓶颈。
- **进程数**：4 核机器上超过 8 个 worker 后 QPS 不再增长，32 个反而下降（上下文切换）。
- **OPcache / 持久连接**：QPS 不变但 P95 从 136→90ms，说明优化的是延迟不是吞吐。
- **Redis**：MySQL CPU 从 94% 降到 0.6%，QPS 提升 59%。
- **内核队列**：`ListenOverflows=101`，`somaxconn=128` 导致半连接队列溢出、SYN 重传，表现为 2 秒级尾延迟。

压测方法：`ab -n 20000 -c 200 -k`，预热缓存后连跑三次取中位数。
⚠️ 单机压测（压测端与被测端共享 4 核），数据偏保守，仅用于前后对比。

## 8. 监控与告警

**采集**：cAdvisor（容器）、node-exporter（主机）、自研 `/metrics.php`（应用），Prometheus 每 5s 拉取。

**面板**（Grafana「LNMP 监控」）：容器 CPU／内存／网络、主机负载、QPS、关键状态（存活容器、抓取状态）。

**告警**：`PHP 容器 CPU > 0.5 核`，评估周期 10s、Pending 30s，Webhook 通知。

**验证**：压测触发后状态 `Normal → Pending → Firing`，21:59 触发、22:01 恢复，Webhook 收到 `firing` 与 `resolved` 两条通知。

**自研指标端点**（`app/metrics.php`）：

```
app_requests_total 12345     # 请求总数（读本地文件，不依赖 Redis）
```

> 设计要点：**观测端点不能依赖被观测的依赖**。最初 `/metrics.php` 需要连 Redis，Redis 一挂监控目标直接 DOWN，什么都看不到；改为读本地文件后，故障期间监控仍可用。

## 9. 故障演练

### 缓存不可用（Redis 停机）

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 页面 | 报错（HTTP 200 但内容失败） | 正常显示商品 |
| QPS | 20.37 | **857.67** |
| P95 | 5172 ms | **183 ms** |
| MySQL CPU | 0.02 核（未被访问） | 0.156 核 |
| 首请求耗时 | 5 s（DNS 超时） | 0.102 s（熔断） |

修复手段：**降级**（Redis 失败回退查 MySQL）+ **熔断**（失败后 30s 内不再尝试 Redis）。
详见 `docs/drill-redis-degradation.md`。

### 其他已遇到的问题

| 问题 | 根因 | 处理 |
|---|---|---|
| 容器全 Up 但端口不通 | firewalld 重新启用，覆盖 Docker 转发规则 | 关闭 firewalld + 重启 Docker |
| 改配置容器不生效 | `sed -i` 替换 inode，bind mount 仍指向旧文件 | 重建容器，或原地写入 |
| 中文乱码 | 导入时客户端字符集为 latin1，双重编码 | `--default-character-set=utf8mb4` + `SET NAMES` |
| 指标查不到 | cAdvisor 该版本用 `name` 标签而非 `container` | 先查 label 再写 PromQL |
| 改代码不生效 | OPcache `validate_timestamps=0` | 重启 php 容器 |

## 10. 已知问题与规划

- 单机部署：应用与数据库均为单实例，存在单点。
- 单机压测：数据偏保守，绝对值无参考意义。
- 未实现限流：数据库被打满时缺少保护。
- 规划：双节点 + upstream 健康检查、MySQL 主从、限流与熔断策略完善。

## 11. 技术栈

Nginx · PHP-FPM · MySQL · Redis · Docker · Docker Compose · Prometheus · Grafana · cAdvisor · Linux 内核调优