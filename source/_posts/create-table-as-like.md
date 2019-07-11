---
title: PostgreSQ中的表复制
date: 2019-05-19
categories:
  - [PostgreSQL]
tags:
  - PostgreSQL
  - CREATE TABLE AS
  - CREATE TABLE LIKE
  - CREATE TABLE
---

PostgreSQL提供了两种语法来进行表复制，分别是：

- CREATE TABLE AS
- CREATE TABLE LIKE

CREATE TABLE AS 复制的表，所有约束、注释和序列都没有被拷贝，只是简单的字段拷贝，同时数据也能拷贝过来了。

CREATE TABLE LIKE 复制的表，里面没有数据，但是你可以指定复制标的约束，索引，注释，序列。其中

1. including constraints ：复制约束
2. including indexes ：复制索引
3. including comments：复制注释
4. including defaults：复制序列

# create table

```sql
`yangjie=# create table tbl1 (id serial primary key, info text);``CREATE TABLE``yangjie=# \d+ tbl1``                                                ``Table ``"public.tbl1"`` ``Column |  Type   | Collation | Nullable |             Default              | Storage  | Stats target | Description``--------+---------+-----------+----------+----------------------------------+----------+--------------+-------------`` ``id     | integer |           | not ``null` `| nextval(``'tbl1_id_seq'``::regclass) | plain    |              |`` ``info   | text    |           |          |                                  | extended |              |``Indexes:``    ``"tbl1_pkey"` `PRIMARY KEY, btree (id)` `yangjie=# insert into tbl1 (info) values (``'aa'``);``INSERT ``0` `1``yangjie=# insert into tbl1 (info) values (``'bb'``);``INSERT ``0` `1``yangjie=# insert into tbl1 (info) values (``'cc'``);``INSERT ``0` `1``yangjie=# select * from tbl1;`` ``id | info``----+------``  ``1` `| aa``  ``2` `| bb``  ``3` `| cc``(``3` `rows)`
```

# create table as

```sql
`yangjie=# create table tbl2 as select * from tbl1;``SELECT ``3``yangjie=# \d+ tbl2``                                    ``Table ``"public.tbl2"`` ``Column |  Type   | Collation | Nullable | Default | Storage  | Stats target | Description``--------+---------+-----------+----------+---------+----------+--------------+-------------`` ``id     | integer |           |          |         | plain    |              |`` ``info   | text    |           |          |         | extended |              |` `yangjie=# select * from tbl2 ;`` ``id | info``----+------``  ``1` `| aa``  ``2` `| bb``  ``3` `| cc``(``3` `rows)`
```

# create table like

```sql
`yangjie=# create table tbl3 (like tbl1 including all);``CREATE TABLE``yangjie=# \d+ tbl3``                                                ``Table ``"public.tbl3"`` ``Column |  Type   | Collation | Nullable |             Default              | Storage  | Stats target | Description``--------+---------+-----------+----------+----------------------------------+----------+--------------+-------------`` ``id     | integer |           | not ``null` `| nextval(``'tbl1_id_seq'``::regclass) | plain    |              |`` ``info   | text    |           |          |                                  | extended |              |``Indexes:``    ``"tbl3_pkey"` `PRIMARY KEY, btree (id)` `yangjie=# select * from tbl3;`` ``id | info``----+------``(``0` `rows)`
```

插入数据

```sql
`yangjie=# insert into tbl3 (info) values (``'dd'``);``INSERT ``0` `1``yangjie=# select * from tbl3;`` ``id | info``----+------``  ``4` `| dd``(``1` `row)`
```

这里序列是接着旧表tbl1继续的。

重建sequence

```sql
`yangjie=# create sequence tbl3_id_seq;``CREATE SEQUENCE` `yangjie=# alter table tbl3 alter id set ``default` `nextval(``'tbl3_id_seq'``::regclass) ;``ALTER TABLE` `yangjie=# \d+ tbl3``                                                ``Table ``"public.tbl3"`` ``Column |  Type   | Collation | Nullable |             Default              | Storage  | Stats target | Description``--------+---------+-----------+----------+----------------------------------+----------+--------------+-------------`` ``id     | integer |           | not ``null` `| nextval(``'tbl3_id_seq'``::regclass) | plain    |              |`` ``info   | text    |           |          |                                  | extended |              |``Indexes:``    ``"tbl3_pkey"` `PRIMARY KEY, btree (id)`
```

插入数据

```sql
`yangjie=# insert into tbl3 (info) values (``'ee'``);``INSERT ``0` `1``yangjie=# select * from tbl3;`` ``id | info``----+------``  ``4` `| dd``  ``1` `| ee``(``2` `rows)`
```

发现从1开始插入数据了，但4怎么办

```sql
`yangjie=# insert into tbl3 (info) values (``'ff'``);``INSERT ``0` `1``yangjie=# insert into tbl3 (info) values (``'gg'``);``INSERT ``0` `1``yangjie=# select * from tbl3;`` ``id | info``----+------``  ``4` `| dd``  ``1` `| ee``  ``2` `| ff``  ``3` `| gg``(``4` `rows)` `yangjie=# insert into tbl3 (info) values (``'hh'``);``ERROR:  duplicate key value violates unique constraint ``"tbl3_pkey"``DETAIL:  Key (id)=(``4``) already exists.``# 在执行一次，成功插入``yangjie=# insert into tbl3 (info) values (``'hh'``);``INSERT ``0` `1``yangjie=# select * from tbl3;`` ``id | info``----+------``  ``4` `| dd``  ``1` `| ee``  ``2` `| ff``  ``3` `| gg``  ``5` `| hh``(``5` `rows)`
```