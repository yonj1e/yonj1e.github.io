---
title: 使用Docker部署PostgreSQL
date: 2018-07-30 
categories: 
  - [Docker]
  - [PostgreSQL - Usage]
tags: 
  - Docker
  - PostgreSQL
---



Docker提供了基于操作系统级和应用级虚拟化的应用部署解决方案。它的出现让在服务器上部署应用免去了操作系统，支持系统等一系列的搭建，而把它们简化为镜像，容器，实现快速部署。

Docker将应用所需要的底层系统支持，操作系统支持，数据库支持，应用本身和应用的数据分离开来，可以从任意层级上在一个拥有docker技术的电脑上对应用进行部署。每一层被抽象成了镜像（image），而镜像跑在服务器上便成了容器（container），相当于虚拟机。跑起一个应用级别的容器，会自动获取它所需要的向下级别的镜像。这些都可以通过云端大量现成的资源和几行脚本命令实现。

#### Docker 安装

前提条件

Docker 运行在 CentOS 7 上，要求系统为64位、系统内核版本为 3.10 以上 

```shell
[yangjie@young-1 ~]$ uname -r
3.10.0-229.el7.x86_64
```

安装 Docker

Docker 软件包和依赖包已经包含在默认的 CentOS-Extras 软件源里，可以使用yum安装，或者脚本安装

```shell
# yum 安装
yum -y install docker-io

# 脚本安装
wget -qO- https://get.docker.com/ | sh
```

换阿里的源，比较丰富，不会出问题

```shell
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
yum clean all
yum makecache
```

安装

```shell
wget -qO- https://get.docker.com/ | sh

Package docker-ce-18.06.0.ce-3.el7.x86_64 already installed and latest version
If you would like to use Docker as a non-root user, you should now consider
adding your user to the "docker" group with something like:

  sudo usermod -aG docker yangjie

Remember that you will have to log out and back in for this to take effect!

WARNING: Adding a user to the "docker" group will grant the ability to run
         containers which can be used to obtain root privileges on the
         docker host.
         Refer to https://docs.docker.com/engine/security/security/#docker-daemon-attack-surface
         for more information.
```

启动docker

```shell
[yangjie@young-1 ~]$ systemctl start docker.service
# 开机启动
[yangjie@young-1 ~]$ chkconfig docker on
[yangjie@young-1 ~]$ sudo docker version
Client:
 Version:           18.06.0-ce
 API version:       1.38
 Go version:        go1.10.3
 Git commit:        0ffa825
 Built:             Wed Jul 18 19:08:18 2018
 OS/Arch:           linux/amd64
 Experimental:      false

Server:
 Engine:
  Version:          18.06.0-ce
  API version:      1.38 (minimum version 1.12)
  Go version:       go1.10.3
  Git commit:       0ffa825
  Built:            Wed Jul 18 19:10:42 2018
  OS/Arch:          linux/amd64
  Experimental:     false
```

几个坑

```shell
# docker 权限问题
# 据官方解释，搭建docker环境必须使用root权限，将普通用户加到docker用户组
[yangjie@young-1 ~]$ sudo groupadd docker
[sudo] password for yangjie: 
[yangjie@young-1 ~]$ sudo usermod -aG docker yangjie
[yangjie@young-1 ~]$ newgrp - docker
[yangjie@young-1 ~]$ sudo service docker start
Redirecting to /bin/systemctl start docker.service

# 存储空间问题
# docker镜像的默认存储路径是/var/lib/docker，这相当于直接挂载系统目录下
# 这个空间一般不够大，更改docker镜像默认存储路径
sudo cp -R /var/lib/docker/ /work/
sudo vim /usr/lib/systemd/system/docker.service 

ExecStart=/usr/bin/dockerd-current \
          --graph=/work/docker \		# 添加新路径

# 重新加载配置，重启，
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo rm -rf /var/lib/docker/
[yangjie@young-1 work]$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAME

# 用的overlay2文件系统，而系统默认只能识别overlay文件系统
# 更新文件系统
[yangjie@young-1 lib]$ docker run --name postgres -e POSTGRES_PASSWORD=postgres -p 54321:5432 -d postgres -v /work/pgsql/docker/data/:/var/lib/postgresql/data
/usr/bin/docker-current: Error response from daemon: error creating overlay mount to /work/docker/lib/docker/overlay2/b103b373b7c815c5663b11116f041b83f98185f4756066f9bdf4e88f2beb7d08-init/merged: invalid argument.
See '/usr/bin/docker-current run --help'.
[yangjie@young-1 lib]$ sudo systemctl stop docker 
[yangjie@young-1 lib]$ sudo vim /etc/sysconfig/docker-storage
[sudo] password for yangjie: 

DOCKER_STORAGE_OPTIONS="--storage-driver overlay"

# 去掉option后面的--selinux-enabled
[yangjie@young-1 lib]$ sudo vim /etc/sysconfig/docker         

[yangjie@young-1 lib]$ sudo systemctl restart docker
```



