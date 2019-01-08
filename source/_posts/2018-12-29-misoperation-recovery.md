---
title: 浅谈数据库误操作恢复
date: 2018-12-12
categories: 
  - [PostgreSQL - 最佳实践]
tags: 
  - RITR
  - Flashback
  - PostgreSQL
---



在使用数据库的过程中，不管是业务开发者还是运维人员，都有可能对数据库进行误操作，比如全表不带条件的update或delete等。

#### 恢复措施

误操作之后又有哪些补救措施呢？

- 延迟从库：发现误操作后，尽快利用从库还原主库。
- 基于时间点恢复（RITR）：使用由连续归档功能创建的基础备份和归档日志将数据库群恢复到任何时间点的功能。
- 闪回方案：是成本最低的一种方式，能够有效的、快速地处理一些数据库误操作等。

#### 闪回方案

闪回技术与介质恢复相比，在易用性、可用性和还原时间方面有明显的优势。这个特性大大的减少了采用时点恢复所需的工作量以及数据库脱机的时间。

闪回查询是指针对特定的表来查询特定的时间段内的数据变化情况来确定是否将表闪回到某一个特定的时刻以保证数据无误存在。

实现原理是根据PostgreSQL多版本并发控制机制、元组可见性检查规则实现，多版本保留死亡元祖，保证误操作之前的版本存在，用于闪回查询，其次，修改可见性检查规则，使事务在执行时，查询误操作之前的版本，通过闪回查询历史版本还原数据库在错误发生点之前。

为了降低保留历史版本带来的膨胀等诸多问题，vacuum需要选择性的清理历史数据，以满足闪回及PG本身正常运行的需要。

使用语法上整体保持与Oracle兼容，使用更加方便。元组头不保存事务时间信息，需要开启track_commit_timestamp = on，获取事务提交时间，以支持通过事务号、时间戳进行闪回查询。

#### 基于undo

PostgreSQL 中很多机制是跟堆表以及这种多版本实现相关的，为了避免这种多版本实现带来的诸多问题，社区开发了基于回滚段的堆表实现，详细可参考zheap。

zheap一种新的存储方式，三个主要目标：

1. 对膨胀提供更好的控制
2. 避免重写堆页，可以减少写放大
3. 通过缩小元组头和消除大多数对齐填充来减少元组大小

zheap 将通过允许就地更新来防止膨胀，zheap只会保存最后一个版本的数据在数据文件中，tupler header没有了，所有事务信息都存储在 undo 中，因此元组不需要存储此类信息的字段。

每个 undo 记录头包含正在执行操作的事务的先前 undo 记录指针的位置，因此，特定事务中的 undo 记录形成单个链接链，可以遍历undo chain来查找历史版本。

以后，可以基于回滚段实现更强大的闪回功能！

#### 实例

##### 延迟从库

默认情况下，备用服务器会尽快从主服务器恢复WAL记录。

拥有时间延迟的数据副本可能很有用，可以提供纠正数据丢失错误的机会。

```shell
# 是应用延迟，不是传输延迟
# 主库还是会等从库落盘才会提交
recovery_min_apply_delay （integer）
```

使用repmgr搭建的流复制集群，修改备节点recovery.conf，设置recovery_min_apply_delay = 5min

```shell
# primary
[yangjie@young-91 bin]$ ./repmgr cluster show
 ID | Name     | Role    | Status    | Upstream | Location | Replication lag | Last replayed LSN
----+----------+---------+-----------+----------+----------+-----------------+-------------------
 1  | young-91 | primary | * running |          | default  | n/a             | none             
 2  | young-90 | standby |   running | young-91 | default  | 0 bytes         | 0/20235CF0
 
# standby
[yangjie@young-90 bin] ./repmgr cluster show
 ID | Name     | Role    | Status    | Upstream | Location | Replication lag | Last replayed LSN
----+----------+---------+-----------+----------+----------+-----------------+-------------------
 1  | young-91 | primary | * running |          | default  | n/a             | none             
 2  | young-90 | standby |   running | young-91 | default  | 0 bytes         | 0/20235CF0  
[yangjie@young-90 bin]$ cat ../data/recovery.conf 
standby_mode = 'on'
primary_conninfo = 'host=''young-91'' user=repmgr connect_timeout=2 fallback_application_name=repmgr application_name=''young-90'''
recovery_target_timeline = 'latest'
recovery_min_apply_delay = 5min
```

在主节点创建表并插入几条数据，检查复制延迟

