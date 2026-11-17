# CI/CD 流水线

## 组件

| 组件 | 端口 | 作用 |
|---|---|---|
| GitLab | 8083 / 2222 | 代码仓库、Webhook 触发 |
| Jenkins | 8084 / 50001 | 流水线引擎 |

## 流水线阶段

```
提交代码 → GitLab → Webhook → Jenkins
                                  ├─ ① 检出代码
                                  ├─ ② 配置语法检查
                                  ├─ ③ 构建镜像（DOCKER_BUILDKIT=0）
                                  ├─ ④ 部署（compose up -d）
                                  └─ ⑤ 冒烟测试（首页 + 应用页）
```

## 触发方式

```bash
# 手动 / 远程触发
curl -X POST "http://<ip>:8084/job/lnmp-pipeline/build?token=lnmp-cicd-token"
```

GitLab 项目 → Settings → Webhooks 配置：
`http://<ip>:8084/job/lnmp-pipeline/build?token=lnmp-cicd-token`

## 关键配置

| 配置 | 说明 |
|---|---|
| `jenkins-job.xml` | 任务定义，可导入 Jenkins |
| Jenkins 关闭 CSRF | 实验环境允许 Webhook 直接触发 |
| GitLab 开启本地请求 | 允许向内网地址发 Webhook |
| `DOCKER_BUILDKIT=0` | 镜像已缓存时避免联网校验基础镜像 |
| 冒烟测试用容器名 | `http://nginx:80`，不能用 127.0.0.1 |

## 验证记录

| 验证 | 结果 |
|---|---|
| 手动触发 | 通过 |
| GitLab 测试推送 | 触发成功 |
| 真实提交自动触发 | SUCCESS |
| 断网（无代理）后构建 | SUCCESS |
