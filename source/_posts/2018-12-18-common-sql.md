---
title: 常用SQL
date: 2018-12-18 
categories: 
  - [SQL]
tags: 
  - PostgreSQL
  - SQL
---



#### 索引系统表

```sql
-- 查看该索引所在表的名称，以及构成该索引的键值数量和具体键值的字段编号
SELECT indnatts,indkey,relname 
FROM pg_index i, pg_class c 
WHERE c.relname LIKE 'test%' AND indrelid = c.oid;

-- 查看指定表包含的索引，同时列出索引的名称
SELECT 
	t.relname AS table_name, 
	c.relname AS index_name 
FROM (
    SELECT relname, indexrelid 
    FROM pg_index i, pg_class c 
    WHERE c.relname LIKE 'test%' AND indrelid = c.oid
) t, pg_index i, pg_class c 
WHERE t.indexrelid = i.indexrelid AND i.indexrelid = c.oid;

-- 查看表明，索引名，索引定义
SELECT tablename, indexname, indexdef 
FROM pg_indexes i, pg_class c 
WHERE c.relname = i.tablename AND c.relname like 'test%';

-- 查看分区表索引，注：看不到主表
SELECT relname, relkind, tablename, indexname, indexdef 
FROM pg_indexes i 
RIGHT JOIN pg_class c ON c.relname = i.tablename 
WHERE c.relkind <> 'i' AND c.relname like 'test%';
   relname   | relkind |  tablename  |     indexname      |                               indexdef                                
-------------+---------+-------------+--------------------+-----------------------------------------------------------------------
 test_hash   | p       |             |                    | 
 test_hash_1 | r       | test_hash_1 | test_hash_1_id_idx | CREATE INDEX test_hash_1_id_idx ON public.test_hash_1 USING hash (id)
 test_hash_2 | r       | test_hash_2 | test_hash_2_id_idx | CREATE INDEX test_hash_2_id_idx ON public.test_hash_2 USING hash (id)
(3 rows)

-- 查看分区表索引，包括主表
SELECT c2.relname, pg_catalog.pg_get_indexdef(i.indexrelid, 0, true)
FROM pg_catalog.pg_class c, pg_catalog.pg_class c2, pg_catalog.pg_index i
WHERE c.oid = i.indrelid AND i.indexrelid = c2.oid AND c.relname like '%hash%'
ORDER BY c2.relname;
      relname       |                        pg_get_indexdef                         
--------------------+----------------------------------------------------------------
 idx_hash           | CREATE INDEX idx_hash ON ONLY test_hash USING hash (id)
 test_hash_1_id_idx | CREATE INDEX test_hash_1_id_idx ON test_hash_1 USING hash (id)
 test_hash_2_id_idx | CREATE INDEX test_hash_2_id_idx ON test_hash_2 USING hash (id)
(3 rows)

SELECT c2.relname, pg_catalog.pg_get_indexdef(i.indexrelid, 0, true), pg_catalog.pg_get_constraintdef(con.oid, true)
FROM pg_catalog.pg_class c, pg_catalog.pg_class c2, pg_catalog.pg_index i
LEFT JOIN pg_catalog.pg_constraint con ON (conrelid = i.indrelid AND conindid = i.indexrelid AND contype IN ('p','u','x'))
WHERE c.oid = i.indrelid AND i.indexrelid = c2.oid AND c.relname like '%hash%'
ORDER BY c2.relname;
      relname       |                        pg_get_indexdef                         | pg_get_constraintdef 
--------------------+----------------------------------------------------------------+----------------------
 idx_hash           | CREATE INDEX idx_hash ON ONLY test_hash USING hash (id)        | 
 test_hash_1_id_idx | CREATE INDEX test_hash_1_id_idx ON test_hash_1 USING hash (id) | 
 test_hash_2_id_idx | CREATE INDEX test_hash_2_id_idx ON test_hash_2 USING hash (id) | 
(3 rows)
```