#### Docker 简单使用

运行交互式容器

当运行容器时，使用的镜像如果在本地中不存在，docker 就会自动从 docker 镜像仓库中下载，默认是从 Docker Hub 公共镜像源下载 

```shell
[yangjie@young-1 ~]$ docker run -i -t centos /bin/bash
[root@1b3d3141cea7 /]# uname -a
Linux 1b3d3141cea7 3.10.0-862.9.1.el7.x86_64 #1 SMP Mon Jul 16 16:29:36 UTC 2018 x86_64 x86_64 x86_64 GNU/Linux
[root@a36ed3a5ed0b /]# cat /etc/centos-release
CentOS Linux release 7.5.1804 (Core)

# 退出
[root@a36ed3a5ed0b /]# exit
exit
[yangjie@young-1 ~]$ 
```

列出容器

```shell
[yangjie@young-1 ~]$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
1b3d3141cea7        centos              "/bin/bash"         23 minutes ago      Up 23 minutes                           hungry_kalam
```

列出镜像

```shell
[yangjie@young-1 ~]$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
centos              latest              49f7960eb7e4        7 weeks ago         200MB
```

获取新镜像

```shell
[yangjie@young-1 ~]$ docker pull ubuntu
Using default tag: latest
latest: Pulling from library/ubuntu
c64513b74145: Downloading [================================>                  ]  20.86MB/31.66MB
c64513b74145: Pull complete 
01b8b12bad90: Pull complete 
c5d85cf7a05f: Pull complete 
b6b268720157: Pull complete 
e12192999ff1: Pull complete 
Digest: sha256:3f119dc0737f57f704ebecac8a6d8477b0f6ca1ca0332c7ee1395ed2c6a82be7
Status: Downloaded newer image for ubuntu:latest
```



#### Docker 安装 postgres

在docker上快速部署Postgresql数据库，其实可以直接参考<https://hub.docker.com/_/postgres/>，这里提供了docker-postgres的官方解决方案。 

查找Docker Hub上的postgres镜像 

```shell
[yangjie@young-1 ~]$ docker search postgres
NAME                                     DESCRIPTION                                     STARS               OFFICIAL            AUTOMATED
postgres                                 The PostgreSQL object-relational database sy…   5251                [OK]                
sameersbn/postgresql                                                                     131                                     [OK]
paintedfox/postgresql                    A docker image for running Postgresql.          77                                      [OK]
orchardup/postgresql                     https://github.com/orchardup/docker-postgres…   46                                      [OK]
kiasaki/alpine-postgres                  PostgreSQL docker image based on Alpine Linux   42                                      [OK]
centos/postgresql-96-centos7             PostgreSQL is an advanced Object-Relational …   24                                      
bitnami/postgresql                       Bitnami PostgreSQL Docker Image                 20                                      [OK]
begriffs/postgrest                       Moved to https://hub.docker.com/r/postgrest/…   16                                      [OK]
centos/postgresql-94-centos7             PostgreSQL is an advanced Object-Relational …   15                                      
crunchydata/crunchy-postgres             Crunchy PostgreSQL is an open source, unmodi…   12                                      
wrouesnel/postgres_exporter              Postgres metrics exporter for Prometheus.       9                                       
clkao/postgres-plv8                      Docker image for running PLV8 1.4 on Postgre…   8                                       [OK]
postdock/postgres                        PostgreSQL server image, can work in master …   7                                       [OK]
circleci/postgres                        The PostgreSQL object-relational database sy…   7                                       
centos/postgresql-95-centos7             PostgreSQL is an advanced Object-Relational …   5                                       
blacklabelops/postgres                   Postgres Image for Atlassian Applications       4                                       [OK]
frodenas/postgresql                      A Docker Image for PostgreSQL                   3                                       [OK]
camptocamp/postgresql                    Camptocamp PostgreSQL Docker Image              3                                       [OK]
cfcommunity/postgresql-base              https://github.com/cloudfoundry-community/po…   0                                       
ansibleplaybookbundle/postgresql-apb     An APB which deploys RHSCL PostgreSQL           0                                       [OK]
fredboat/postgres                        PostgreSQL 10.0 used in FredBoat's docker-co…   0                                       
relatable/postgrest                      Nginx container to serve web requests to the…   0                                       [OK]
cfcommunity/postgresql                   https://github.com/cloudfoundry-community/po…   0                                       
openshift/postgresql-92-centos7          DEPRECATED: A Centos7 based PostgreSQL v9.2 …   0                                       
ansibleplaybookbundle/rds-postgres-apb   An APB that deploys an RDS instance of Postg…   0                                       [OK]
[yangjie@young-1 ~]$ 
```

