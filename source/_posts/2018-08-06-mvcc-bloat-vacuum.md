---
title: 理解MVCC和VACUUM以及调整AutoVacuum
date: 2018-08-06
categories: 
  - [PostgreSQL - 特性分析]
tags: 
  - MVCC
  - AutoVacuum
  - PostgreSQL
  - Transaction
---



与其他RDBMS相比，PostgreSQL中MVCC（多版本并发控制）的实现是不同的和特殊的。PostgreSQL中的MVCC可以通过版本控制控制哪些元组对事务可见。

#### PostgreSQL中的版本控制是什么？

让我们考虑Oracle或MySQL数据库的情况。执行行的DELETE或UPDATE时会发生什么？ 您可以在全局撤销段中看到UNDO记录。此UNDO段包含一行的过去快照，以帮助数据库实现一致性。（A.C.I.D中的“C”）。例如，如果存在依赖于已删除的行的旧事务，则该行可能仍然可见，因为过去的快照仍保留在UNDO中。如果阅读此博客文章的您是的Oracle DBA，您可能会很快会收到错误ORA-01555 snapshot too old。这个错误意味着什么 - 你可能有一个较小的undo_retention或者没有一个巨大的UNDO段，它可以保留现有或旧的事务所需的所有过去的快照（版本）。

你可能不必担心PostgreSQL。

#### PostgreSQL如何管理UNDO？

简单来说，PostgreSQL在其自己的表中维护过去的快照和行的最新快照。这意味着，UNDO保留在每个表内。这是通过版本控制完成的。现在，我们可能会得到一个暗示，PostgreSQL表的每一行都有一个版本号。这绝对是正确的。为了理解每个表中如何维护这些版本，您应该了解PostgreSQL中表（尤其是xmin）的隐藏列。

#### 了解表的隐藏列

描述表时，您只会看到已添加的列，就像您在以下看到的那样。

```sql
percona=# \d scott.employee
                                          Table "scott.employee"
  Column  |          Type          | Collation | Nullable |                    Default
----------+------------------------+-----------+----------+------------------------------------------------
 emp_id   | integer                |           | not null | nextval('scott.employee_emp_id_seq'::regclass)
 emp_name | character varying(100) |           |          |
 dept_id  | integer                |           |          |
```

但是，如果在pg_attribute中查看表的所有列，您应该看到几个隐藏列，如下所示。

```sql
percona=# SELECT attname, format_type (atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid::regclass::text='scott.employee'
ORDER BY attnum;
 attname  |      format_type       
----------+------------------------
 tableoid | oid
 cmax     | cid
 xmax     | xid
 cmin     | cid
 xmin     | xid
 ctid     | tid
 emp_id   | integer
 emp_name | character varying(100)
 dept_id  | integer
(9 rows)
```

让我们详细了解一些隐藏列。

tableoid：包含该行的表的OID。由从继承层次结构中选择的查询使用。
有关表继承的更多详细信息，请访问：https://www.postgresql.org/docs/current/static/ddl-inherit.html

xmin：插入此行版本的事务的事务ID（xid）。更新后，将插入新的行版本。让我们看一下以下内容来更好地理解xmin。

```sql
percona=# select txid_current();
 txid_current 
--------------
          646
(1 row)
 
percona=# INSERT into scott.employee VALUES (9,'avi',9);
INSERT 0 1
percona=# select xmin,xmax,cmin,cmax,* from scott.employee where emp_id = 9;
 xmin | xmax | cmin | cmax | emp_id | emp_name | dept_id 
------+------+------+------+--------+----------+---------
  647 |    0 |    0 |    0 |      9 | avi      |       9
(1 row)
```

正如您在上面看到的那样，`select txid_current()` 命令的事务ID为646。因此，INSERT语句获得了事务ID 647，因此，该记录被分配xmin 647。这意味着，任何在ID 647之前启动的事务ID都不能看到该行。换句话说，已经运行txid小于647的事务，无法看到txid 647插入的行。

