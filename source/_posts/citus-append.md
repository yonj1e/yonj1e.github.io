---
title: Citus中的分片策略:追加分配
date: 2019-02-14
categories: 
  - [PostgreSQL]
tags: 
  - Citus
  - PostgreSQL
  - Sharding
---



[原文](https://blog.csdn.net/fm0517/article/details/79611271)

[官方文档](https://docs.citusdata.com/en/v7.2/reference/append.html)



Append distribution is a specialized technique which requires care to use efficiently. Hash distribution is a better choice for most situations. 
追加分配是需要谨慎使用的专门技术。散列分布是大多数情况下更好的选择。

While Citus’ most common use cases involve hash data distribution, it can also distribute timeseries data across a variable number of shards by their order in time. This section provides a short reference to loading, deleting, and maninpulating timeseries data. 
虽然Citus最常见的用例涉及散列数据分布，但它也可以按时间顺序在可变数量的碎片上分布时间序列数据。 本节提供加载，删除和操作时间序列数据的简短参考。

As the name suggests, append based distribution is more suited to append-only use cases. This typically includes event based data which arrives in a time-ordered series. You can then distribute your largest tables by time, and batch load your events into Citus in intervals of N minutes. This data model can be generalized to a number of time series use cases; for example, each line in a website’s log file, machine activity logs or aggregated website events. Append based distribution supports more efficient range queries. This is because given a range query on the distribution key, the Citus query planner can easily determine which shards overlap that range and send the query to only to relevant shards. 
[顾名思义](https://www.baidu.com/s?wd=%E9%A1%BE%E5%90%8D%E6%80%9D%E4%B9%89&tn=24004469_oem_dg&rsv_dl=gh_pl_sl_csd)，基于append的分发更适合于追加用例。 这通常包括以时间排序的系列到达的基于事件的数据。 然后，您可以按时间分配最大的表格，并以N分钟的时间间隔将您的活动批量加载到Citus中。 这个数据模型可以推广到许多时间序列用例;例如网站日志文件中的每一行，机器活动日志或聚合的网站事件。 追加基于分布支持更有效的范围查询。这是因为通过对分发密钥进行范围查询，Citus查询计划人员可以轻松确定哪些分片与该范围重叠，并将查询仅发送给相关的分片。

Hash based distribution is more suited to cases where you want to do real-time inserts along with analytics on your data or want to distribute by a non-ordered column (eg. user id). This data model is relevant for real-time analytics use cases; for example, actions in a mobile application, user website events, or social media analytics. In this case, Citus will maintain minimum and maximum hash ranges for all the created shards. Whenever a row is inserted, updated or deleted, Citus will redirect the query to the correct shard and issue it locally. This data model is more suited for doing co-located joins and for queries involving equality based filters on the distribution column. 
基于散列的分布更适合于您想要对数据进行实时插入以及对数据进行分析的情况，或者希望通过无序列（例如，用户标识）进行分发的情况。 该数据模型与实时分析用例相关; 例如，移动应用程序中的操作，用户网站事件或社交媒体分析。 在这种情况下，Citus将为所有创建的碎片维护最小和最大散列范围。 无论何时插入，更新或删除行，Citus都会将查询重定向到正确的分片并在本地发布。 此数据模型更适合于执行共址连接以及在分布列上使用基于等式的过滤器的查询。

Citus uses slightly different syntaxes for creation and manipulation of append and hash distributed tables. Also, the operations supported on the tables differ based on the distribution method chosen. In the sections that follow, we describe the syntax for creating append distributed tables, and also describe the operations which can be done on them. 
Citus使用稍微不同的语法来创建和操作append和hash分布表。 此外，表支持的操作因所选分配方法而异。 在接下来的部分中，我们描述创建附加分布表的语法，并描述可以在其上执行的操作。

## Creating and Distributing Tables创建和分配表格

The instructions below assume that the PostgreSQL installation is in your path. If not, you will need to add it to your PATH environment variable. For example: 
以下说明假定PostgreSQL安装位于您的路径中。 如果没有，您需要将其添加到PATH环境变量中。 例如：

```shell
export PATH=/usr/lib/postgresql/9.6/:$PATH1
```

We use the github events dataset to illustrate the commands below. You can download that dataset by running: 
我们使用github事件数据集来说明下面的命令。 您可以通过运行下载该数据集：

```shell
wget http://examples.citusdata.com/github_archive/github_events-2015-01-01-{0..5}.csv.gz
gzip -d github_events-2015-01-01-*.gz12
```

To create an append distributed table, you need to first define the table schema. To do so, you can define a table using the CREATE TABLE statement in the same way as you would do with a regular PostgreSQL table. 
要创建追加分布表，您需要先定义表格模式。 为此，您可以像使用常规PostgreSQL表一样使用CREATE TABLE语句定义表。

```sql
psql -h localhost -d postgres
CREATE TABLE github_events
(
    event_id bigint,
    event_type text,
    event_public boolean,
    repo_id bigint,
    payload jsonb,
    repo jsonb,
    actor jsonb,
    org jsonb,
    created_at timestamp
);12345678910111213
```

Next, you can use the create_distributed_table() function to mark the table as an append distributed table and specify its distribution column. 
接下来，您可以使用create_distributed_table（）函数将该表标记为追加分布表并指定其分布列。

```sql
SELECT create_distributed_table('github_events', 'created_at', 'append');1
```

This function informs Citus that the github_events table should be distributed by append on the created_at column. Note that this method doesn’t enforce a particular distribution; it merely tells the database to keep minimum and maximum values for the created_at column in each shard which are later used by the database for optimizing queries. 
该函数通知Citus github_events表应该通过追加在created_at列上进行分配。 请注意，此方法不强制执行特定的分配; 它只是告诉数据库为每个分片中的created_at列保留最小值和最大值，稍后由数据库用于优化查询。

## Expiring Data到期数据

In append distribution, users typically want to track data only for the last few months / years. In such cases, the shards that are no longer needed still occupy disk space. To address this, Citus provides a user defined function master_apply_delete_command() to delete old shards. The function takes a DELETE command as input and deletes all the shards that match the delete criteria with their metadata. 
在附加分发中，用户通常只想跟踪过去几个月/年的数据。 在这种情况下，不再需要的碎片仍占用磁盘空间。为了解决这个问题，Citus提供了一个用户定义的函数master_apply_delete_command（）来删除旧的分片。 该函数将DELETE命令作为输入，并删除与删除条件及其元数据匹配的所有碎片。

The function uses shard metadata to decide whether or not a shard needs to be deleted, so it requires the WHERE clause in the DELETE statement to be on the distribution column. If no condition is specified, then all shards are selected for deletion. The UDF then connects to the worker nodes and issues DROP commands for all the shards which need to be deleted. If a drop query for a particular shard replica fails, then that replica is marked as TO DELETE. The shard replicas which are marked as TO DELETE are not considered for future queries and can be cleaned up later. 
该函数使用分片元数据来决定是否需要删除分片，因此它要求DELETE语句中的WHERE子句位于分布列上。 如果没有指定条件，则选择所有分片进行删除。 然后，UDF连接到工作节点，并为需要删除的所有分片发出DROP命令。 如果特定分片副本的删除查询失败，则该副本被标记为“删除”。 标记为TO DELETE的分片副本不会被考虑用于将来的查询，并且可以稍后进行清理。

The example below deletes those shards from the github_events table which have all rows with created_at >= ‘2015-01-01 00:00:00’. Note that the table is distributed on the created_at column. 
下面的示例从github_events表中删除那些包含created_at> =’2015-01-01 00:00:00’的所有行的碎片。 请注意，该表分布在created_at列中。

```sql
SELECT * from master_apply_delete_command('DELETE FROM github_events WHERE created_at >= ''2015-01-01 00:00:00''');
 master_apply_delete_command
-----------------------------
                           3
(1 row)12345
```

To learn more about the function, its arguments and its usage, please visit the Citus Utility Function Reference section of our documentation. Please note that this function only deletes complete shards and not individual rows from shards. If your use case requires deletion of individual rows in real-time, see the section below about deleting data. 
要了解更多关于功能，参数和用法的信息，请访问我们文档中的Citus Utility函数参考部分。 请注意，此功能只会删除完整的碎片，而不会从碎片中删除单独的行。 如果您的用例需要实时删除单个行，请参阅以下有关删除数据的部分。

## Deleting Data删除数据

The most flexible way to modify or delete rows throughout a Citus cluster with regular SQL statements: 
使用常规SQL语句修改或删除整个Citus集群中行的最灵活的方法： 
DELETE FROM github_events WHERE created_at >= ‘2015-01-01 00:03:00’;

Unlike master_apply_delete_command, standard SQL works at the row- rather than shard-level to modify or delete all rows that match the condition in the where clause. It deletes rows regardless of whether they comprise an entire shard. 
与master_apply_delete_command不同，标准SQL在行而不是分片级上修改或删除与where子句中的条件匹配的所有行。 它会删除行，而不管它们是否包含整个分片。

## Dropping Tables删除表

You can use the standard PostgreSQL DROP TABLE command to remove your append distributed tables. As with regular tables, DROP TABLE removes any indexes, rules, triggers, and constraints that exist for the target table. In addition, it also drops the shards on the worker nodes and cleans up their metadata. 
您可以使用标准的PostgreSQL DROP TABLE命令删除附加的分布式表。 与常规表一样，DROP TABLE删除目标表存在的所有索引，规则，触发器和约束。 此外，它还会删除工作节点上的碎片并清理其元数据。 
DROP TABLE github_events;

## Data Loading数据加载

Citus supports two methods to load data into your append distributed tables. The first one is suitable for bulk loads from files and involves using the \copy command. For use cases requiring smaller, incremental data loads, Citus provides two user defined functions. We describe each of the methods and their usage below. 
Citus支持两种将数据加载到附加分布表的方法。 第一个适用于文件的批量加载，并涉及使用\copy命令。 对于需要更小的增量数据加载的用例，Citus提供了两个用户定义的函数。 我们在下面描述每种方法及其用法。

#### Bulk load using \copy使用\copy批量加载

The \copy command is used to copy data from a file to a distributed table while handling replication and failures automatically. You can also use the server side COPY command. In the examples, we use the \copy command from psql, which sends a COPY .. FROM STDIN to the server and reads files on the client side, whereas COPY from a file would read the file on the server. 
\copy命令用于将数据从文件复制到分布式表中，同时自动处理复制和失败。 你也可以使用[服务器](https://www.baidu.com/s?wd=%E6%9C%8D%E5%8A%A1%E5%99%A8&tn=24004469_oem_dg&rsv_dl=gh_pl_sl_csd)端的COPY命令。 在这些示例中，我们使用psql的\copy命令，该命令将COPY .. FROM STDIN发送到服务器，并在客户端读取文件，而来自文件的COPY会读取服务器上的文件。

You can use \copy both on the coordinator and from any of the workers. When using it from the worker, you need to add the master_host option. Behind the scenes, \copy first opens a connection to the coordinator using the provided master_host option and uses master_create_empty_shard to create a new shard. Then, the command connects to the workers and copies data into the replicas until the size reaches shard_max_size, at which point another new shard is created. Finally, the command fetches statistics for the shards and updates the metadata. 
您可以在协调节点和任何工作节点上使用\copy。从工作节点中使用它时，需要添加master_host选项。在幕后，\copy首先使用提供的master_host选项打开到协调节点的连接，并使用master_create_empty_shard创建新的分片。 然后，该命令连接到工作节点并将数据复制到副本中，直到大小达到shard_max_size，此时会创建另一个新的碎片。 最后，该命令获取分片的统计信息并更新元数据。

```sql
SET citus.shard_max_size TO '64MB';
\copy github_events from 'github_events-2015-01-01-0.csv' WITH (format CSV, master_host 'coordinator-host')12
```

Citus assigns a unique shard id to each new shard and all its replicas have the same shard id. Each shard is represented on the worker node as a regular PostgreSQL table with name ‘tablename_shardid’ where tablename is the name of the distributed table and shardid is the unique id assigned to that shard. One can connect to the worker postgres instances to view or run commands on individual shards. 
Citus为每个新分片分配一个唯一的分片ID，并且其所有副本具有相同的分片ID。 每个分片在工作节点上表示为名为’tablename_shardid’的普通PostgreSQL表，其中tablename是分布式表的名称，shardid是分配给该分片的唯一标识。 可以连接到worker postgres实例来查看或运行单个分片上的命令。

By default, the \copy command depends on two configuration parameters for its behavior. These are called citus.shard_max_size and citus.shard_replication_factor. 
默认情况下，\copy命令依赖于其行为的两个配置参数。 这些被称为citus.shard_max_size和citus.shard_replication_factor。

```sql
1.  citus.shard_max_size :- This parameter determines the maximum size of a shard created using \copy, and defaults to 1 GB. If the file is larger than this parameter, \copy will break it up into multiple shards.
1.  citus.shard_max_size： - 此参数确定使用\copy创建的分片的最大大小，默认值为1 GB。 如果文件大于此参数，\copy会将其分解为多个分片。

2.  citus.shard_replication_factor :- This parameter determines the number of nodes each shard gets replicated to, and defaults to one. Set it to two if you want Citus to replicate data automatically and provide fault tolerance. You may want to increase the factor even higher if you run large clusters and observe node failures on a more frequent basis.
2.  citus.shard_replication_factor： - 此参数确定每个分片被复制到的节点数量，默认值为1。 如果希望Citus自动复制数据并提供容错功能，请将其设置为2。 如果运行大型群集并更频繁地观察节点故障，则可能需要将系数提高得更高。
12345
```

The configuration setting citus.shard_replication_factor can only be set on the coordinator node. 
配置设置citus.shard_replication_factor只能在协调节点上设置。

Please note that you can load several files in parallel through separate database connections or from different nodes. It is also worth noting that \copy always creates at least one shard and does not append to existing shards. You can use the method described below to append to previously created shards. 
请注意，您可以通过单独的数据库连接或从不同的节点并行加载多个文件。 还值得注意的是，\copy总是创建至少一个分片，并且不会附加到现有的分片上。 您可以使用下面描述的方法追加到以前创建的分片。

There is no notion of snapshot isolation across shards, which means that a multi-shard SELECT that runs concurrently with a COPY might see it committed on some shards, but not on others. If the user is storing events data, he may occasionally observe small gaps in recent data. It is up to applications to deal with this if it is a problem (e.g. exclude the most recent data from queries, or use some lock). 
在分片之间没有快照隔离的概念，这意味着与COPY同时运行的多分片SELECT可能会在某些分片上看到它提交，但在其他分片上没有。 如果用户正在存储事件数据，他可能偶尔会观察到最近数据中的小差距。 如果应用程序出现问题（例如排除查询中的最新数据或使用某些锁定），则由应用程序处理。

If COPY fails to open a connection for a shard placement then it behaves in the same way as INSERT, namely to mark the placement(s) as inactive unless there are no more active placements. If any other failure occurs after connecting, the transaction is rolled back and thus no metadata changes are made. 
如果COPY无法为分片展示位置打开连接，那么它的行为方式与INSERT相同，即将展示位置标记为非活动状态，除非没有更多的活动展示位置。 如果连接后发生任何其他故障，事务将回滚，因此不会进行元数据更改。

#### Incremental loads by appending to existing shards通过附加到现有碎片增量加载

The \copy command always creates a new shard when it is used and is best suited for bulk loading of data. Using \copy to load smaller data increments will result in many small shards which might not be ideal. In order to allow smaller, incremental loads into append distributed tables, Citus provides 2 user defined functions. They are master_create_empty_shard() and master_append_table_to_shard(). 
\copy命令在使用时总是创建一个新的分片，并且最适合批量加载数据。 使用\copy加载较小的数据增量会导致许多小碎片，这可能并不理想。 为了允许更小的增量加载到追加分布表中，Citus提供了2个用户定义的函数。 它们是master_create_empty_shard（）和master_append_table_to_shard（）。

master_create_empty_shard() can be used to create new empty shards for a table. This function also replicates the empty shard to citus.shard_replication_factor number of nodes like the \copy command. 
master_create_empty_shard（）可用于为表创建新的空分片。 该函数还将空分片复制到citus.shard_replication_factor节点的数目，如\copy命令。

master_append_table_to_shard() can be used to append the contents of a PostgreSQL table to an existing shard. This allows the user to control the shard to which the rows will be appended. It also returns the shard fill ratio which helps to make a decision on whether more data should be appended to this shard or if a new shard should be created. 
master_append_table_to_shard（）可用于将PostgreSQL表的内容附加到现有分片。 这允许用户控制行将被附加到的碎片。 它还返回碎片填充比率，这有助于决定是否应将更多数据附加到此碎片或者是否应创建新的碎片。

To use the above functionality, you can first insert incoming data into a regular PostgreSQL table. You can then create an empty shard using master_create_empty_shard(). Then, using master_append_table_to_shard(), you can append the contents of the staging table to the specified shard, and then subsequently delete the data from the staging table. Once the shard fill ratio returned by the append function becomes close to 1, you can create a new shard and start appending to the new one. 
要使用上述功能，您可以首先将传入数据插入常规PostgreSQL表中。 然后可以使用master_create_empty_shard（）创建一个空的分片。 然后，使用master_append_table_to_shard（），可以将临时表的内容附加到指定的分片，然后从临时表中删除数据。 一旦附加函数返回的分片填充率接近1，您可以创建一个新的分片并开始追加到新的分片。

```sql
SELECT * from master_create_empty_shard('github_events');
master_create_empty_shard
---------------------------
                102089
(1 row)

SELECT * from master_append_table_to_shard(102089, 'github_events_temp', 'master-101', 5432);
master_append_table_to_shard
------------------------------
        0.100548
(1 row)1234567891011
```

To learn more about the two UDFs, their arguments and usage, please visit the Citus Utility Function Reference section of the documentation. 
要详细了解这两个UDF，它们的论点和用法，请访问文档中的Citus Utility Function Reference部分。

#### Increasing data loading performance提高数据加载性能

The methods described above enable you to achieve high bulk load rates which are sufficient for most use cases. If you require even higher data load rates, you can use the functions described above in several ways and write scripts to better control sharding and data loading. The next section explains how to go even faster. 
上述方法使您可以实现大批量加载速率，这对大多数使用情况都是足够的。 如果您需要更高的数据加载速率，则可以通过多种方式使用上述功能，并编写脚本以更好地控制分片和数据加载。 下一节将介绍如何更快地进行。

## Scaling Data Ingestion缩放数据摄入

If your use-case does not require real-time ingests, then using append distributed tables will give you the highest ingest rates. This approach is more suitable for use-cases which use time-series data and where the database can be a few minutes or more behind. 
如果你的用例不需要实时摄取，那么使用append分布表将会给你最高的摄取率。 这种方法更适用于使用时间序列数据的用例，并且数据库可能滞后几分钟或更长时间。

#### Coordinator Node Bulk Ingestion (100k/s-200k/s) 协调节点批量摄取

To ingest data into an append distributed table, you can use the COPY command, which will create a new shard out of the data you ingest. COPY can break up files larger than the configured citus.shard_max_size into multiple shards. COPY for append distributed tables only opens connections for the new shards, which means it behaves a bit differently than COPY for hash distributed tables, which may open connections for all shards. A COPY for append distributed tables command does not ingest rows in parallel over many connections, but it is safe to run many commands in parallel. 
要将数据提取到追加分布表中，可以使用COPY命令，该命令将从您提取的数据中创建一个新的碎片。 COPY可以将大于配置的citus.shard_max_size的文件分解为多个分片。 用于追加分布表的COPY只会打开新分片的连接，这意味着它与散列分布表的COPY行为有点不同，这可能会打开所有分片的连接。 追加分布表命令的COPY不会在许多连接上并行摄取行，但可以并行运行多个命令。

```sql
-- Set up the events table
CREATE TABLE events (time timestamp, data jsonb);
SELECT create_distributed_table('events', 'time', 'append');

-- Add data into a new staging table
\COPY events FROM 'path-to-csv-file' WITH CSV123456
```

COPY creates new shards every time it is used, which allows many files to be ingested simultaneously, but may cause issues if queries end up involving thousands of shards. An alternative way to ingest data is to append it to existing shards using the master_append_table_to_shard function. To use master_append_table_to_shard, the data needs to be loaded into a staging table and some custom logic to select an appropriate shard is required. 
COPY每次使用时都会创建新的碎片，这样可以同时吸收许多文件，但如果查询最终会涉及数千个碎片，则可能会导致问题。 获取数据的另一种方法是使用master_append_table_to_shard函数将其追加到现有碎片。 要使用master_append_table_to_shard，需要将数据加载到临时表中，并且需要一些自定义逻辑来选择适当的分片。

```sql
-- Prepare a staging table
CREATE TABLE stage_1 (LIKE events);
\COPY stage_1 FROM 'path-to-csv-file WITH CSV

-- In a separate transaction, append the staging table
SELECT master_append_table_to_shard(select_events_shard(), 'stage_1', 'coordinator-host', 5432);123456
```

An example of a shard selection function is given below. It appends to a shard until its size is greater than 1GB and then creates a new one, which has the drawback of only allowing one append at a time, but the advantage of bounding shard sizes. 
下面给出了一个分片选择函数的例子。 它附加到一个分片，直到它的大小大于1GB，然后创建一个新的分支，其缺点是一次只允许一个附加，但是限制分片大小的优点。

```sql
CREATE OR REPLACE FUNCTION select_events_shard() RETURNS bigint AS $$
DECLARE
  shard_id bigint;
BEGIN
  SELECT shardid INTO shard_id
  FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
  WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024;

  IF shard_id IS NULL THEN
    /* no shard smaller than 1GB, create a new one */
    SELECT master_create_empty_shard('events') INTO shard_id;
  END IF;

  RETURN shard_id;
END;
$$ LANGUAGE plpgsql;12345678910111213141516
```

It may also be useful to create a sequence to generate a unique name for the staging table. This way each ingestion can be handled independently. 
创建序列来为临时表生成唯一名称也可能很有用。 这样每个摄取都可以独立处理。

```sql
-- Create stage table name sequence
CREATE SEQUENCE stage_id_sequence;

-- Generate a stage table name
SELECT 'stage_'||nextval('stage_id_sequence');12345
```

To learn more about the master_append_table_to_shard and master_create_empty_shard UDFs, please visit the Citus Utility Function Reference section of the documentation. 
要了解关于master_append_table_to_shard和master_create_empty_shard UDF的更多信息，请访问文档中的Citus Utility函数参考部分。

#### Worker Node Bulk Ingestion (100k/s-1M/s) 工作节点批量摄取

For very high data ingestion rates, data can be staged via the workers. This method scales out horizontally and provides the highest ingestion rates, but can be more complex to use. Hence, we recommend trying this method only if your data ingestion rates cannot be addressed by the previously described methods. 
对于非常高的数据摄取率，数据可以通过工作节点进行。 该方法水平扩大并提供最高的摄取率，但使用起来可能更复杂。 因此，我们建议仅当您的数据摄取率无法通过前述方法解决时才尝试使用此方法。

Append distributed tables support COPY via the worker, by specifying the address of the coordinator in a master_host option, and optionally a master_port option (defaults to 5432). COPY via the workers has the same general properties as COPY via the coordinator, except the initial parsing is not bottlenecked on the coordinator. 
通过指定master_host选项中协调节点地址以及可选的master_port选项（默认为5432），附加分布式表格支持COPY。 通过工作节点的COPY通过协调节点具有与COPY相同的一般属性，但初始解析不是协调节点的瓶颈。

```sql
psql -h worker-host-n -c "\COPY events FROM 'data.csv' WITH (FORMAT CSV, MASTER_HOST 'coordinator-host')"1
```

An alternative to using COPY is to create a staging table and use standard SQL clients to append it to the distributed table, which is similar to staging data via the coordinator. An example of staging a file via a worker using psql is as follows: 
使用COPY的替代方法是创建登台表并使用标准SQL客户端将其附加到分布式表，这类似于通过协调节点登台数据。 使用psql通过工作节点登录文件的示例如下所示：

```sql
stage_table=$(psql -tA -h worker-host-n -c "SELECT 'stage_'||nextval('stage_id_sequence')")
psql -h worker-host-n -c "CREATE TABLE $stage_table (time timestamp, data jsonb)"
psql -h worker-host-n -c "\COPY $stage_table FROM 'data.csv' WITH CSV"
psql -h coordinator-host -c "SELECT master_append_table_to_shard(choose_underutilized_shard(), '$stage_table', 'worker-host-n', 5432)"
psql -h worker-host-n -c "DROP TABLE $stage_table"12345
```

The example above uses a choose_underutilized_shard function to select the shard to which to append. To ensure parallel data ingestion, this function should balance across many different shards. 
上面的例子使用choose_underutilized_shard函数来选择要附加的分片。 为了确保并行数据摄入，这个函数应该平衡许多不同的分片。

An example choose_underutilized_shard function belows randomly picks one of the 20 smallest shards or creates a new one if there are less than 20 under 1GB. This allows 20 concurrent appends, which allows data ingestion of up to 1 million rows/s (depending on indexes, size, capacity). 
下面的choose_underutilized_shard函数示例将随机选取20个最小碎片中的一个，如果在1GB以下的值小于20，则会创建一个新碎片。 这允许20个并发追加，允许数据摄取高达100万行/秒（取决于索引，大小，容量）。

```sql
/* Choose a shard to which to append */
CREATE OR REPLACE FUNCTION choose_underutilized_shard()
RETURNS bigint LANGUAGE plpgsql
AS $function$
DECLARE
  shard_id bigint;
  num_small_shards int;
BEGIN
  SELECT shardid, count(*) OVER () INTO shard_id, num_small_shards
  FROM pg_dist_shard JOIN pg_dist_placement USING (shardid)
  WHERE logicalrelid = 'events'::regclass AND shardlength < 1024*1024*1024
  GROUP BY shardid ORDER BY RANDOM() ASC;

  IF num_small_shards IS NULL OR num_small_shards < 20 THEN
    SELECT master_create_empty_shard('events') INTO shard_id;
  END IF;

  RETURN shard_id;
END;
$function$;1234567891011121314151617181920
```

A drawback of ingesting into many shards concurrently is that shards may span longer time ranges, which means that queries for a specific time period may involve shards that contain a lot of data outside of that period. 
同时摄入多个碎片的缺点是碎片可能跨越较长的时间范围，这意味着对于特定时间段的查询可能涉及在该时段之外包含大量数据的碎片。

In addition to copying into temporary staging tables, it is also possible to set up tables on the workers which can continuously take INSERTs. In that case, the data has to be periodically moved into a staging table and then appended, but this requires more advanced scripting. 
除了复制到临时登台表之外，还可以在可连续进行INSERT的工作人员上设置表格。 在这种情况下，数据必须定期移动到临时表中，然后追加，但这需要更高级的脚本。

#### Pre-processing Data in Citus预处理数据

The format in which raw data is delivered often differs from the schema used in the database. For example, the raw data may be in the form of log files in which every line is a JSON object, while in the database table it is more efficient to store common values in separate columns. Moreover, a distributed table should always have a distribution column. Fortunately, PostgreSQL is a very powerful data processing tool. You can apply arbitrary pre-processing using SQL before putting the results into a staging table. 
原始数据交付的格式通常与数据库中使用的模式不同。 例如，原始数据可能是日志文件的形式，其中每一行都是JSON对象，而在数据库表中，将常见值存储在单独的列中效率更高。 而且，分布式表格应该总是有一个分布列。 幸运的是，PostgreSQL是一个非常强大的数据处理工具。 在将结果放入登台表之前，可以使用SQL进行任意预处理。

For example, assume we have the following table schema and want to load the compressed JSON logs from githubarchive.org: 
例如，假设我们有下面的表模式，并想从githubarchive.org加载压缩的JSON日志：

```sql
CREATE TABLE github_events
(
    event_id bigint,
    event_type text,
    event_public boolean,
    repo_id bigint,
    payload jsonb,
    repo jsonb,
    actor jsonb,
    org jsonb,
    created_at timestamp
);
SELECT create_distributed_table('github_events', 'created_at', 'append');12345678910111213
```

To load the data, we can download the data, decompress it, filter out unsupported rows, and extract the fields in which we are interested into a staging table using 3 commands: 
要加载数据，我们可以下载数据，解压缩数据，过滤不支持的行，并使用3个命令将我们感兴趣的字段提取到临时表中：

```sql
CREATE TEMPORARY TABLE prepare_1 (data jsonb);

-- Load a file directly from Github archive and filter out rows with unescaped 0-bytes
COPY prepare_1 FROM PROGRAM
'curl -s http://data.githubarchive.org/2016-01-01-15.json.gz | zcat | grep -v "\\u0000"'
CSV QUOTE e'\x01' DELIMITER e'\x02';

-- Prepare a staging table
CREATE TABLE stage_1 AS
SELECT (data->>'id')::bigint event_id,
       (data->>'type') event_type,
       (data->>'public')::boolean event_public,
       (data->'repo'->>'id')::bigint repo_id,
       (data->'payload') payload,
       (data->'actor') actor,
       (data->'org') org,
       (data->>'created_at')::timestamp created_at FROM prepare_1;1234567891011121314151617
```

You can then use the master_append_table_to_shard function to append this staging table to the distributed table. 
然后，您可以使用master_append_table_to_shard函数将该临时表追加到分布式表中。

This approach works especially well when staging data via the workers, since the pre-processing itself can be scaled out by running it on many workers in parallel for different chunks of input data. 
这种方法在通过工作节点分级数据时效果特别好，因为预处理本身可以通过在不同的输入数据块上并行运行许多工作节点来扩展。

For a more complete example, see Interactive Analytics on GitHub Data using PostgreSQL with Citus. 
有关更完整的示例，请参阅使用PostgreSQL和Citus的GitHub数据交互式分析。