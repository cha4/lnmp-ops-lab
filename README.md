# 商品库存数据采集与监控分析系统

> 基于 Docker Compose 在单台虚拟机上构建 19 个容器的完整运维体系，
> 覆盖服务编排、负载均衡、数据库主从与读写分离、监控告警、日志平台、备份容灾与配置自动化。

## 一、项目背景

商品仓储中心需要对库存数据、出入库单据、库位状态等进行实时采集与展示。
随着访问量增长与系统复杂度提升，面临三个问题：

1. **部署依赖手工操作**，环境一致性难以保证，重建成本高
2. **性能瓶颈缺乏量化依据**，容量规划依靠经验
3. **运行状态缺少可观测性**，故障往往由用户侧反馈才发现

本项目构建一套可快速复现、可量化评估、可观测告警的运维体系。

## 二、架构总览

```
                        ┌─────────────────────────────────┐
   用户 ──▶ 8080 ──▶ Nginx ──┬── /       ──▶ PHP-FPM ──▶ ProxySQL ──┬──▶ MySQL 主库（写）
                            │                                       └──▶ MySQL 从库（读）
                            └── /app/   ──▶ Tomcat A / Tomcat B（轮询）

   采集层：
     cAdvisor ─┐
     node-exporter ─┼──▶ Prometheus ──▶ Grafana（面板）
     应用指标 ─┘            └──▶ Alertmanager（告警路由）

   日志层：
     nginx 日志 ──▶ Filebeat ──▶ Logstash（grok 解析）──▶ Elasticsearch ──▶ Kibana

   运维层：
     Ansible（配置下发，幂等） · Crontab（定时备份） · Shell（备份/恢复）
```

### 容器清单（19 个）

| 类别 | 容器 | 端口 | 说明 |
|---|---|---|---|
| 接入 | nginx | 8080→80 | 反向代理、静态资源、fastcgi、upstream |
| 应用 | php | 内网 9000 | PHP-FPM + OPcache |
| 应用 | tomcat-a / tomcat-b | 8081 / 8082 | Java 应用集群（inventory war） |
| 数据 | mysql | 内网 3306 | 主库（写） |
| 数据 | mysql-slave | 内网 3306 | 从库（读，super_read_only） |
| 数据 | proxysql | 6033 / 6032 | 读写分离中间件 |
| 数据 | redis | 内网 6379 | 缓存 |
| 监控 | prometheus | 9090 | 指标采集与存储 |
| 监控 | grafana | 3000 | 可视化 |
| 监控 | alertmanager | 9093 | 告警路由 |
| 监控 | cadvisor | 内网 | 容器指标 |
| 监控 | node-exporter | 内网 | 主机指标 |
| 日志 | elasticsearch | 9200 | 日志存储 |
| 日志 | kibana | 5601 | 日志可视化 |
| 日志 | logstash | 内网 5044 | 日志解析 |
| 日志 | filebeat | — | 日志采集 |
| 交付 | gitlab | 8083 / 2222 | 代码仓库与 Webhook |
| 交付 | jenkins | 8084 / 50001 | 流水线引擎 |

## 三、技术栈

CentOS 7.9 · Docker · Docker Compose · Nginx · PHP-FPM · Tomcat · MySQL 8.0 · ProxySQL · Redis
· Prometheus · Alertmanager · Grafana · cAdvisor · node-exporter · Elasticsearch · Logstash · Kibana · Filebeat
· Ansible · Shell · Crontab · Jenkins · GitLab · Git

## 四、目录结构

```
/opt/lnmp
├── docker-compose.yml               # 核心服务：nginx/php/mysql/redis
├── docker-compose.override.yml      # 监控 + 日志 + 中间件扩展
├── .env / .env.example              # 凭证（真实值不入库）
├── nginx/default.conf               # 反代 + fastcgi + upstream + backlog
├── app/
│   ├── index.php                    # 缓存 + 降级 + 熔断 + 数据节点标识
│   └── metrics.php                  # 自定义 Prometheus 指标端点
├── php/                             # Dockerfile + OPcache + FPM 进程池
├── tomcat/
│   ├── webapp/                      # JSP 源码
│   └── app.war                      # 构建产物
├── sql/init.sql
├── monitoring/
│   ├── prometheus.yml               # 由 Ansible 渲染
│   ├── alertmanager.yml             # 告警路由
│   ├── rules/lnmp.yml               # Prometheus 告警规则
│   ├── logstash/pipeline/           # grok 解析规则
│   ├── filebeat/filebeat.yml        # 日志采集配置
│   └── grafana/provisioning/        # 数据源
├── ansible/                         # inventory + site.yml（幂等）
├── scripts/                         # backup-full.sh / restore.sh
├── docs/                            # 故障复盘文档
└── README.md
```