通过上面的示例，您现在应该了解每个元组都有一个xmin，它被分配了插入它的txid。

注意：根据您选择的隔离级别，行为可能会发生变化，稍后将在另一篇博客文章中讨论。

xmax：如果它不是已删除的行版本，则此值为0。在提交DELETE之前，行版本的xmax将更改为已发出DELETE的事务的ID。让我们通过以下操作以更好地理解。

在终端A：我们打开一个事务并删除一行而不提交它。

```sql
percona=# BEGIN;
BEGIN
percona=# select txid_current();
 txid_current 
--------------
          655
(1 row)
 
percona=# DELETE from scott.employee where emp_id = 10;
DELETE 1
```

在终端B上：观察删除前后的xmax值（尚未提交）。

```sql
Before the Delete
------------------
percona=# select xmin,xmax,cmin,cmax,* from scott.employee where emp_id = 10;
 xmin | xmax | cmin | cmax | emp_id | emp_name | dept_id 
------+------+------+------+--------+----------+---------
  649 |    0 |    0 |    0 |     10 | avi      |      10
 
After the Delete
------------------
percona=# select xmin,xmax,cmin,cmax,* from scott.employee where emp_id = 10;
 xmin | xmax | cmin | cmax | emp_id | emp_name | dept_id 
------+------+------+------+--------+----------+---------
  649 |  655 |    0 |    0 |     10 | avi      |      10
(1 row)
```

正如您在上面的日志中看到的那样，xmax值已更改为已发出删除的事务ID。如果您已发出ROLLBACK，或者事务已中止，则xmax将保留在尝试删除它的事务ID（在这种情况下为655）。

现在我们了解了隐藏的列xmin和xmax，让我们观察PostgreSQL中DELETE或UPDATE之后会发生什么。正如我们前面所讨论的，通过PostgreSQL中每个表的隐藏列，我们知道每个表中都有多个版本的行。让我们看看下面的例子来更好地理解这一点。

我们将向表中插入10条记录：scott.employee

```sql
percona=# INSERT into scott.employee VALUES (generate_series(1,10),'avi',1);
INSERT 0 10
```

现在，让我们从表中删除5条记录。

```sql
percona=# DELETE from scott.employee where emp_id > 5;
DELETE 5
percona=# select count(*) from scott.employee;
 count 
-------
     5
(1 row)
```

现在，当您在DELETE之后检查计数时，您将看不到已删除的记录。要查看表中存在但不可见的任何行版本，我们有一个名为pageinspect的扩展。`pageinspect` 扩展提供的功能允许您以较低级别检查数据库页面的内容，这对于调试非常有用。让我们创建此扩展以查看已删除的旧行版本。

```sql
percona=# CREATE EXTENSION pageinspect;
CREATE EXTENSION
percona=# SELECT t_xmin, t_xmax, tuple_data_split('scott.employee'::regclass, t_data, t_infomask, t_infomask2, t_bits) FROM heap_page_items(get_raw_page('scott.employee', 0));
 t_xmin | t_xmax |              tuple_data_split
--------+--------+---------------------------------------------
    668 |      0 | {"\\x01000000","\\x09617669","\\x01000000"}
    668 |      0 | {"\\x02000000","\\x09617669","\\x01000000"}
    668 |      0 | {"\\x03000000","\\x09617669","\\x01000000"}
    668 |      0 | {"\\x04000000","\\x09617669","\\x01000000"}
    668 |      0 | {"\\x05000000","\\x09617669","\\x01000000"}
    668 |    669 | {"\\x06000000","\\x09617669","\\x01000000"}
    668 |    669 | {"\\x07000000","\\x09617669","\\x01000000"}
    668 |    669 | {"\\x08000000","\\x09617669","\\x01000000"}
    668 |    669 | {"\\x09000000","\\x09617669","\\x01000000"}
    668 |    669 | {"\\x0a000000","\\x09617669","\\x01000000"}
(10 rows)
```

