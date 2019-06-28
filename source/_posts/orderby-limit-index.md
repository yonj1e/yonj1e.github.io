---
title: PostgreSQ 中 order by limit 索引选择问题
date: 2019-06-27 
categories: 
  - [PostgreSQL]
tags: 
  - PostgreSQL
  - Order By
  - Limit
  - Index
---

## 简介

相同sql，limit 1和limit 10，走不同索引，效率相差很大

实际执行计划如下:

```sql
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 1;
                                                                                    QUERY PLAN                                                                                   
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.44..1690.33 rows=1 width=16) (actual time=12816.268..12816.269 rows=1 loops=1)
   ->  Index Scan Backward using test_tbl_create_time_idx on test_tbl  (cost=0.44..1936615.36 rows=1146 width=16) (actual time=12816.266..12816.266 rows=1 loops=1)
         Filter: ((status = 0) AND (city_id = 310188) AND (type = 103) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])))
         Rows Removed by Filter: 9969343
 Planning time: 2.940 ms
 Execution time: 12816.306 ms
(6 rows)
 
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 10;
                                                                                      QUERY PLAN                                                                                     
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=4268.71..4268.73 rows=10 width=16) (actual time=0.082..0.084 rows=10 loops=1)
   ->  Sort  (cost=4268.71..4271.57 rows=1146 width=16) (actual time=0.082..0.083 rows=10 loops=1)
         Sort Key: create_time
         Sort Method: quicksort  Memory: 25kB
         ->  Index Scan using test_tbl_city_id_sub_type_create_time_idx on test_tbl  (cost=0.44..4243.94 rows=1146 width=16) (actual time=0.030..0.066 rows=15 loops=1)
               Index Cond: ((city_id = 310188) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])))
 Planning time: 0.375 ms
 Execution time: 0.150 ms
(8 rows)
```

两个走的索引不一样

```sql
test=# \d test_tbl_create_time_idx
     Index "public.test_tbl_create_time_idx"
   Column    |            Type             | Definition 
-------------+-----------------------------+-------------
 create_time | timestamp without time zone | create_time
btree, for table "public.test_tbl"
 
 
test=# \d test_tbl_city_id_sub_type_create_time_idx
Index "public.test_tbl_city_id_sub_type_create_time_idx"
   Column    |            Type             | Definition 
-------------+-----------------------------+-------------
 city_id     | integer                     | city_id
 sub_type    | integer                     | sub_type
 create_time | timestamp without time zone | create_time
btree, for table "public.test_tbl", predicate (type = 103 AND status = 0)
```

首先，表的记录数(3123万)除以满足whereclase的记录数(1199)，得到平均需要扫描多少条记录，可以得到一条满足whereclase条件的记录

```sql
test=# select count(*) from test_tbl;
  count  
----------
 31227936
(1 row)
 
test=# select 31227936/1199;
 ?column?
----------
    26044
(1 row)
```

也就是说每扫描26044条记录，可以得到一条满足条件的记录。（优化器这么算，是认为数据分布是均匀的。）

但是，实际上，数据分布是不均匀的，whereclause的记录在表的前端。

并不是估算的每扫描26044条记录，可以得到一条满足条件的记录。

问题就出在这里。

```sql
# ctid
test=# select max(ctid) from test_tbl;
     max     
--------------
 (244118,407)
(1 row)
 
test=# select max(ctid),min(ctid) from test_tbl where data_id in (select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305));
    max     |    min   
------------+-----------
 (21293,15) | (2444,73)
(1 row)
 
 
 
# 分布在28w个rows里(不一定均匀分布),且通过数据分布分别在表中的 page min号 是 2444, max号是21293, 整个表的最大page号是 244118, 可以看出符合条件的28w行,物理分布于表的前端.
 
test=# select 31227936/244118*21293;
 ?column?
----------
  2704211
(1 row)
 
# order by asc 就能看出效果
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time asc limit 1;
                                                                              QUERY PLAN                                                                              
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.44..1615.86 rows=1 width=16) (actual time=4295.865..4295.866 rows=1 loops=1)
   ->  Index Scan using test_tbl_create_time_idx on test_tbl  (cost=0.44..1936888.15 rows=1199 width=16) (actual time=4295.864..4295.864 rows=1 loops=1)
         Filter: ((status = 0) AND (city_id = 310188) AND (type = 103) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])))
         Rows Removed by Filter: 4712758
 Planning time: 0.404 ms
 Execution time: 4295.884 ms
(6 rows)
```

