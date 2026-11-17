FROM jenkins/jenkins:lts-jdk17
USER root
ENV JENKINS_UC=https://mirrors.tuna.tsinghua.edu.cn/jenkins/updates
ENV JENKINS_UC_DOWNLOAD=https://mirrors.tuna.tsinghua.edu.cn/jenkins
RUN jenkins-plugin-cli --plugins git:latest workflow-aggregator:latest docker-workflow:latest gitlab-plugin:latest
USER jenkins