现在，即使删除了5条记录，我们仍然可以在表格中看到10条记录。此外，您可以在此处观察到t_xmax设置为已删除它们的事务ID。这些已删除的记录保留在同一个表中，以便为仍在访问它们的任何旧事务提供服务。

我们将在下面的日志中看一看UPDATE会做什么。

```sql
percona=# DROP TABLE scott.employee ;
DROP TABLE
percona=# CREATE TABLE scott.employee (emp_id INT, emp_name VARCHAR(100), dept_id INT);
CREATE TABLE
percona=# INSERT into scott.employee VALUES (generate_series(1,10),'avi',1);
INSERT 0 10
percona=# UPDATE scott.employee SET emp_name = 'avii';
UPDATE 10
percona=# SELECT t_xmin, t_xmax, tuple_data_split('scott.employee'::regclass, t_data, t_infomask, t_infomask2, t_bits) FROM heap_page_items(get_raw_page('scott.employee', 0));
 t_xmin | t_xmax |               tuple_data_split
--------+--------+-----------------------------------------------
    672 |    673 | {"\\x01000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x02000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x03000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x04000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x05000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x06000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x07000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x08000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x09000000","\\x09617669","\\x01000000"}
    672 |    673 | {"\\x0a000000","\\x09617669","\\x01000000"}
    673 |      0 | {"\\x01000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x02000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x03000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x04000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x05000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x06000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x07000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x08000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x09000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x0a000000","\\x0b61766969","\\x01000000"}
(20 rows)
```

PostgreSQL中的UPDATE将执行INSERT和DELETE。因此，所有更新的记录都已删除，并以新值重新插入。删除的记录具有非零的t_xmax值。

对于您看到t_xmax的非零值的记录，以前的事务可能需要它，以确保基于适当的隔离级别的一致性。

我们讨论了xmin和xmax。cmin和cmax这些隐藏的列是什么？

