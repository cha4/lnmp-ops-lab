#!/bin/bash
cd /opt/lnmp/cicd
echo "===== 构建开始 $(date +%T) ====="
docker build -f jenkins.Dockerfile -t lnmp/jenkins:1.0 . 
echo "===== 构建结束 $(date +%T) exit=$? ====="
docker images | grep -E "lnmp/jenkins" 
