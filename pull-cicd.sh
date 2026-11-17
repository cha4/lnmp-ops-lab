#!/bin/bash
LOG=/tmp/cicd3.log
exec >> $LOG 2>&1
need() { docker image inspect "$1" >/dev/null 2>&1; }

echo "===== 开始 $(date +%F' '%T) ====="

# 先拉小的 Jenkins
for round in $(seq 1 40); do
  if need jenkins/jenkins:lts-jdk17; then echo "[$(date +%T)] jenkins 已存在"; break; fi
  echo "[$(date +%T)] jenkins 第 $round 轮"
  docker pull jenkins/jenkins:lts-jdk17 && echo "[$(date +%T)] ✅ JENKINS OK" && break
  sleep 10
done

# 再拉 GitLab，三个源轮换
for round in $(seq 1 40); do
  if need gitlab/gitlab-ce:17.5.2-ce.0; then echo "[$(date +%T)] gitlab 已存在"; break; fi
  for src in docker.m.daocloud.io docker.1ms.run dockerproxy.net; do
    echo "[$(date +%T)] gitlab 第 $round 轮 via $src"
    docker pull $src/gitlab/gitlab-ce:17.5.2-ce.0 \
      && docker tag $src/gitlab/gitlab-ce:17.5.2-ce.0 gitlab/gitlab-ce:17.5.2-ce.0 \
      && echo "[$(date +%T)] ✅ GITLAB OK" && break 2
    sleep 5
  done
  sleep 15
done

echo "===== 结束 $(date +%F' '%T) ====="
docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep -E "gitlab|jenkins"
