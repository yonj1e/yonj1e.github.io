---
title: autovacuum和参数配置
date: 2018-08-10 
categories: 
  - [PostgreSQL - Usage]
tags: 
  - AutoVacuum
  - PostgreSQL
---



PostgreSQL的MVCC的实现，确保数据库的事务只返回快照中已提交的数据，即使其他进程正在试图修改该数据。想象一下，一个数据库在一个表中包含数以百万计的元组(通常称为“行”)。如果表中有许多索引，并且有频繁的读/写操作，那么这可能会导致大量的膨胀，最终导致性能问题。防止膨胀的一个关键过程是autovacuum。  

vacuum用于清理表中的死亡元组，以便它们可以被重用。它还可以避免事务ID环绕，并更新统计信息和改进查询优化。 

**VACUUM:**

- 这是一个手动命令。
- Vacuum将从表和索引中删除死亡元组 - 它不会将磁盘空间返回给操作系统，但新行可以重新利用。
- 不要在事务中运行，因为它将占用系统上更高的CPU和I/O使用率。
- 你可能在事务较少的情况下每天/每周运行一次，在这种情况下，可能会积累更多的死亡元组。

**VACUUM FULL:**

- VACUUM FULL会回收空间并将其返回给操作系统。
- 最初它获取表上的独占锁，阻塞所有操作（包括SELECT）。
- 然后它创建表的副本，这使所需的磁盘空间加倍，因此在磁盘空间不足时不太实用。

**AUTOVACUUM:**

- Autovacuum在繁忙时段将更频繁地执行，而在数据库清闲时则更少。
- 不应该消耗太多资源（CPU和磁盘I/O）。
- 默认情况下，当死亡元组达到表的20％时，autovacuum触发。
- 默认情况下，当死亡元祖达到表的10％时，autovacuum不仅会清除死亡元组并且更新统计信息到优化器（用于新的查询规划）。

从上面不同可以了解autovacuum的重要性。

我们的postgresql.conf中有4个参数设置为默认值：

```shell
autovacuum_vacuum_scale_factor = 0.2;
autovacuum_analyze_scale_factor = 0.1;
autovacuum_vacuum_threshold (integer)50
autovacuum_analyze_threshold (integer)50
```

对于我们的数据库正在处理的事务数，默认值太小了。例如，此数据库中的K1表不会自动清理最近几天更新或删除的元组。 

```sql
select n_dead_tup ,last_vacuum,last_analyze,n_tup_upd, n_tup_del,n_tup_hot_upd,relname ,seq_scan,idx_scan  from pg_stat_all_tables where relname='k1';
 n_dead_tup | last_vacuum | last_analyze | n_tup_upd | n_tup_del | n_tup_hot_upd | relname | seq_scan | idx_scan
------------+-------------+--------------+-----------+-----------+---------------+---------+----------+----------
       200  |             |              |    200    |      0    |             0 | k1      |       17 |        
(1 row) 
```

```sql
SELECT reltuples::numeric FROM pg_class WHERE relname = 'k1';
 reltuples
-----------
  10,000
```

下面的公式用到上面的数据：

```shell
autovacuum_vacuum_threshold + pg_class.reltuples * scale_factor
autovacuum_analyze_threshold + pg_class.reltuples * scale_factor
```

当死亡元组达到2050时，PostgreSQL会触发vacuum，现在我们只有200个

         50 + 10000 * 0.2 = 2050

当死亡元组达到1050时，PostgreSQL会触发analyze

         50 + 10000 * 0.1 = 1050

我们有一个10,000行的表，其中200个已更改：

- autovacuum_analyze_threshold告诉我们，我们超过默认值50;
- 我们根据autovacuum_analyze_scale_factor（默认为0.1）计算阙值，这里是1000行;
- 因此总计算阈值为1050;
- 当200小于1050时，ANALYZE未触发。

对于VACCUM，还有另一对相似的参数：autovacuum_vacuum_threshold和autovacuum_vacuum_scale_factor，但vacuum的默认值为0.2。

### Autovacuum参数选项：

#### 选项1：vacuum默认为0.2，analyze默认为0.1

```
autovacuum_vacuum_scale_factor = 0.2
autovacuum_analyze_scale_factor = 0.1
```

该表将被视为需要清理。 该公式基本上表示在清理之前，高达20％的表可能是死亡元组（50行的阈值是为了防止非常频繁地清理微小的表）。

默认的比例因子适用于中小型表，而不是非常大的表- 在20GB表上，死亡元组达到vacuum触发条件大约是4GB，analyze是2GB，而10TB表达到vacuum触发条件需要达到2TB，analyze达到1TB。

这是一个累积大量死亡元组，同时即处理所有这些元组的例子。 根据前面提到的规则，解决方案是通过显著降低比例因子来更频繁地清理做到这一点，甚至可能是这样的：

#### 选项2：vacuum 0.01，analyze 0.01

```shell
 autovacuum_vacuum_scale_factor = 0.01
 autovacuum_analyze_scale_factor = 0.01
```

在10TB的大表：

PostgreSQL会触发vacuum并analyze，当死亡元祖达到1％也就是100GB

在2TB中等表：

PostgreSQL会触发vacuum并analyze，当死亡元祖达到1％也就是20GB

在10GB小表：

PostgreSQL会触发vacuum并analyze，当死亡元祖达到1％也就是100MB

这适用于小表，而不是TB级别的。

这将限制减少到仅占表的1％。 

另一种解决方案是完全放弃比例因子，仅使用阈值。

#### 选项3：基于阈值

```shell
 autovacuum_vacuum_scale_factor = 0
 autovacuum_analyze_scale_factor = 0
 autovacuum_vacuum_threshold = 15000
 autovacuum_analyze_threshold =10000 
```

在死亡元组达到15000个后触发vacuum，死亡元组达到10000触发analyze。

一个问题是postgresql.conf中的这些更改会影响所有表（实际上是整个集群），并且它可能会不利地影响小表的清理，包括系统目录。

当更频繁地清理小表时，最简单的解决方案是完全忽略问题。清理小表不会有太多消耗，反而大表的改进通常非常重要，即使你忽略了小表上的低效率，整体效果仍然是非常积极的。

但是，如果您决定以显著延迟小表清理的方式更改配置（例如设置scale_factor = 0和threshold = 4000），则最好使用ALTER TABLE将这些更改仅应用于特定表：

```sql
ALTER TABLE small_table SET (autovacuum_vacuum_scale_factor = 0);
ALTER TABLE small_table SET (autovacuum_analyze_scale_factor = 0);
ALTER TABLE small_table SET (autovacuum_vacuum_threshold = 5000);
ALTER TABLE small_table SET (autovacuum_analyze_threshold = 2500);
```

尽量使配置保持简单，并且覆盖尽可能少的表的参数。