---
title: PostgreSQL逻辑复制实践
date: 2017-12-07 
categories: 
  - [PostgreSQL - Usage]
tags: 
  - High-availability
  - Replication
  - PostgreSQL
---



简单说一下什么是逻辑复制以及有什么好处。

大多数人都知道Streaming Replication已经成为PostgreSQL的一部分，并且通常用于高可用性和读写分离，流复制是基于WAL日志的物理复制，适用于整个数据库实例的复制，并且备库是只读的。

Logical Replication属于逻辑复制，适用于数据库实例的部分(单个数据库或者某些表)的复制，目前只支持表复制。

最大的不同就是可以向下游节点写入数据，也可以将多个数据库实例的数据，同步到一个目标数据库等等。

## 使用
Logical Replication使用piblish/subcribe概念，在上游节点创建发布者，下游节点创建订阅者。

**配置postgresql.conf**

```shell
wal_level = logical
```
**创建发布者**

```sql
yangjie=# create table users(id int, name name);
CREATE TABLE
yangjie=# create publication pub1 for table users;
CREATE PUBLICATION
```
创建发布者pub1,并添加表users.

另一种用法是添加数据库中所有用户表到发布者alltables:
```sql
create publication alltables for all tables;
```
**创建订阅者：**

```sql
yangjie=# create subscription sub1 connection 'host=192.168.102.30 port=5432 dbname=yangjie' publication pub1;
NOTICE:  created replication slot "sub1" on publisher
CREATE SUBSCRIPTION
```
订阅者sub1将会从发布者pub1复制表users.

这些都需要基础的复制工作，订阅者会拷贝所有数据到表中，创建订阅者时，表不会被复制，我们需要先自己创建这些表，如果没有发现本地表复制将会失败。

当发布者添加新表时，订阅者不能自动的获知，我们需要更新订阅者：

```sql
alter subscription sub refresh publication;
```
这会从新表中拷贝所有存在的数据。

**示例：**

先创建发布者、订阅者：
```sql
# publication
yangjie=# create publication mypub for all tables;
CREATE PUBLICATION

yangjie=# create subscription mysub connection 'host=192.168.102.30 port=5432 dbname=yangjie' publication mypub;
CREATE SUBSCRIPTION
```
上游节点添加一张表并插入数据：
```sql
yangjie=# create table a(id int);
CREATE TABLE
yangjie=# insert into a values (1);
INSERT 0 1

yangjie=# select * from a ;
 id
----
  1
(1 row)
```
下游节点添加上表并查询：
```sql
yangjie# create table a(id int);
CREATE TABLE

yangjie=# select * from a;
 id
----
(0 rows)
```
更新订阅者：
```sql
yangjie=# alter subscription mysub refresh publication ;
ALTER SUBSCRIPTION

yangjie=# select * from a;
 id
----
  1
(1 row)
```
## 监控
现在我们已经配置好了逻辑复制，为了能清楚地知道它如何运行等，提供了两张视图，pg_stat_replication显示当前服务的所有复制连接，pg_stat_subscription下游节点显示订阅者的状态信息。

```sql
# publication
yangjie=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+------------------------------
pid              | 5743
usesysid         | 10
usename          | yangjie
application_name | sub1
client_addr      | 192.168.102.34
client_hostname  | 
client_port      | 34094
backend_start    | 2017-11-23 17:22:08.460961+08
backend_xmin     | 
state            | streaming
sent_lsn         | 0/308DCB8
write_lsn        | 0/308DCB8
flush_lsn        | 0/308DCB8
replay_lsn       | 0/308DCB8
write_lag        | 
flush_lag        | 
replay_lag       | 
sync_priority    | 0
sync_state       | async
```

```sql
# subscription
yangjie=# select * from pg_stat_subscription ;
-[ RECORD 1 ]---------+------------------------------
subid                 | 16388
subname               | sub1
pid                   | 10810
relid                 | 
received_lsn          | 0/308DCB8
last_msg_send_time    | 2017-11-23 17:22:08.484458+08
last_msg_receipt_time | 2017-11-23 17:22:08.476762+08
latest_end_lsn        | 0/308DCB8
latest_end_time       | 2017-11-23 17:22:08.484458+08
```
## 进程信息