cmax：删除事务中的命令标识符或为零。（依据[官方文档](https://www.postgresql.org/docs/current/static/ddl-system-columns.html)）。但是，依据PostgreSQL源代码cmin和cmax是相同的。

cmin：插入事务中的命令标识符。您可以在以下日志中看到以0开头的3个insert语句的cmin。

请参阅以下日志以了解cmin和cmax值如何通过事务中的插入和删除进行更改。

```sql
On Terminal A
---------------
percona=# BEGIN;
BEGIN
percona=# INSERT into scott.employee VALUES (1,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (2,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (3,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (4,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (5,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (6,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (7,'avi',2);
INSERT 0 1
percona=# INSERT into scott.employee VALUES (8,'avi',2);
INSERT 0 1
percona=# COMMIT;
COMMIT
percona=# select xmin,xmax,cmin,cmax,* from scott.employee;
 xmin | xmax | cmin | cmax | emp_id | emp_name | dept_id
------+------+------+------+--------+----------+---------
  644 |    0 |    0 |    0 |      1 | avi      |       2
  644 |    0 |    1 |    1 |      2 | avi      |       2
  644 |    0 |    2 |    2 |      3 | avi      |       2
  644 |    0 |    3 |    3 |      4 | avi      |       2
  644 |    0 |    4 |    4 |      5 | avi      |       2
  644 |    0 |    5 |    5 |      6 | avi      |       2
  644 |    0 |    6 |    6 |      7 | avi      |       2
  644 |    0 |    7 |    7 |      8 | avi      |       2
(8 rows)
```

如果观察到上面的输出日志，就会看到cmin和cmax值随着每次插入而递增。

现在，让我们从终端A中删除3条记录，并观察在提交之前，这些值在终端B中是如何显示的。  

```sql
On Terminal A
---------------
percona=# BEGIN;
BEGIN
percona=# DELETE from scott.employee where emp_id = 4;
DELETE 1
percona=# DELETE from scott.employee where emp_id = 5;
DELETE 1
percona=# DELETE from scott.employee where emp_id = 6;
DELETE 1

On Terminal B, before issuing COMMIT on Terminal A
----------------------------------------------------
percona=# select xmin,xmax,cmin,cmax,* from scott.employee;
 xmin | xmax | cmin | cmax | emp_id | emp_name | dept_id
------+------+------+------+--------+----------+---------
  644 |    0 |    0 |    0 |      1 | avi      |       2
  644 |    0 |    1 |    1 |      2 | avi      |       2
  644 |    0 |    2 |    2 |      3 | avi      |       2
  644 |  645 |    0 |    0 |      4 | avi      |       2
  644 |  645 |    1 |    1 |      5 | avi      |       2
  644 |  645 |    2 |    2 |      6 | avi      |       2
  644 |    0 |    6 |    6 |      7 | avi      |       2
  644 |    0 |    7 |    7 |      8 | avi      |       2
(8 rows)
```

现在，在上面的日志中，您可以看到对于被删除的记录，cmax和cmin值从0开始递增。正如我们之前看到的那样，它们的值在删除之前是不同的。即使你ROLLBACK，值仍保持不变。

在了解了隐藏列以及PostgreSQL如何将UNDO维护为多个版本的行之后，下一个问题将是-如何从表中清除这些UNDO？这不是不断增加一个表的大小吗？为了更好地理解这一点，我们需要了解PostgreSQL中的VACUUM。

#### PostgreSQL中的VACUUM

如上例所示，每个已被删除但仍占用一些空间的记录称为死亡元组。一旦已经运行的事务不再依赖那些死亡元组，就不再需要它们了。因此，PostgreSQL在这些表上运行VACUUM。VACUUM回收了这些死亡元组占用的存储空间。这些死亡元组占据的空间可以称为Bloat。VACUUM扫描页面中的死亡元组，并将它们标记到空闲空间映射表（FSM）。除散列索引之外的每个关系都有一个FSM，存储在一个名为<relation_oid> _fsm的单独文件中。

这里，relation_oid是pg_class中可见的关系的oid。

```sql
percona=# select oid from pg_class where relname = 'employee';
  oid  
-------
 24613
(1 row)
```

在VACUUM时，此空间不会回收到磁盘，但在此表上的未来插入中可以重复使用。VACUUM将每个堆（或索引）页面上的可用空间存储到FSM文件。

运行VACUUM是一种非阻塞操作。它永远不会导致对表的独占锁定。这意味着VACUUM可以在生产中的繁忙事务表上运行，同时有多个事务写入它。

正如我们之前讨论的那样，10条记录的更新产生了10个死亡元组。让我们看一下以下日志，了解VACUUM之后那些死亡元组会发生什么。

```sql
percona=# VACUUM scott.employee ;
VACUUM
percona=# SELECT t_xmin, t_xmax, tuple_data_split('scott.employee'::regclass, t_data, t_infomask, t_infomask2, t_bits) FROM heap_page_items(get_raw_page('scott.employee', 0));
 t_xmin | t_xmax |               tuple_data_split                
--------+--------+-----------------------------------------------
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
        |        | 
    673 |      0 | {"\\x01000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x02000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x03000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x04000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x05000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x06000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x07000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x08000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x09000000","\\x0b61766969","\\x01000000"}
    673 |      0 | {"\\x0a000000","\\x0b61766969","\\x01000000"}
(20 rows)
```

在上面的日志中，您可能会注意到已删除死亡元组并且该空间可供重用。但是，在VACUUM之后，此空间不会回收到文件系统。只有将来的插入才能使用此空间。

VACUUM还有一项额外的任务。过去插入并成功提交的所有行都标记为frozen，这表示它们对所有当前和未来的事务都可见。

VACUUM通常不会回收文件系统的空间，除非死亡元组超出了高水位线。

让我们考虑以下示例来查看VACUUM何时可以释放文件系统的空间。

创建一个表并插入一些示例记录。根据主键索引在磁盘上对记录进行物理排序。

```sql
percona=# CREATE TABLE scott.employee (emp_id int PRIMARY KEY, name varchar(20), dept_id int);
CREATE TABLE
percona=# INSERT INTO scott.employee VALUES (generate_series(1,1000), 'avi', 1);
INSERT 0 1000
```

现在，在表上运行ANALYZE以更新其统计信息，并查看在上述插入后分配给表的页数。

```sql
percona=# ANALYZE scott.employee ;
ANALYZE
percona=# select relpages, relpages*8192 as total_bytes, pg_relation_size('scott.employee') as relsize 
FROM pg_class 
WHERE relname = 'employee';
relpages | total_bytes | relsize 
---------+-------------+---------
6        | 49152       | 49152
(1 row)
```

现在让我们看一下当你删除emp_id> 500的行时VACUUM的行为

```sql
percona=# DELETE from scott.employee where emp_id > 500;
DELETE 500
percona=# VACUUM ANALYZE scott.employee ;
VACUUM
percona=# select relpages, relpages*8192 as total_bytes, pg_relation_size('scott.employee') as relsize 
FROM pg_class 
WHERE relname = 'employee';
relpages | total_bytes | relsize 
---------+-------------+---------
3        | 24576       | 24576
(1 row)
```

在上面的日志中，您看到VACUUM已经回收了文件系统的一半空间。之前，它占用了6页（每页8KB或设置为参数：block_size）。在VACUUM之后，它已经向文件系统发布了3个页面。

现在，让我们通过删除emp_id <500的行来重复相同的操作。

```sql
percona=# DELETE from scott.employee ;
DELETE 500
percona=# INSERT INTO scott.employee VALUES (generate_series(1,1000), 'avi', 1);
INSERT 0 1000
percona=# DELETE from scott.employee where emp_id < 500;
DELETE 499
percona=# VACUUM ANALYZE scott.employee ;
VACUUM
percona=# select relpages, relpages*8192 as total_bytes, pg_relation_size('scott.employee') as relsize 
FROM pg_class 
WHERE relname = 'employee';
 relpages | total_bytes | relsize 
----------+-------------+---------
        6 |       49152 |   49152
(1 row)
```

在上面的示例中，您可以看到，在从表中删除一半记录之后，页面数量仍然保持不变。这意味着这次VACUUM没有释放空间到文件系统。

正如前面所解释的，如果在高水位线之后没有更多的活动元组，则可以通过VACUUM将后续的页面刷新到磁盘上。在第一种情况下，在第3页之后没有活动元组是可以理解的。因此，第4、5和6页已被刷新到磁盘上。

但是，如果您需要在我们删除emp_id <500的所有记录的情况下回收文件系统的空间，则可以运行VACUUM FULL。VACUUM FULL重建整个表并将空间回收到磁盘。

```sql
percona=# VACUUM FULL scott.employee ;
VACUUM
percona=# VACUUM ANALYZE scott.employee ;
VACUUM
percona=# select relpages, relpages*8192 as total_bytes, pg_relation_size('scott.employee') as relsize 
FROM pg_class 
WHERE relname = 'employee';
 relpages | total_bytes | relsize 
----------+-------------+---------
        3 |       24576 |   24576
(1 row)
```

请注意，VACUUM FULL不是在线操作。这是一个阻塞操作。在VACUUM FULL正在进行时，您无法读取或写入表。我们将在未来的博客文章中讨论如何在线重建表而不会阻塞。



---



PostgreSQL数据库的性能可能会因死亡元祖而受到影响，因为它们会继续占用空间并导致膨胀。我们在上面的内容中介绍了VACUUM和膨胀。不过，现在是时候看看postgres的autovacuum功能了，以及您需要了解的内部结构，以维护高性能的PostgreSQL数据库，这是高要求的应用程序所需要的。

#### 什么是autovacuum？

Autovacuum是启动PostgreSQL时自动启动的后台进程之一。正如您在下面的日志中看到的那样，pid 2862的postmaster进程已经启动了 pid 2868的autovacuum launcher进程。要启动autovacuum，必须将参数autovacuum设置为ON。实际上，除非您100％确定自己正在做什么及其影响，否则不应在生产系统中将其设置为OFF。

```
$ps -eaf | egrep "/post|autovacuum"
postgres  2862     1  0 Jun17 pts/0    00:00:11 /usr/pgsql-10/bin/postgres -D /var/lib/pgsql/10/data
postgres  2868  2862  0 Jun17 ?        00:00:10 postgres: autovacuum launcher process
postgres 15427  4398  0 18:35 pts/1    00:00:00 grep -E --color=auto /post|autovacuum
```

#### 为什么需要autovacuum？

我们需要VACUUM来删除死亡元祖，这样死亡元组所占用的空间就可以被表重新使用，用于将来的插入/更新。要了解有关死亡元祖和膨胀的更多信息，请阅读见面的内容。我们还需要在更新表统计信息的表上使用ANALYZE，以便优化器可以为SQL语句选择最佳执行计划。postgres中的autovacuum负责在表上执行vacuum和analyze。

postgres中存在另一个后台进程，名为Stats Collector，用于跟踪使用情况和活动信息。autovacuum launcher进程使用此进程收集的信息来标识autovacuum的候选表列表。PostgreSQL仅在启用autovacuum时自动识别需要vacuum或analyze的表。这可以确保postgres自我修复并阻止数据库产生更多的膨胀/碎片。

在PostgreSQL中启用autovacuum所需的参数是：

```
autovacuum = on  # ( ON by default )
track_counts = on # ( ON by default )
```

track_counts由stats collector使用。如果没有这个，autovacuum无法访问候选表。

#### autovacuum 日志

最后，您可能希望记录autovacuum花费更多时间的表。在这种情况下，将设置参数 `log_autovacuum_min_duration` （默认为毫秒），以便运行超过此值的任何autovacuum都会记录到PostgreSQL日志文件中。这可能有助于适当调整表级autovacuum设置。

```shell
# Setting this parameter to 0 logs every autovacuum to the log file.
log_autovacuum_min_duration = '250ms' # Or 1s, 1min, 1h, 1d
```

这是autovacuum的vacuum和analyze的示例日志

```shell
< 2018-08-06 07:22:35.040 EDT > LOG: automatic vacuum of table "vactest.scott.employee": index scans: 0
pages: 0 removed, 1190 remain, 0 skipped due to pins, 0 skipped frozen
tuples: 110008 removed, 110008 remain, 0 are dead but not yet removable
buffer usage: 2402 hits, 2 misses, 0 dirtied
avg read rate: 0.057 MB/s, avg write rate: 0.000 MB/s
system usage: CPU 0.00s/0.02u sec elapsed 0.27 sec
< 2018-08-06 07:22:35.199 EDT > LOG: automatic analyze of table "vactest.scott.employee" system usage: CPU 0.00s/0.02u sec elapsed 0.15 sec
```

#### PostgreSQL什么时候在表上运行autovacuum？

如前所述，postgres中的autovacuum指的是自动VACUUM和ANALYZE，而不仅仅是VACUUM。根据以下数学方程，自动vacuum或analyze在表上运行。

计算表级autovacuum阈值的公式为：

```shell
Autovacuum VACUUM thresold for a table = autovacuum_vacuum_scale_factor * number of tuples + autovacuum_vacuum_threshold
```

通过上面的等式，很明显，如果表中的实际死亡元祖数超过该有效阈值，由于更新和删除，该表将成为autovacuum vacuum的候选者。

```shell
Autovacuum ANALYZE threshold for a table = autovacuum_analyze_scale_factor * number of tuples + autovacuum_analyze_threshold
```

上面的等式表明，自上次analyze以来，任何插入/删除/更新总数超过此阈值的表都有资格进行autovacuum analyze。

让我们详细了解这些参数。

- `autovacuum_vacuum_scale_factor` 或 `autovacuum_analyze_scale_factor`：将添加到公式中的表记录的比例系数。例如，值0.2等于表记录的20％。
- `autovacuum_vacuum_threshold` 或 `autovacuum_analyze_threshold`：触发autovacuum所需的过时记录或DML的最少数量。

让我们考虑一个表：percona.employee，包含1000条记录和以下autovacuum参数。

```shell
autovacuum_vacuum_scale_factor = 0.2
autovacuum_vacuum_threshold = 50
autovacuum_analyze_scale_factor = 0.1
autovacuum_analyze_threshold = 50
```

使用上述数学公式作为参考，

```shell
Table : percona.employee becomes a candidate for autovacuum Vacuum when,
Total number of Obsolete records = (0.2 * 1000) + 50 = 250
```

```shell
Table : percona.employee becomes a candidate for autovacuum ANALYZE when,
Total number of Inserts/Deletes/Updates = (0.1 * 1000) + 50 = 150
```

#### 调整PostgreSQL中的Autovacuum

我们需要了解这些是全局设置。这些设置适用于实例中的所有数据库。这意味着，无论表大小如何，如果达到上述公式，表都有资格进行autovacuum vacuum或analyze。

#### 这是一个问题吗？

考虑一个包含十条记录的表与一个包含一百万条记录的表。尽管具有一百万条记录的表可能更频繁地涉及事务，但vacuum或analyze自动运行的频率对于仅有十条记录的表可能更高。

因此，PostgreSQL允许您配置表级autovacuum设置。

```shell
ALTER TABLE scott.employee SET (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 100);
```

```sql
Output Log
----------
$psql -d percona
psql (10.4)
Type "help" for help.
percona=# ALTER TABLE scott.employee SET (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 100);
ALTER TABLE
```

只有超过100个过时记录时，上述设置才会在表scott.employee上运行autovacuum vacuum。

#### 我们如何识别需要调整autovacuum设置的表？

为了单独调整表的autovacuum，您必须知道一个表上的插入/删除/更新的数量。您还可以查看postgres系统视图：pg_stat_user_tables以获取该信息。

```sql
percona=# SELECT n_tup_ins as "inserts",n_tup_upd as "updates",n_tup_del as "deletes", n_live_tup as "live_tuples", n_dead_tup as "dead_tuples"
FROM pg_stat_user_tables
WHERE schemaname = 'scott' and relname = 'employee';
 inserts | updates | deletes | live_tuples | dead_tuples
---------+---------+---------+-------------+-------------
      30 |      40 |       9 |          21 |          39
(1 row)
```

如上面的日志所示，在一定时间间隔内拍摄此数据的快照可以帮助您了解每个表上DML的频率。反过来，这可以帮助您调整各个表的autovacuum设置。

#### 一次可以运行多少个autovacuum进程？

在可能包含多个数据库的实例/集群中，一次运行的autovacuum进程数不能超过 `autovacuum_max_workers` 数。Autovacuum launcher后台进程为需要vacuum或analyze的表启动autovacuum worker进程。如果有四个数据库，其中autovacuum_max_workers设置为3，则第四个数据库必须等待，直到其中一个现有worker进程空闲。

在开始下一次autovacuum之前，它等待 `autovacuum_naptime`，大多数版本的默认值为1分钟。如果您有三个数据库，则下一个autovacuum等待60/3秒。因此，启动下一个autovacuum之前的等待时间始终是（autovacuum_naptime/N），其中N是实例中数据库的总数。

#### 调大autovacuum_max_workers是否会增加可并行运行的autovacuum进程数？

没有。接下来的几行更好地解释了这一点。

#### VACUUM IO密集吗？

Autovacuum可视为清理。如前所述，每个表有1个worker进程。Autovacuum从磁盘读取一个表页面（默认block_size = 8KB），并修改/写入包含死亡元祖的页面。这涉及读写IO。因此，这可能是IO密集型操作，当在峰值事务时间内在具有许多死亡元祖的巨大表上运行autovacuum时。为避免此问题，我们设置了一些参数，以最大限度地减少因vacuum造成的对IO的影响。

以下是用于调整autovacuum IO的参数

- autovacuum_vacuum_cost_limit：autovacuum可达到的总成本限制（结合所有autovacuum任务）。
- autovacuum_vacuum_cost_delay：当清理达到autovacuum_vacuum_cost_limit成本时，autovacuum将休眠多少毫秒。
- vacuum_cost_page_hit：读取已在共享缓冲区中且不需要磁盘读取的页面的成本。
- vacuum_cost_page_miss：获取不在共享缓冲区中的页面的成本。
- vacuum_cost_page_dirty：当在每一页中发现死亡元组时写入该页的成本。

```sql
Default Values for the parameters discussed above.
------------------------------------------------------
autovacuum_vacuum_cost_limit = -1 (So, it defaults to vacuum_cost_limit) = 200
autovacuum_vacuum_cost_delay = 20ms
vacuum_cost_page_hit = 1
vacuum_cost_page_miss = 10
vacuum_cost_page_dirty = 20
```

考虑在percona.employee表上运行的autovacuum VACUUM。

让我们想象一下1秒内会发生什么。（1秒 = 1000毫秒）

在读取延迟为0毫秒的最佳情况下，autovacuum可以唤醒并进入睡眠50次（1000毫秒/20毫秒），因为唤醒之间的延迟需要为20毫秒。

```shell
1 second = 1000 milliseconds = 50 * autovacuum_vacuum_cost_delay
```

由于每个读取shared_buffers页面的相关成本为1，因此每次唤醒都可以读取200页，并且在50次唤醒中可以读取50*200页。

如果在共享缓冲区中找到所有具有死亡元祖的页面，并且autovacuum_vacuum_cost_delay为20ms，那么它可以读取：（（200/vacuum_cost_page_hit）* 8）KB，每轮需要等待forautovacuum_vacuum_cost_delayamount时间。

因此，考虑到block_size为8192字节，autovacuum最多可以读取：50 * 200 * 8 KB = 78.13 MB/秒（如果已在shared_buffers中找到块）。

如果块不在共享缓冲区中并且需要从磁盘中获取，则autovacuum可以读取：50 * ((200 / vacuum_cost_page_miss) * 8) KB = 7.81 MB/s。

我们上面看到的所有信息都是针对读IO的。

现在，为了从页面/块中删除死亡元祖，写操作的成本为：vacuum_cost_page_dirty，默认设置为20。

autovacuum最多可以写/脏：50 * ((200 / vacuum_cost_page_dirty) * 8) KB = 3.9 MB/秒。

通常，此成本等于实例中运行的所有 `autovacuum_max_workers` 自动清理进程数。因此，增加 `autovacuum_max_workers` 可能会延迟当前运行的autovacuum worker的autovacuum执行。增加 `autovacuum_vacuum_cost_limit` 可能会导致IO瓶颈。需要注意的重要一点是，可以通过设置表级的参数来重写此行为，这将忽略全局设置。

```sql
postgres=# alter table percona.employee set (autovacuum_vacuum_cost_limit = 500);
ALTER TABLE
postgres=# alter table percona.employee set (autovacuum_vacuum_cost_delay = 10);
ALTER TABLE
postgres=#
postgres=# \d+ percona.employee
Table "percona.employee"
Column | Type | Collation | Nullable | Default | Storage | Stats target | Description
--------+---------+-----------+----------+---------+---------+--------------+-------------
id | integer | | | | plain | |
Options: autovacuum_vacuum_threshold=10000, autovacuum_vacuum_cost_limit=500, autovacuum_vacuum_cost_delay=10
```

因此，在繁忙的OLTP数据库中，始终有策略在低峰值窗口期间对经常使用DML命中的表实施手动VACUUM。在设置相关的autovacuum_ *设置后手动运行时，可能会有尽可能多的并行vacuum任务。因此，始终建议使用预定的手动vacuum任务以及精细调整的autovacuum设置。

#### 参考

https://www.percona.com/blog/2018/08/06/basic-understanding-bloat-vacuum-postgresql-mvcc/

https://www.percona.com/blog/2018/08/10/tuning-autovacuum-in-postgresql-and-autovacuum-internals/