## 为什么走不同的索引

实际上PG会通过计算成本得到应该使用哪个索引



在limit10 时, 使用test_tbl_city_id_sub_type_create_time_idx索引的时候，需要扫描1199行，然后排序，总cost是 cost=4268.71..4271.57，然后取出 desc 的10个tuple,需要的cost是cost=4268.71..4268.73,

实际的执行时间是: actual time=0.082..0.084，从这点来看，limit 10 的真正执行时间比执行计划还快, 可以认为是查询规化器从诸多查询路径中，找到较优的执行计划了.



在 limit 1 时, 使用 test_tbl_create_time_idx的时候, 

Limit (cost=0.44..1690.33 rows=1 width=16) (actual time=12816.268..12816.269 rows=1 loops=1)

执行计划预估是 cost=0.44..1690.33，但是实际却是 actual time=12816.268..12816.269,  明显查询规化器从诸多查询路径中，找到的执行计划不是较优的. 也就是查询规化器出现了误判.



返回多少条记录能达到4271.57成本（limit 1 cost 1690.33，limit 10 sort cost 4271.57）

```sql
test=# select 4271.57/1690.33;
      ?column?     
--------------------
 2.5270627628924530
(1 row)
```

limit 大于2.5的时候走 test_tbl_city_id_sub_type_create_time_idx 索引

limit 小于2.5的时候走  test_tbl_create_time_idx 索引

验证一下，也确实如此

```sql
test=#  explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 3;
                                                                                      QUERY PLAN                                             
                                         
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=4455.61..4455.62 rows=3 width=16) (actual time=0.103..0.103 rows=3 loops=1)
   ->  Sort  (cost=4455.61..4458.61 rows=1199 width=16) (actual time=0.103..0.103 rows=3 loops=1)
         Sort Key: create_time
         Sort Method: top-N heapsort  Memory: 25kB
         ->  Index Scan using test_tbl_city_id_sub_type_create_time_idx on test_tbl  (cost=0.44..4440.12 rows=1199 width=16) (ac
tual time=0.047..0.088 rows=15 loops=1)
               Index Cond: ((city_id = 310188) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])))
 Planning time: 0.413 ms
 Execution time: 0.151 ms
(8 rows)
 
 
test=#  explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 2;
                                                                                    QUERY PLAN                                               
                                     
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.44..3231.28 rows=2 width=16) (actual time=11433.166..15947.713 rows=2 loops=1)
   ->  Index Scan Backward using test_tbl_create_time_idx on test_tbl  (cost=0.44..1936892.40 rows=1199 width=16) (actual time=11433.164..15947.708 rows=2 loops=1)
         Filter: ((status = 0) AND (city_id = 310188) AND (type = 103) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])))
         Rows Removed by Filter: 13631428
 Planning time: 0.375 ms
 Execution time: 15947.730 ms
(6 rows)
```

很显然，根据order by create_time desc 作为依据, 来使用test_tbl_create_time_idx (单个字段 create_time 的index)进行扫描，一定会慢，因为满足条件的数据都分布在**前**28w条记录中

## 优化方法

#### 改SQL

a 强制不走cretate_time扫描

```sql
# order by create_time, data_id
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc,1 limit 1;
                                                                                      QUERY PLAN                                                                                     
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=4475.93..4475.93 rows=1 width=16) (actual time=0.193..0.193 rows=1 loops=1)
   ->  Sort  (cost=4475.93..4478.94 rows=1207 width=16) (actual time=0.193..0.193 rows=1 loops=1)
         Sort Key: create_time, data_id
         Sort Method: top-N heapsort  Memory: 25kB
         ->  Index Scan using test_tbl_city_id_sub_type_type_status_idx on test_tbl  (cost=0.44..4469.89 rows=1207 width=16) (actual time=0.128..0.173 rows=15 loops=1)
               Index Cond: ((city_id = 310188) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])) AND (type = 103) AND (status = 0))
 Planning time: 1.614 ms
 Execution time: 0.219 ms
(8 rows)
```