```sql
-- primary
-- 主节点创建表并插入几条测试数据
postgres=# create table test_recovery_delay(id int, ts timestamp);
CREATE TABLE
postgres=# insert into test_recovery_delay values (1,now());
INSERT 0 1
postgres=# insert into test_recovery_delay values (2,now());
INSERT 0 1
postgres=# select * from test_recovery_delay ;
 id |             ts             
----+----------------------------
  1 | 2019-01-08 13:07:12.699596
  2 | 2019-01-08 13:07:16.291744
(2 rows)

-- standby
postgres=# \d
                   List of relations
 Schema |           Name           |   Type   |  Owner  
--------+--------------------------+----------+---------
 public | t_test                   | table    | yangjie
 public | t_test_id_seq            | sequence | yangjie
 public | test                     | table    | yangjie
(3 rows)

-- 等五分钟

postgres=# \d
                   List of relations
 Schema |           Name           |   Type   |  Owner  
--------+--------------------------+----------+---------
 public | t_test                   | table    | yangjie
 public | t_test_id_seq            | sequence | yangjie
 public | test                     | table    | yangjie
 public | test_recovery_delay      | table    | yangjie
(4 rows)
```

也可以通过 repmgr node status 查看Last received LSN，Last replayed LSN，Replication lag等信息：

```shell
# standby
[yangjie@young-90 bin]$ ./repmgr node status
Node "young-90":
	postgres Database version: 5.1.0
	Total data size: 397 MB
	Conninfo: host=young-90 user=repmgr dbname=repmgr connect_timeout=2
	Role: standby
	WAL archiving: off
	Archive command: (none)
	Replication connections: 0 (of maximal 10)
	Replication slots: 0 (of maximal 10)
	Upstream node: young-91 (ID: 1)
	Replication lag: 395 seconds
	Last received LSN: 0/202A8ED8
	Last replayed LSN: 0/20295440
```

或者SQL：

```sql
SELECT ts, 
		last_wal_receive_lsn, 
		last_wal_replay_lsn, 
		last_xact_replay_timestamp, 
	CASE WHEN (last_wal_receive_lsn = last_wal_replay_lsn) 
		THEN 0::INT 
	ELSE 
		EXTRACT(epoch FROM (pg_catalog.clock_timestamp() - last_xact_replay_timestamp))::INT 
	END AS replication_lag_time, 
	COALESCE(last_wal_receive_lsn, '0/0') >= last_wal_replay_lsn AS receiving_streamed_wal 
FROM ( 
	SELECT CURRENT_TIMESTAMP AS ts, 
		pg_catalog.pg_last_wal_receive_lsn()       AS last_wal_receive_lsn, 
		pg_catalog.pg_last_wal_replay_lsn()        AS last_wal_replay_lsn, 
		pg_catalog.pg_last_xact_replay_timestamp() AS last_xact_replay_timestamp 
) q ;
-[ RECORD 1 ]--------------+------------------------------
ts                         | 2019-01-08 13:18:19.961552+08
last_wal_receive_lsn       | 0/202ADAC0
last_wal_replay_lsn        | 0/202AB940
last_xact_replay_timestamp | 2019-01-08 13:11:47.534904+08
replication_lag_time       | 392
receiving_streamed_wal     | t
```

##### 基于时间点恢复（RITR）

```shell
# primary
# postgresql.conf
archive_mode = on
archive_command = 'ssh young-90 test ! -f /work/pgsql/pgsql-11-stable/archives/%f && scp %p young-90:/work/pgsql/pgsql-11-stable/archives/%f'
```

创建表添加几条测试数据。

正常情况下，wal日志段在达到16M后会自动归档，由于测试我们使用手动切换归档。 

```sql
-- primary
postgres=# create table test_pitr(id int, ts timestamp);
CREATE TABLE
postgres=# select pg_switch_wal();
 pg_switch_wal 
---------------
 0/3017568
(1 row)

postgres=# insert into test_pitr values (1, now());
INSERT 0 1
postgres=# insert into test_pitr values (2, now());
INSERT 0 1
postgres=# select * from test_pitr ;
 id |             ts             
----+----------------------------
  1 | 2019-01-08 14:22:57.734731
  2 | 2019-01-08 14:23:00.598715
(2 rows)

postgres=# select pg_switch_wal();
 pg_switch_wal 
---------------
 0/4000190
(1 row)

postgres=# insert into test_pitr values (3, now());
INSERT 0 1
postgres=# insert into test_pitr values (4, now());
INSERT 0 1
postgres=# select * from test_pitr ;
 id |             ts             
----+----------------------------
  1 | 2019-01-08 14:22:57.734731
  2 | 2019-01-08 14:23:00.598715
  3 | 2019-01-08 14:23:29.175027
  4 | 2019-01-08 14:23:32.25439
(4 rows)
postgres=# select pg_switch_wal();
 pg_switch_wal 
---------------
 0/5000190
(1 row)

postgres=# insert into test_pitr values (5, now());
INSERT 0 1
postgres=# insert into test_pitr values (6, now());
INSERT 0 1
postgres=# select * from test_pitr ;
 id |             ts             
----+----------------------------
  1 | 2019-01-08 14:22:57.734731
  2 | 2019-01-08 14:23:00.598715
  3 | 2019-01-08 14:23:29.175027
  4 | 2019-01-08 14:23:32.25439
  5 | 2019-01-08 14:26:57.560111
  6 | 2019-01-08 14:27:01.015577
(6 rows)

postgres=# select pg_switch_wal();
 pg_switch_wal 
---------------
 0/6000358
(1 row)
```