拉取官方镜像

```shell
[yangjie@young-1 ~]$ sudo docker pull postgres
Using default tag: latest
latest: Pulling from library/postgres
be8881be8156: Pull complete 
bcc05f43b4de: Pull complete 
78c4cc9b5f06: Pull complete 
d45b5ac60cd5: Pull complete 
67f823cf5f8b: Pull complete 
0626c6149c90: Pull complete 
e25dcd1f62ca: Pull complete 
c3c9ac2352c5: Pull complete 
e7850488cb30: Pull complete 
afbae3a26c07: Pull complete 
90b4f1aa8431: Pull complete 
916671d3d4a6: Pull complete 
8221e20bcbad: Pull complete 
b2eb8d065dc9: Pull complete 
Digest: sha256:7d20c46b2da5e4a240dda720e3a159e2bf9d0f0af9a9b72d8e0c348f75ef374b
Status: Downloaded newer image for postgres:latest
```

查看postgres镜像

```shell
[yangjie@young-1 ~]$ docker images | grep postgres
postgres            latest              978b82dc00dc        3 days ago          236MB
```

使用postgres镜像

```shell
[yangjie@young-1 ~]$ docker run --name postgres -e POSTGRES_PASSWORD=postgres -p 54321:5432 -d postgres
b9ff94a1dae3dc1feaf5d58cf4dfcb35178d06eb80dcd969b1299664fe80fbc2
[yangjie@young-1 ~]$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                     NAMES
b9ff94a1dae3        postgres            "docker-entrypoint.s…"   7 seconds ago       Up 7 seconds        0.0.0.0:54321->5432/tcp   postgres
[yangjie@young-1 bin]$ ./psql -p 54321 -U postgres -h 192.168.102.30
Password for user postgres: 
psql (5.0.0, server 10.4)
Type "help" for help.

postgres=# select version();
                                                             version                                                              
----------------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 10.4 (Debian 10.4-2.pgdg90+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 6.3.0-18+deb9u1) 6.3.0 20170516, 64-bit
(1 row)

postgres=# 
```

使用数据卷持久化

