# 项目状态

最后更新：2026-11-10 晚

## 已完成

- [x] Docker 环境：Nginx + PHP-FPM + MySQL + Redis 四层服务
- [x] 性能调优四轮：QPS 598 → 1700（+184%），P95 382 → 125ms
- [x] 监控栈：Prometheus + Grafana + cAdvisor + node-exporter
- [x] Grafana 面板：容器 CPU / 内存 / 网络 / 主机负载
- [x] 告警规则：PHP 容器 CPU > 0.5 核，评估 10s，Pending 30s，Webhook 通知
- [x] 告警验证：21:59:00 Firing → 22:01:00 Resolved，全生命周期跑通

## 待办（明天从这里开始）

1. **故障演练 A**：停 Redis，观察页面是否报错、MySQL CPU 是否上涨
2. **代码修复**：Redis 不可用时回退查询 MySQL（当前直接抛异常，无降级）
3. **故障演练 B**：停 php 容器，观察 502 与监控曲线
4. **故障演练 C**：磁盘写满，观察 MySQL 报错
5. **安全**：密码移入 .env，补 .gitignore
6. **推送**：GitHub
7. **文档**：README 补「监控与告警」章节

## 环境速查

| 项 | 值 |
|---|---|
| 虚拟机 | 192.168.255.131（root，SSH 密钥已配） |
| 应用入口 | http://192.168.255.131:8080 |
| Grafana | http://192.168.255.131:3000 （admin / admin） |
| Prometheus | http://192.168.255.131:9090 |
| 项目目录 | /opt/lnmp |
| Webhook 接收器 | python3 /opt/lnmp/webhook.py（端口 9999） |
| 告警日志 | /tmp/webhook.log |

## 常用命令

```bash
cd /opt/lnmp
docker compose ps                       # 查看 8 个容器
docker compose up -d                    # 启动全部
tail -f /tmp/webhook.log                # 看告警
ab -n 20000 -c 200 -k http://127.0.0.1:8080/   # 压测
git log --oneline                       # 版本历史
```

## 当前配置要点

| 配置 | 值 | 位置 |
|---|---|---|
| PHP-FPM | pm=static, max_children=16 | php/zz-custom.conf |
| OPcache | enable=1, validate_timestamps=0 | php/opcache.ini |
| Nginx | listen 80 backlog=4096 | nginx/default.conf |
| 内核 | somaxconn=4096, tcp_max_syn_backlog=8192 | /etc/sysctl.d/99-tuning.conf |
| 缓存 | 商品列表 TTL 60s | app/index.php |

## 已知问题

- 单机压测（ab 与被测服务共享 4 核），数据偏保守
- 应用与数据库均为单实例，存在单点
- 密码明文在 docker-compose.yml 中，推送前需处理