```shell
# publication
[yangjie@young-1 ~]$ ps -ef | grep postgres
yangjie   4266 31571  0 Nov23 ?        00:00:00 postgres: yangjie yangjie [local] idle
yangjie   5743 31571  0 Nov23 ?        00:00:00 postgres: wal sender process yangjie 192.168.102.34(34094) idle
yangjie  14395 14347  0 09:22 pts/2    00:00:00 grep --color=auto postgres
yangjie  31571     1  0 Nov23 ?        00:00:01 /opt/pgsql/pg101/bin/postgres -D ../data
yangjie  31573 31571  0 Nov23 ?        00:00:00 postgres: checkpointer process   
yangjie  31574 31571  0 Nov23 ?        00:00:00 postgres: writer process   
yangjie  31575 31571  0 Nov23 ?        00:00:00 postgres: wal writer process   
yangjie  31576 31571  0 Nov23 ?        00:00:01 postgres: autovacuum launcher process   
yangjie  31577 31571  0 Nov23 ?        00:00:01 postgres: stats collector process   
yangjie  31578 31571  0 Nov23 ?        00:00:00 postgres: bgworker: logical replication launcher
```

```shell
# subscription
[yangjie@young-2 ~]$ ps -ef | grep postgres
yangjie   9222     1  0 Nov23 pts/1    00:00:01 /opt/pgsql/pg101-2/bin/postgres -D ../data
yangjie   9224  9222  0 Nov23 ?        00:00:00 postgres: checkpointer process   
yangjie   9225  9222  0 Nov23 ?        00:00:00 postgres: writer process   
yangjie   9226  9222  0 Nov23 ?        00:00:00 postgres: wal writer process   
yangjie   9227  9222  0 Nov23 ?        00:00:01 postgres: autovacuum launcher process   
yangjie   9228  9222  0 Nov23 ?        00:00:02 postgres: stats collector process   
yangjie   9229  9222  0 Nov23 ?        00:00:00 postgres: bgworker: logical replication launcher  
yangjie   9287  9222  0 Nov23 ?        00:00:00 postgres: yangjie yangjie [local] idle
yangjie  10810  9222  0 Nov23 ?        00:00:04 postgres: bgworker: logical replication worker for subscription 16388  
yangjie  26627 26570  0 09:22 pts/0    00:00:00 grep --color=auto postgres
```
## 示例
在上游节点创建发布者：

```sql
yangjie=# create table users(id int, name name);
CREATE TABLE

yangjie=# insert into users values (1, 'Jie Yang');
INSERT 0 1

yangjie=# create publication pub1 for table users;
CREATE PUBLICATION
```
设置订阅者：

```sql
yangjie=# create table users (id int, name name);
CREATE TABLE

yangjie=# create subscription sub1 connection 'host=192.168.102.30 port=5432 dbname=yangjie' publication pub1;
NOTICE:  created replication slot "sub1" on publisher
CREATE SUBSCRIPTION
```
这里将会将会同步表信息并在上游节点创建一个复制槽sub1：

```sql
# subscription
yangjie=# select * from users ;
 id |   name   
----+----------
  1 | Jie Yang
(1 row)

yangjie=# select * from pg_replication_slots ;
-[ RECORD 1 ]-------+----------
slot_name           | sub1
plugin              | pgoutput
slot_type           | logical
datoid              | 16384
database            | yangjie
temporary           | f
active              | t
active_pid          | 15386
xmin                | 
catalog_xmin        | 593
restart_lsn         | 0/308DF28
confirmed_flush_lsn | 0/308DF60
```
查看订阅者状态：

```sql
# subscription
yangjie=# select * from pg_stat_subscription ;
-[ RECORD 1 ]---------+------------------------------
subid                 | 16393
subname               | sub1
pid                   | 27705
relid                 | 
received_lsn          | 0/308DF60
last_msg_send_time    | 2017-11-24 09:29:41.820483+08
last_msg_receipt_time | 2017-11-24 09:29:41.818227+08
latest_end_lsn        | 0/308DF60
latest_end_time       | 2017-11-24 09:29:41.820483+08
```
查看复制状态：
```sql
# publication
yangjie=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+------------------------------
pid              | 15386
usesysid         | 10
usename          | yangjie
application_name | sub1
client_addr      | 192.168.102.34
client_hostname  | 
client_port      | 41152
backend_start    | 2017-11-24 09:29:41.796288+08
backend_xmin     | 
state            | streaming
sent_lsn         | 0/308DF60
write_lsn        | 0/308DF60
flush_lsn        | 0/308DF60
replay_lsn       | 0/308DF60
write_lag        | 
flush_lag        | 
replay_lag       | 
sync_priority    | 0
sync_state       | async
```
注意这里的application_name与我们创建订阅者的名字相同。

在插入一行，看是否复制：

