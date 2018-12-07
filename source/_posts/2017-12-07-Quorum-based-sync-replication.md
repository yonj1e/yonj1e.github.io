---
title: 基于Quorum同步流复制
date: 2017-12-07 
categories: 
  - [PostgreSQL - 特性分析]
tags: 
  - Replication
  - PostgreSQL
  - High-availability
---



## 简介

同步复制功能是PG9.1版本添加的。

**PG9.6之前版本的同步复制中，同步的备用数据库只能有一个实例**，异步的可以有多个实例，
在同步的备用数据库实例宕掉之后，异步的备用服务器可以升级为同步备用数据库实例。
其配置参数如下：

```shell
synchronous_standby_names = application_name, application_name, …
```

配置中第一个application_name是同步备用数据库实例，后面的是潜在的同步备用数据库实例(potential synchronous standby)。

**PG9.6中，可以实现多个备用数据库实例实现同步复制**。
其配置参数如下：

```shell
synchronous_standby_names = num_sync (application_name, application_name, …)
```

num_sync是指定的同步备用数据库实例个数，括号中是指定的一系列备用数据库实例。前num_sync是同步备用数据库实例，超过num_sync时，后面的是潜在的同步备用数据库实例，
其中同步备用服务器实例根据list中application_name的前后顺序确定优先级，即越靠前的优先级越高。主库只有在接收到num_sync个备用数据库实例返回的确认信息后，才commit。

如果其中一台，同步备用服务器挂掉的话，其他潜在的同步备库升级为同步备库。

**PG10中，实现了基于Quorum的同步复制**，即
其配置参数如下：

```shell
synchronous_standby_names = FIRST | ANY num_sync (application_name, application_name, …)
```

如果指定了FIRST参数或忽略，其行为和PG9.6一样，是指定了优先级的同步复制，主库只有在接收到前num_sync个优先级较高的同步备用服务器实例的确认信息后才commit。

如果一台同步备用数据库实例宕掉的话，后面的备用数据库会替换掉该数据库实例。

如果指定了ANY参数，则是指定了基于Quorum的同步复制，主库只需要接收到application_name列表中的任意num_sync个数据库实例的返回确认信息就可以commit。这种设置不需要优先级高的返回才能commit。


**对比三个版本同步复制的主要区别**：

- pg9.5 --- 数据库只能在一台备库上进行同步复制，可以指定多个，一个同步的，其他是异步的， 同步备库挂掉的话，其他的升级为同步备库。
- pg9.6 --- 数据库可以实现多个备库进行同步复制，但主库需要接收到指定num_sync个优先级的备库的确认信息后，才commit。
- pg10  --- 数据库可以实现多个备库进行同步复制， 主库只需要接收到任意num_sync个备库的确认信息后，就可以commit。