正常情况下，wal日志段在达到16M后会自动归档，由于测试我们使用手动切换归档。 

```shell
# standby
ll archives/
total 98308
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:21 000000010000000000000001
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:21 000000010000000000000002
-rw------- 1 yangjie yangjie      330 Jan  8 14:21 000000010000000000000002.00000028.backup
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:22 000000010000000000000003
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:23 000000010000000000000004
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:23 000000010000000000000005
-rw------- 1 yangjie yangjie 16777216 Jan  8 14:27 000000010000000000000006
```

修改备库配置文件

```shell
# standby 
# recovery.conf
standby_mode = 'off'
primary_conninfo = 'host=''young-91'' user=repmgr application_name=young90 connect_timeout=2'
recovery_target_time = '2019-01-08 14:26:00'
restore_command = 'cp /work/pgsql/pgsql-11-stable/archives/%f %p'

# postgresql.conf
#archive_mode = on
#archive_command = 'ssh young-90 test ! -f /work/pgsql/pgsql-11-stable/archives/%f && scp %p young-90:/work/pgsql/pgsql-11-stable/archives/%f'
```

重启备库

会进行PITR恢复到指定的时间点

```shell
# standby
[yangjie@young-90 bin]$ ./pg_ctl -D ../data/ start
waiting for server to start....
2019-01-08 14:29:33.364 CST [24910] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2019-01-08 14:29:33.364 CST [24910] LOG:  listening on IPv6 address "::", port 5432
2019-01-08 14:29:33.366 CST [24910] LOG:  listening on Unix socket "/tmp/.s.PGSQL.5432"
2019-01-08 14:29:33.385 CST [24911] LOG:  database system was interrupted while in recovery at log time 2019-01-08 14:21:30 CST
2019-01-08 14:29:33.385 CST [24911] HINT:  If this has occurred more than once some data might be corrupted and you might need to choose an earlier recovery target.
2019-01-08 14:29:33.556 CST [24911] LOG:  starting point-in-time recovery to 2019-01-08 14:26:00+08
2019-01-08 14:29:33.570 CST [24911] LOG:  restored log file "000000010000000000000002" from archive
2019-01-08 14:29:33.585 CST [24911] LOG:  redo starts at 0/2000028
2019-01-08 14:29:33.599 CST [24911] LOG:  restored log file "000000010000000000000003" from archive
2019-01-08 14:29:33.630 CST [24911] LOG:  restored log file "000000010000000000000004" from archive
2019-01-08 14:29:33.662 CST [24911] LOG:  restored log file "000000010000000000000005" from archive
2019-01-08 14:29:33.694 CST [24911] LOG:  restored log file "000000010000000000000006" from archive
2019-01-08 14:29:33.709 CST [24911] LOG:  consistent recovery state reached at 0/6000060
2019-01-08 14:29:33.709 CST [24911] LOG:  recovery stopping before commit of transaction 584, time 2019-01-08 14:26:57.560463+08
2019-01-08 14:29:33.709 CST [24911] LOG:  recovery has paused
2019-01-08 14:29:33.709 CST [24911] HINT:  Execute pg_wal_replay_resume() to continue.
2019-01-08 14:29:33.709 CST [24910] LOG:  database system is ready to accept read only connections
 done
server started
[yangjie@young-90 bin]$ ./psql postgres
psql (11.1)
Type "help" for help.

postgres=# select * from test_pitr;
 id |             ts             
----+----------------------------
  1 | 2019-01-08 14:22:57.734731
  2 | 2019-01-08 14:23:00.598715
  3 | 2019-01-08 14:23:29.175027
  4 | 2019-01-08 14:23:32.25439
(4 rows)
```

##### 闪回查询



#### 相关链接

https://www.postgresql.org/docs/current/standby-settings.html

https://www.postgresql.org/docs/current/continuous-archiving.html