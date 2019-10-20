---
title: 基于PostgreSQL10实现hash分区
date: 2017-08-11 
categories: 
  - [PostgreSQL]
tags: 
  - Hash Partition
---

##  简介

基于pg10实现hash分区，下面介绍参照range/list分区实现的hash分区。

注意：由于本人水平限制，难免会有遗漏及错误的地方，不保证正确性，并且是个人见解，发现问题欢迎留言指正。

思路

- 语法尽可能与range/list分区相似，先创建主表，再创建分区。

- inser时对key值进行hash算法对分区数取余，找到要插入的分区。

- 可动态添加分区，当分区中有数据并新创建分区时，数据重新计算并分发。

- select时约束排除使用相同的算法过滤分区。

## 建表语法

```sql
yonj1e=# create table h (h_id int, h_name name, h_date date) partition by hash(h_id);
CREATE TABLE
yonj1e=# create table h1 partition of h;
CREATE TABLE
yonj1e=# create table h2 partition of h;
CREATE TABLE
yonj1e=# create table h3 partition of h;
CREATE TABLE
yonj1e=# create table h4 partition of h;
CREATE TABLE
```
建主表的语法与range/list分区一样，只有类型差别。

子表不需要想range/list分区那样的约束，因此不需要额外的说明，创建后，会将分区key值信息记录到pg_class.relpartbound。

创建主表时做了两个主要修改以识别主表的创建：

```c
/src/include/nodes/parsenodes.h
#define PARTITION_STRATEGY_HASH        'h'

/src/backend/commands/tablecmds.c
   else if (pg_strcasecmp(partspec->strategy, "hash") == 0)
        *strategy = PARTITION_STRATEGY_HASH;
```
创建子表时修改ForValue 为EMPTY时即为创建hash partition：
```c
/src/backend/parser/gram.y
/* a HASH partition */
            |  /*EMPTY*/
                {
                    PartitionBoundSpec *n = makeNode(PartitionBoundSpec);

                    n->strategy = PARTITION_STRATEGY_HASH;
                    //n->hashnumber = 1;
                    //n->location = @3;

                    $$ = n;
                }
```
## 插入数据

insert时，做的修改也是在range/list分区基础上做的修改，增加的代码不多，代码在parition.c文件get_partition_for_tuple()，根据value值计算出目标分区，
```c
cur_index = DatumGetUInt32(OidFunctionCall1(get_hashfunc_oid(key->parttypid[0]), values[0])) % nparts;
```
本hash partition实现方式不需要事先确定好几个分区，可随时添加分区，这里需要考虑到如果分区中已经有数据的情况，当分区中有数据，如果新创建一个分区，分区数发生变化，计算出来的目标分区也就改变，同样的数据在不同的分区这样显然是不合理的，所以需要在创建新分区的时候对已有的数据重新进行计算并插入目标分区。
```sql
postgres=# insert into h select generate_series(1,20);
INSERT 0 20
postgres=# select tableoid::regclass,* from h;
 tableoid | id 
----------+----
 h1       |  1
 h1       |  2
 h1       |  5
 h1       |  6
 h1       |  8
 h1       |  9
 h1       | 12
 h1       | 13
 h1       | 15
 h1       | 17
 h1       | 19
 h2       |  3
 h2       |  4
 h2       |  7
 h2       | 10
 h2       | 11
 h2       | 14
 h2       | 16
 h2       | 18
 h2       | 20
(20 rows)

postgres=# create table h3 partition of h;
CREATE TABLE
postgres=# select tableoid::regclass,* from h;
 tableoid | id 
----------+----
 h1       |  5
 h1       | 17
 h1       | 19
 h1       |  3
 h2       |  7
 h2       | 11
 h2       | 14
 h2       | 18
 h2       | 20
 h2       |  2
 h2       |  6
 h2       | 12
 h2       | 15
 h3       |  1
 h3       |  8
 h3       |  9
 h3       | 13
 h3       |  4
 h3       | 10
 h3       | 16
(20 rows)

postgres=# 
```
## 数据查询

这里主要修改查询规划部分，在relation_excluded_by_constraints函数中添加对hash分区的过滤处理，排除掉不需要扫描的分区，这里使用与插入时一样的算法，找到目标分区，排除没必要的分区

```c
    if (NIL != root->append_rel_list)
    {
        Node        *parent = NULL;
        parent = (Node*)linitial(root->append_rel_list);

        if ((nodeTag(parent) == T_AppendRelInfo) && get_hash_part_strategy(((AppendRelInfo*)parent)->parent_reloid) == PARTITION_STRATEGY_HASH && (root->parse->jointree->quals != NULL))
        {
            Relation rel = RelationIdGetRelation(((AppendRelInfo*)parent)->parent_reloid);
            PartitionKey key = RelationGetPartitionKey(rel);

            heap_close(rel, NoLock);

            Const cc = *(Const*)((OpExpr*)((List*)root->parse->jointree->quals)->head->data.ptr_value)->args->head->next->data.ptr_value;
            
            cur_index = DatumGetUInt32(OidFunctionCall1(get_hashfunc_oid(key->parttypid[0]), cc.constvalue)) % list_length(root->append_rel_list);
            
            //hash分区则进行判断
            if (get_hash_part_number(rte->relid) != cur_index)
                return true;
            
        }
  }
```
return true;需要扫描，false不需要扫描，找到目标分区后，其他的过滤掉。

上面只是简单的获取 where id = 1;得到value值1，进行哈希运算寻找目标分区，还需要对where子句做更细致的处理，更多的可查看补丁。