## 五、快速开始

```bash
cp .env.example .env          # 填入真实密码
docker compose up -d          # 拉起全部服务
docker compose ps             # 确认 19 个容器 Up
```

访问入口：

| 服务 | 地址 |
|---|---|
| 应用 | http://<ip>:8080 |
| Tomcat 集群 | http://<ip>:8080/app/ |
| Grafana | http://<ip>:3000 |
| Prometheus | http://<ip>:9090 |
| Alertmanager | http://<ip>:9093 |
| Kibana | http://<ip>:5601 |
| GitLab | http://<ip>:8083 |
| Jenkins | http://<ip>:8084 |

## 六、核心模块与实测结果

### 1. 服务编排

自定义 bridge 网络实现容器名服务发现，healthcheck 保障启动依赖，命名卷持久化数据。
一条命令重建整套环境。

### 2. Nginx + Tomcat 集群（负载均衡与故障切换）

两个 Tomcat 节点部署同一个 war 包，Nginx 用 upstream 轮询，配置被动健康检查。

**实测结果**：

| 场景 | 结果 |
|---|---|
| 正常 20 次请求 | 两节点各 10 次，完全均分 |
| 停掉一个节点 | **100% 转到存活节点，0 失败，耗时 5ms** |

**关键配置**：

```nginx
upstream tomcat_cluster {
    server tomcat-a:8080 max_fails=1 fail_timeout=30s;
    server tomcat-b:8080 max_fails=1 fail_timeout=30s;
}
proxy_connect_timeout 2s;                 # 默认 60s 会导致请求挂死
proxy_next_upstream error timeout http_502 http_503 http_504;
```

> **踩坑**：容器停机后 IP 仍在网桥上，连接是「黑洞超时」而非快速拒绝。
> 默认 60 秒连接超时会让请求挂死 5 秒以上（日志表现为 499 而非 502）。

### 3. MySQL 主从 + ProxySQL 读写分离

主从基于 **GTID** 复制（避免位点漂移），从库设置 `super_read_only` 防止误写；
ProxySQL 按 hostgroup 分流：10 = 写组，20 = 读组，`^SELECT` 路由到读组。

**实测结果**：

| 检查项 | 结果 |
|---|---|
| 复制状态 | IO/SQL 均 Yes，延迟 0 秒 |
| 写入同步 | 主库写入 2 秒内从库可见 |
| 读路由 | 页面显示 `server_id=2`（从库） |
| 从库保护 | 写入被拒绝（ERROR 1290） |

> **踩坑**：容器内的 socket 连接异常，必须用 `-h127.0.0.1` 走 TCP；
> `--super-read-only` 会阻断初始化脚本，需在建好复制后再开启。

### 4. 监控与告警

Prometheus 采集容器（cAdvisor）、主机（node-exporter）、应用（自研端点）三层指标，
Grafana 配置 6 个面板；告警规则交由 Prometheus 评估、Alertmanager 路由。

**实测结果**：压测时 PHP CPU 从 0.39 → 1.31 核，告警状态 `pending → firing`，
Alertmanager 收到告警（携带实际值 1.21 核），压测停止后自动恢复。

**关键设计**：自研指标端点采用**本地文件计数**，不依赖 Redis——
否则缓存故障时监控端点一起超时，故障期间完全看不到数据。

### 5. ELK 日志平台

nginx 访问日志落盘 → Filebeat 采集 → Logstash 用 grok 解析 → ES 存储 → Kibana 查询。

**实测结果**：

| 指标 | 结果 |
|---|---|
| 索引文档数 | 150+ |
| 集群状态 | green |
| 字段解析 | clientip / method / status / bytes / user_agent 全部结构化 |
| 聚合查询 | 按状态码聚合正常（200 × N） |

**关键配置**：`vm.max_map_count=262144`（ES 必需）、单节点模式、关闭安全认证、
JVM 堆限制 1G、索引副本 0（单节点无法分配副本否则一直是 yellow）。

### 6. 备份与容灾

全量备份（mysqldump + gzip + 保留 7 天）+ binlog 归档，Crontab 每天 02:00 执行。

**演练过程与结果**：