[Multiple Synchronous Standbys](https://www.postgresql.org/docs/10/static/warm-standby.html#SYNCHRONOUS-REPLICATION)

Synchronous replication supports one or more synchronous standby servers; transactions will wait until all the standby servers which are considered as synchronous confirm receipt of their data. The number of synchronous standbys that transactions must wait for replies from is specified in synchronous_standby_names. This parameter also specifies a list of standby names and the method (FIRST and ANY) to choose synchronous standbys from the listed ones.

The method FIRST specifies a priority-based synchronous replication and makes transaction commits wait until their WAL records are replicated to the requested number of synchronous standbys chosen based on their priorities. The standbys whose names appear earlier in the list are given higher priority and will be considered as synchronous. Other standby servers appearing later in this list represent potential synchronous standbys. If any of the current synchronous standbys disconnects for whatever reason, it will be replaced immediately with the next-highest-priority standby.

An example of synchronous_standby_names for a priority-based multiple synchronous standbys is:


```shell
synchronous_standby_names = 'FIRST 2 (s1, s2, s3)'
```

**In this example, if four standby servers s1, s2, s3 and s4 are running, the two standbys s1 and s2 will be chosen as synchronous standbys because their names appear early in the list of standby names. s3 is a potential synchronous standby and will take over the role of synchronous standby when either of s1 or s2 fails. s4 is an asynchronous standby since its name is not in the list.**

The method ANY specifies a quorum-based synchronous replication and makes transaction commits wait until their WAL records are replicated to at least the requested number of synchronous standbys in the list.

An example of synchronous_standby_names for a quorum-based multiple synchronous standbys is:


```shell
synchronous_standby_names = 'ANY 2 (s1, s2, s3)'
```

In this example, if four standby servers s1, s2, s3 and s4 are running, transaction commits will wait for replies from at least any two standbys of s1, s2 and s3. s4 is an asynchronous standby since its name is not in the list.

The synchronous states of standby servers can be viewed using the [pg_stat_replication](https://www.postgresql.org/docs/10/static/monitoring-stats.html#PG-STAT-REPLICATION-VIEW) view.

```shell
Synchronous state of this standby server. Possible values are:
- async: This standby server is asynchronous.
- potential: This standby server is now asynchronous, but can potentially become synchronous if one of current synchronous ones fails.
- sync: This standby server is synchronous.
- quorum: This standby server is considered as a candidate for quorum standbys.
```

## 测试
**环境：**

主机名 | ip | 角色 | port | 系统 | 数据库 | 数据目录
---|---|---|---|---|---|---
young-1 | 192.168.102.30 | master | 5432 | CentOS 7.1 | PostgreSQL 10.1 | /work/pgsql/pg10/data-master
young-2 | 192.168.102.34 | slave1 | 5431 | CentOS 7.1 | PostgreSQL 10.1 | /work/pgsql/pg10/data-slave1
young-2 | 192.168.102.34 | slave2 | 5432 | CentOS 7.1 | PostgreSQL 10.1 | /work/pgsql/pg10/data-slave2
young-2 | 192.168.102.34 | slave3 | 5433 | CentOS 7.1 | PostgreSQL 10.1 | /work/pgsql/pg10/data-slave3
young-2 | 192.168.102.34 | slave4 | 5434 | CentOS 7.1 | PostgreSQL 10.1 | /work/pgsql/pg10/data-slave4

同步流复制搭建

**基于优先级**

```shell
synchronous_standby_names = '2 (stdb01,stdb02,stdb03)'  # standby servers that provide sync rep
                                # method to choose sync standbys, number of sync standbys,
                                # and comma-separated list of application_name
                                # from standby(s); '*' = all

```

```sql
yangjie=# select application_name,pid,state,client_addr,sync_priority,sync_state from pg_stat_replication;
 application_name |  pid  |   state   |  client_addr   | sync_priority | sync_state 
------------------+-------+-----------+----------------+---------------+------------
 stdb01           | 22965 | streaming | 192.168.102.34 |             1 | sync
 stdb02           | 22967 | streaming | 192.168.102.34 |             2 | sync
 stdb03           | 22964 | streaming | 192.168.102.34 |             3 | potential
 walreceiver      | 22966 | streaming | 192.168.102.34 |             0 | async
(4 rows)
```
四个元组表示有四个备份服务，stdb01,stdb02是同步备库，stdb03是潜在的同步备库，当前是异步复制，stdb01、stdb02中如果有一个宕机，stdb03就会成为同步备库，最后一个元组没有在synchronous_standby_names中，它是异步备库。

```sql
# young-2 slave2
[yangjie@young-2 bin]$ ./pg_ctl -D ../data-slave2/ stop

# young-1 master
yangjie=# 2017-12-07 14:08:28.024 CST [22964] LOG:  standby "stdb03" is now a synchronous standby with priority 3

yangjie=# select application_name,pid,state,client_addr,sync_priority,sync_state from pg_stat_replication;
 application_name |  pid  |   state   |  client_addr   | sync_priority | sync_state 
------------------+-------+-----------+----------------+---------------+------------
 stdb03           | 22964 | streaming | 192.168.102.34 |             3 | sync
 walreceiver      | 22966 | streaming | 192.168.102.34 |             0 | async
 stdb02           | 22967 | streaming | 192.168.102.34 |             2 | sync
(3 rows)
```

**基于Quorum**

```shell
ynchronous_standby_names = 'any 2 (stdb01,stdb02,stdb03)'      # standby servers that provide sync rep
                                # method to choose sync standbys, number of sync standbys,
                                # and comma-separated list of application_name
                                # from standby(s); '*' = all
```

```sql
yangjie=# select application_name,pid,state,client_addr,sync_priority,sync_state from pg_stat_replication;
 application_name |  pid  |   state   |  client_addr   | sync_priority | sync_state 
------------------+-------+-----------+----------------+---------------+------------
 stdb01           | 28526 | streaming | 192.168.102.34 |             1 | quorum
 stdb02           | 28528 | streaming | 192.168.102.34 |             1 | quorum
 stdb03           | 28525 | streaming | 192.168.102.34 |             1 | quorum
 walreceiver      | 28527 | streaming | 192.168.102.34 |             0 | async
(4 rows)
```