```sql
# publication
yangjie=# insert into users values (2, 'Joe Yang');
INSERT 0 1
```
查看订阅者：
```sql
# subscription
yangjie=# select * from users ;
 id |   name   
----+----------
  1 | Jie Yang
  2 | Joe Yang
(2 rows)
```
复制标识(replica identity)：

为了逻辑复制能在下游节点正确执行UPDATE和DELETE，我们需要定义如何找到唯一行，这就是复制标识，默认情况下，复制标识将是表的主键，如果已经定义了主键，将不需要做任何动作，
```sql
yangjie=# update users set name = 'Jee Yang' where id = 2;
ERROR:  cannot update table "users" because it does not have a replica identity and publishes updates
HINT:  To enable updating the table, set REPLICA IDENTITY using ALTER TABLE.
```
配置replica identity：
```sql
yangjie=# alter table users add primary key(id);
ALTER TABLE

# 明确定义复制标识
yangjie=# alter table users replica identity using index users_pkey;
ALTER TABLE

yangjie=# \d+ users
                                   Table "public.users"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           | not null |         | plain   |              | 
 name   | name    |           |          |         | plain   |              | 
Indexes:
    "users_pkey" PRIMARY KEY, btree (id) REPLICA IDENTITY
Publications:
    "pub1"

yangjie=# update users set name = 'Jee Yang' where id = 2;
UPDATE 1

```
查询：
```sql
# subscription
yangjie=# alter table users add primary key(id);
ALTER TABLE


yangjie=# select * from users ;
 id |   name   
----+----------
  1 | Jie Yang
  2 | Jee Yang
(2 rows)
```

## 灵活性

订阅者添加额外字段：

```sql
# subscription
yangjie=# alter table users add age int;
ALTER TABLE

# publication
yangjie=# insert INTO users values (3, 'Joe Yang');
INSERT 0 1

# subscription
yangjie=# select * from users ;
 id |   name   | age 
----+----------+-----
  1 | Jie Yang |    
  2 | Jee Yang |    
  3 | Joe Yang |    
(3 rows)
```
多个数据库实例的数据，同步到一个目标数据库

```sql
# publication host=192.168.102.30 port=5431
yangjie=# create table users (id int primary key, name name, age int);
CREATE TABLE

yangjie=# insert into users values (11, 'Jre Yang', 24);
INSERT 0 1

yangjie=# create publication pub1 for table users ;
CREATE PUBLICATION

# subscription
yangjie=# create subscription sub2 connection 'host=localhost port=5431 dbname=yangjie' publication pub1;
NOTICE:  created replication slot "sub2" on publisher
CREATE SUBSCRIPTION

yangjie=# select * from users ;
 id |   name   | age 
----+----------+-----
  1 | Jie Yang |    
  2 | Jee Yang |    
  3 | Joe Yang | 
 11 | Jre Yang |  24
(4 rows)

# publication 2
yangjie=# update users set age = 23 where id = 11;
UPDATE 1
yangjie=# select * from users ;
 id |   name   | age 
----+----------+-----
 11 | Jre Yang |  23
(1 row)

# NOTICE:创建

# subscription
yangjie=# select * from users ;
 id |   name   | age 
----+----------+-----
  1 | Jie Yang |    
  2 | Jee Yang |    
  3 | Joe Yang | 
 11 | Jre Yang |  23
(4 rows)
```
同理：也可以将一个数据库实例的不同数据，复制到不同的目标库，或者多个数据库实例之间，共享部分数据等等。

## 总结
**publication - 发布者**

- 逻辑复制的前提是将数据库 wal_level 参数设置成 logical；
- 源库上逻辑复制的用户必须具有 replicatoin 或 superuser 角色；
- 逻辑复制目前仅支持数据库表逻辑复制，其它对象例如函数、视图不支持；
- 逻辑复制支持DML(UPDATE、INSERT、DELETE)操作，TRUNCATE 和 DDL 操作不支持；
- 需要发布逻辑复制的表，须配置表的 REPLICA IDENTITY 特性；
- 一个数据库中可以有多个publication，通过 pg_publication  查看；
- 允许一次发布所有表，语法： CREATE PUBLICATION alltables FOR ALL TABLES;

**subscription - 订阅者**

- 订阅节点需要指定发布者的连接信息；
- 一个数据库中可以有多个订阅者；
- 可以使用enable/disable启用/暂停该订阅；
- 发布节点和订阅节点表的模式名、表名必须一致，订阅节点允许表有额外字段；
- 发布节点增加表名，订阅节点需要执行： ALTER SUBSCRIPTION sub1 REFRESH PUBLICATION  