| 步骤 | 结果 |
|---|---|
| 备份 | 生成 `shop_YYYYmmdd_HHMMSS.sql.gz` + 4 个 binlog |
| 模拟灾难 | `DROP TABLE` → 查询报 ERROR 1146 |
| 恢复 | **RTO 592 毫秒** |
| 数据校验 | 主从各 5 条，内容一致，中文正常 |
| 复制状态 | 恢复后 IO/SQL 仍为 Yes |

**踩的四个坑**：

| 现象 | 根因 | 解决 |
|---|---|---|
| `GTID_PURGED cannot be changed` | 备份的 GTID 集合与本机已执行重叠 | 恢复时剔除该行 |
| 中文变 `????` | 客户端默认 latin1 | 备份/恢复都加 `--default-character-set=utf8mb4` |
| 恢复后从库没数据 | **mysqldump 内含 `SET SQL_LOG_BIN=0`** | 恢复时一并剔除 |
| 从库 SQL 线程停止（1051） | 主库 DROP 在从库执行时表已不存在 | 重建从库 |

### 7. Ansible 自动化

`site.yml` 完成内核参数下发、目录创建、Prometheus 配置渲染（Jinja2 模板）、容器编排。

**幂等性实测**：

```
第一次执行：changed=3
第二次执行：changed=0    ← 重复执行不产生变更
```

### 8. CI/CD 流水线

基于 GitLab + Jenkins 实现「提交即部署」：代码推送到 GitLab 触发 Webhook，Jenkins 依次执行五个阶段。

```
提交代码 → GitLab → Webhook → Jenkins
                                  ├─ ① 检出代码
                                  ├─ ② 配置语法检查（compose config -q）
                                  ├─ ③ 构建镜像（打构建号标签）
                                  ├─ ④ 部署（compose up -d php nginx）
                                  └─ ⑤ 冒烟测试（首页 + 应用页均要求 200）
```

**实测结果**：

| 验证项 | 结果 |
|---|---|
| 手动触发构建 | 通过 |
| GitLab 测试推送触发 | 触发成功（`201 Created`） |
| 真实提交自动触发 | 提交 → 推送 → 自动构建 #6 → SUCCESS |
| 冒烟测试 | 首页 200、应用页 200 |

**关键设计**：

- 冒烟测试带**重试**（12 次 × 5 秒），避免容器刚重建未就绪造成误判
- 构建镜像用 `DOCKER_BUILDKIT=0`：镜像已缓存时可离线构建，避免 BuildKit 联网校验基础镜像
- 冒烟测试目标用**容器网络名**（`http://nginx:80`），不能用 `127.0.0.1`——流水线在 Jenkins 容器内执行，`127.0.0.1:8080` 指向的是 Jenkins 自己
- 镜像标签带构建号，每次部署可追溯到具体版本
- 任一阶段失败立即中止，不继续部署

**踩的坑**：

| 问题 | 原因 | 解决 |
|---|---|---|
| 端口冲突 | GitLab 想用 8081/8082，被 Tomcat 占用 | 改为 8083/8084 |
| 外部访问 000 | `external_url` 带端口后，容器内 nginx 监听该端口 | 映射改为 `8083:8083` |
| Webhook 401/403 | Jenkins CSRF 保护 | 关闭 CSRF（实验环境） |
| Webhook "Invalid url" | GitLab 默认禁止访问内网 | 开启 `allow_local_requests_from_web_hooks_and_services` |
| 冒烟测试误判 | 在容器内测 `127.0.0.1` | 改用容器名 |

## 七、其他问题与解决

| 问题 | 根因 | 解决 |
|---|---|---|
| 容器 Up 但端口不通 | firewalld 重新启用覆盖 Docker 规则 | 关闭 firewalld + 重启 Docker |
| 改配置容器不生效 | `sed -i` 替换 inode，bind mount 仍指向旧文件 | 用 `cat >` 原地写入或重建容器 |
| 改代码不生效 | OPcache `validate_timestamps=0` | 重启 php 容器 |
| 端口冲突 | GitLab/监控组件都想用 80 | 统一规划端口（8081/8082/5601/9200） |
| 镜像拉取超时 | Docker Hub 与 ES CDN 被墙 | 走代理 + 多源重试 |

## 八、已知问题与规划

- 单机部署，应用与数据库均为单实例，存在单点
- 未实现限流，数据库被打满时缺少保护
- ELK 未做索引生命周期管理（ILM），日志会持续增长
- 规划：双机 + Keepalived 高可用、MySQL 半同步复制、接入 CI/CD 流水线

## 九、文档

- `docs/STATUS.md` — 环境状态与变更记录
- `docs/drill-redis-degradation.md` — 缓存降级故障复盘

## 十、仓库

https://github.com/cha4/lnmp-ops-lab