目前完成以下几种的查询优化。
```sql
postgres=# explain analyze select * from h where id = 1;
                                             QUERY PLAN                                             
----------------------------------------------------------------------------------------------------
 Append  (cost=0.00..41.88 rows=13 width=4) (actual time=0.022..0.026 rows=1 loops=1)
   ->  Seq Scan on h3  (cost=0.00..41.88 rows=13 width=4) (actual time=0.014..0.017 rows=1 loops=1)
         Filter: (id = 1)
         Rows Removed by Filter: 4
 Planning time: 0.271 ms
 Execution time: 0.069 ms
(6 rows)

postgres=# explain analyze select * from h where id = 1 or id = 20;
                                             QUERY PLAN                                             
----------------------------------------------------------------------------------------------------
 Append  (cost=0.00..96.50 rows=50 width=4) (actual time=0.015..0.028 rows=2 loops=1)
   ->  Seq Scan on h3  (cost=0.00..48.25 rows=25 width=4) (actual time=0.014..0.017 rows=1 loops=1)
         Filter: ((id = 1) OR (id = 20))
         Rows Removed by Filter: 4
   ->  Seq Scan on h4  (cost=0.00..48.25 rows=25 width=4) (actual time=0.006..0.008 rows=1 loops=1)
         Filter: ((id = 1) OR (id = 20))
         Rows Removed by Filter: 10
 Planning time: 0.315 ms
 Execution time: 0.080 ms
(9 rows)

postgres=# explain analyze select * from h where id in (1,2,3);
                                             QUERY PLAN                                             
----------------------------------------------------------------------------------------------------
 Append  (cost=0.00..90.12 rows=76 width=4) (actual time=0.015..0.028 rows=3 loops=1)
   ->  Seq Scan on h3  (cost=0.00..45.06 rows=38 width=4) (actual time=0.014..0.018 rows=2 loops=1)
         Filter: (id = ANY ('{1,2,3}'::integer[]))
         Rows Removed by Filter: 3
   ->  Seq Scan on h4  (cost=0.00..45.06 rows=38 width=4) (actual time=0.005..0.008 rows=1 loops=1)
         Filter: (id = ANY ('{1,2,3}'::integer[]))
         Rows Removed by Filter: 10
 Planning time: 0.377 ms
 Execution time: 0.073 ms
(9 rows)
```
## 备份恢复

添加hash partition之后，备份恢复时，创建分区时将分区key的信息记录到了pg_class.relpartbound，
```sql
postgres=# create table h (id int) partition by hash(id);
CREATE TABLE
postgres=# create table h1 partition of h;
CREATE TABLE
postgres=# create table h2 partition of h;
CREATE TABLE
postgres=# select relname,relispartition,relpartbound from pg_class where relname like 'h%';;
 relname | relispartition |                                               relpartbound                                                
---------+----------------+-----------------------------------------------------------------------------------------------------------
 h       | f              | 
 h1      | t              | {PARTITIONBOUNDSPEC :strategy h :listdatums <> :lowerdatums <> :upperdatums <> :hashnumber 0 :location 0}
 h2      | t              | {PARTITIONBOUNDSPEC :strategy h :listdatums <> :lowerdatums <> :upperdatums <> :hashnumber 1 :location 0}
(3 rows)

使用pg_dump时，创建分区的语句会带有key值信息，导致恢复失败，

--
-- Name: h; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE h (
    id integer
)
PARTITION BY HASH (id);


ALTER TABLE h OWNER TO postgres;

--
-- Name: h1; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE h1 PARTITION OF h
SERIAL NUMBER 0;


ALTER TABLE h1 OWNER TO postgres;

--
-- Name: h2; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE h2 PARTITION OF h
SERIAL NUMBER 1;


ALTER TABLE h2 OWNER TO postgres;

CREATE TABLE h1 PARTITION OF h SERIAL NUMBER 0;
```
这样显然是错误的，需要修改pg_dump.c ,如果是hash partition，不将partbound信息添加进去
```c
if(!(strcmp(strategy, s) == 0))
{
	appendPQExpBufferStr(q, "\n");
	appendPQExpBufferStr(q, tbinfo->partbound);
}
```
## 回归测试

/src/test/regress/sql/：相关测试的sql文件

/src/test/regress/expected/：sql执行后的预期结果

/src/test/regress/results/：sql执行后的结果

diff 比较它们生成regression.diffs --> diff expected/xxxx.out results/xxxx.out

Beta2上是没有hash partition的，所以创建hash partition时会有不同，需要去掉不然回归测试不通过。
```sql
--- only accept "list" and "range" as partitioning strategy
-CREATE TABLE partitioned (
-	a int
-) PARTITION BY HASH (a);
-ERROR:  unrecognized partitioning strategy "hash"
```
## 其他

\d \d+
```sql
postgres=# \d+ h*
                                     Table "public.h"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           |          |         | plain   |              | 
Partition key: HASH (id)
Partitions: h1 SERIAL NUMBER 0,
            h2 SERIAL NUMBER 1

                                    Table "public.h1"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           |          |         | plain   |              | 
Partition of: h SERIAL NUMBER 0
Partition constraint: (id IS NOT NULL)

                                    Table "public.h2"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           |          |         | plain   |              | 
Partition of: h SERIAL NUMBER 1
Partition constraint: (id IS NOT NULL)
```
## 限制

### 不支持 attach、detach

```sql
postgres=# create table h3 (id int);
CREATE TABLE
postgres=# alter table h attach partition h3;
ERROR:  hash partition do not support attach operation
postgres=# alter table h detach partition h2;
ERROR:  hash partition do not support detach operation
```
### 不支持 drop 分区子表

```sql
postgres=# drop table h2;
ERROR:  hash partition "h2" can not be dropped
```
outfunc.c readfunc.c copyfunc.c

## 邮件列表

https://www.postgresql.org/message-id/2017082612390093777512%40highgo.com