```shell
# 创建本地数据目录
[yangjie@young-1 data]$ pwd
/work/pgsql/docker/data

# 运行镜像，-v 指定本地数据卷，映射pg目录
[yangjie@young-3 work]$ docker run --name postgres -v /work/pgsql/docker/data/:/var/lib/postgresql/data -e POSTGRES_PASSWORD=postgres -p 5438:5432 -d postgres
be8b0b918eb8256431a4b28c6fb25b4cb60b735809d8a63a83cb73ad517bbc39
[yangjie@young-3 work]$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
be8b0b918eb8        postgres            "docker-entrypoint..."   12 seconds ago      Up 11 seconds       0.0.0.0:5438->5432/tcp   postgres
[yangjie@young-3 work]$ docker run -it --rm --link postgres:postgres postgres psql -h postgres -U postgres
Password for user postgres: 
psql (10.4 (Debian 10.4-2.pgdg90+1))
Type "help" for help.

postgres=# select version();
                                                             version                                                              
----------------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 10.4 (Debian 10.4-2.pgdg90+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 6.3.0-18+deb9u1) 6.3.0 20170516, 64-bit
(1 row)

postgres=# \d
Did not find any relations.
postgres=# create table test(id int, tx text, ts timestamp);
CREATE TABLE
postgres=# insert into test values (1, 't1', now());
INSERT 0 1
postgres=# select * from test ;
 id | tx |             ts             
----+----+----------------------------
  1 | t1 | 2018-08-03 04:36:58.705212
(1 row)

postgres=# \q

# 关闭容器并重新启动
[yangjie@young-3 work]$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
be8b0b918eb8        postgres            "docker-entrypoint..."   5 minutes ago       Up 5 minutes        0.0.0.0:5438->5432/tcp   postgres
[yangjie@young-3 work]$ docker stop be8b0b918eb8
be8b0b918eb8
[yangjie@young-3 work]$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
[yangjie@young-3 work]$ docker ps -a
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS                      PORTS               NAMES
be8b0b918eb8        postgres            "docker-entrypoint..."   5 minutes ago       Exited (0) 11 seconds ago                       postgres
[yangjie@young-3 work]$ docker start be8b0b918eb8
be8b0b918eb8
[yangjie@young-3 work]$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
be8b0b918eb8        postgres            "docker-entrypoint..."   6 minutes ago       Up 2 seconds        0.0.0.0:5438->5432/tcp   postgres

# 重新连接并查询数据
[yangjie@young-3 work]$ docker run -it --rm --link postgres:postgres postgres psql -h postgres -U postgres
Password for user postgres: 
psql (10.4 (Debian 10.4-2.pgdg90+1))
Type "help" for help.

postgres=# select * from test;
 id | tx |             ts             
----+----+----------------------------
  1 | t1 | 2018-08-03 04:36:58.705212
(1 row)

postgres=# 
```



#### Docker 实例问题

```shell
# 看到之前运行docker容器还没有退出，导致出现容器重名情况
[yangjie@young-1 data10]$ docker run --name postgres -e POSTGRES_PASSWORD=postgres -p 54321:5432 -d postgres
docker: Error response from daemon: Conflict. The container name "/postgres" is already in use by container "b9ff94a1dae3dc1feaf5d58cf4dfcb35178d06eb80dcd969b1299664fe80fbc2". You have to remove (or rename) that container to be able to reuse that name.
See 'docker run --help'.
[yangjie@young-1 data10]$ docker ps -a
CONTAINER ID        IMAGE                    COMMAND                  CREATED             STATUS                      PORTS               NAMES
b89a72e1f518        centos7.5_pgsql11beta2   "/bin/bash"              28 hours ago        Exited (255) 28 hours ago                       admiring_galileo
7fe3bff33dd0        centos7.5_pgsql11beta2   "/bin/bash"              29 hours ago        Exited (1) 28 hours ago                         romantic_lamarr
7446a44cb020        postgres                 "docker-entrypoint.s…"   44 hours ago        Exited (127) 44 hours ago                       reverent_gates
b9ff94a1dae3        postgres                 "docker-entrypoint.s…"   2 days ago          Exited (0) 43 hours ago                         postgres
8081a1937fc4        postgres                 "docker-entrypoint.s…"   2 days ago          Exited (1) 2 days ago                           elated_bhaskara


# stop停止所有容器
docker stop $(docker ps -a -q)
# remove删除所有容器
docker rm $(docker ps -a -q) 
```



#### Docker 参考手册

```shell
#从官网拉取镜像

docker pull 镜像名:tag
如：docker pull centos(拉取centos的镜像到本机)

#搜索在线可用镜像名

docker search <镜像名>
如：docker search centos( 在线查找centos的镜像)

#查询所有的镜像，默认是最近创建的排在最上

docker images

#查看正在运行的容器

docker ps

# 重名名镜像

docker tag SOURCE_IMAGE[:TAG] TARGET_IMAGE[:TAG]
docker tag 49f7960eb7e4 centos:v7.5

#删除单个镜像

docker rmi -f <镜像ID>

#启动、停止操作

docker stop <容器名 or ID> #停止某个容器 
docker start <容器名 or ID> #启动某个容器 
docker kill <容器名 or ID> #杀掉某个容器

#查询某个容器的所有操作记录。

docker logs {容器ID|容器名称}

# 制作镜像  使用以下命令，根据某个“容器 ID”来创建一个新的“镜像”：

docker commit 93639a83a38e  wsl/javaweb:0.1

#启动一个容器

docker run [OPTIONS] IMAGE [COMMAND] [ARG...]

#启动docker服务的命令

service docker start

```