b 使用with

```sql
test=# explain analyze with cte as (select data_id from test_tbl where status=0 and city_id=310188 and type=103  and sub_type in(10306,10304,10305)  order by create_time desc)
select data_id from cte limit 1;
                                                                                   QUERY PLAN                                                                                   
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=4535.80..4535.82 rows=1 width=8) (actual time=0.075..0.075 rows=1 loops=1)
   CTE cte
     ->  Sort  (cost=4532.87..4535.80 rows=1169 width=16) (actual time=0.073..0.073 rows=1 loops=1)
           Sort Key: test_tbl.create_time
           Sort Method: quicksort  Memory: 25kB
           ->  Index Scan using idx_test_tbl_city_id_sub_type_type on test_tbl  (cost=0.44..4473.31 rows=1169 width=16) (actual time=0.019..0.067 rows=15 loops=1)
                 Index Cond: ((city_id = 310188) AND (sub_type = ANY ('{10306,10304,10305}'::integer[])) AND (type = 103))
                 Filter: (status = 0)
                 Rows Removed by Filter: 22
   ->  CTE Scan on cte  (cost=0.00..23.38 rows=1169 width=8) (actual time=0.075..0.075 rows=1 loops=1)
 Planning time: 0.306 ms
 Execution time: 0.097 ms
(12 rows)
```

#### 加多列复合索引

加到哪几个字段是关键

比如 create index CONCURRENTLY ON test_tbl (city_id,sub_type,create_time desc) where type=103 and status = 0; 就没有效果.

```sql
test=# select count(distinct city_id), count(distinct sub_type), count(distinct type), count(distinct status) from test_tbl;
 count | count | count | count
-------+-------+-------+-------
 29689 |    42 |     4 |     9
(1 row)
 
 
create index CONCURRENTLY  on test_tbl(city_id, create_time) where  status=0  and type=103;
 
test=# \d test_tbl_city_id_create_time_idx
 Index "public.test_tbl_city_id_create_time_idx"
   Column    |            Type             | Definition 
-------------+-----------------------------+-------------
 city_id     | integer                     | city_id
 create_time | timestamp without time zone | create_time
btree, for table "public.test_tbl", predicate (status = 0 AND type = 103)
 
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 10;
                                                                                    QUERY PLAN                                                                                   
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.44..764.64 rows=10 width=16) (actual time=6.121..25.471 rows=10 loops=1)
   ->  Index Scan Backward using test_tbl_city_id_create_time_idx on test_tbl  (cost=0.44..91628.47 rows=1199 width=16) (actual time=6.120..25.466 rows=10 loops=1)
         Index Cond: (city_id = 310188)
         Filter: (sub_type = ANY ('{10306,10304,10305}'::integer[]))
         Rows Removed by Filter: 4237
 Planning time: 0.525 ms
 Execution time: 25.512 ms
(7 rows)
 
test=# explain analyze select data_id from test_tbl where status=0 and city_id=310188 and type=103 and sub_type in(10306,10304,10305) order by create_time desc limit 1;
                                                                                   QUERY PLAN                                                                                  
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.44..76.86 rows=1 width=16) (actual time=0.935..0.935 rows=1 loops=1)
   ->  Index Scan Backward using test_tbl_city_id_create_time_idx on test_tbl  (cost=0.44..91628.47 rows=1199 width=16) (actual time=0.934..0.934 rows=1 loops=1)
         Index Cond: (city_id = 310188)
         Filter: (sub_type = ANY ('{10306,10304,10305}'::integer[]))
         Rows Removed by Filter: 796
 Planning time: 0.447 ms
 Execution time: 0.956 ms
(7 rows)
```

## 参考

https://yq.aliyun.com/articles/647456