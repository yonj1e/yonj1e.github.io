---
title: page的内部结构
date: 2018-07-20 
categories: 
  - [PostgreSQL - Internals]
tags: 
  - PostgreSQL
  - Page
---



[原文](https://www.8kdata.com/blog/postgresql-page-layout/)

简要概述PostgreSQL如何将数据存储到page页中。 

作为开发人员，我们通常每天都使用数据库，但是我们真的知道它们是如何工作的吗？他们如何存储信息？使用哪种内部结构？本文将介绍在PostgreSQL中如何存储信息。

#### 获取page页信息

为了获得数据结构的详细信息，我们需要使用 `pageinspect` 扩展。

安装此扩展后，我们就能够获得PostgreSQL中page页的详细信息。 

安装： 

```sql
# create extension pageinspect;
```

#### Page页的结构

使用 `pageinspect` 扩展中包含的一些函数来分析page页结构。

例如，我们可以获取在每个page页的header信息，如下所示：获取表 `test` 中的第一页的信息。

```sql
# SELECT * FROM page_header(get_raw_page('public.test', 0));
    lsn    | checksum | flags | lower | upper | special | pagesize | version | prune_xid 
-----------+----------+-------+-------+-------+---------+----------+---------+-----------
 0/1898650 |        0 |     0 |    44 |  7992 |    8192 |     8192 |       4 |       565
(1 row)
```

header是page页的前24个字节，包含一些基本信息，如指向空闲空间的指针或page页的大小(默认情况下为8KB)等。

`page_header` 中的每一列的含义：

- **lsn**: Log Sequence Number: is the address of the next byte to be used in the page xlog.
- **checksum**: Page checksum.
- **flags**: Various flag bits.
- **lower**: The offset where the free space starts, it will be the initial address to the next tuple created.
- **upper**: The offset where the free space ends.
- **special**: The offset where the special space starts, it is at the end of the page actually.
- **pagesize**: 页面的大小，默认为8KB，但可以配置。
- **version**: 页面版本号。
- **prune_xid**: Signals when pruning operation can be a good option to improve the system.

page结构图如下：

![PostgreSQL page layout](2018-07-20-page-layout/pg-page-layout.jpg?raw=true)

图中有一些数据没有出现在 `page_Header` 中，它们是PostgreSQL配置的一部分，比如 `fill factor` 或 `alignment padding`。

#### Fill factor

`fill factor` 是一个值，它告诉PostgreSQL何时停止在当前页面中存储元组并切换到新的page页。默认情况下，页面不是完全填充的。这允许将更新元组存储在同一原始页面中，从而提高系统性能。

#### Alignment padding

为了提高I/O性能，PostgreSQL使用的字长取决于运行它的机器。在具有64位处理器的现代计算机中，字长为8字节。

这导致元组与磁盘占用的大小不完全相同，因为PostgreSQL使用这个额外的空间(alignment)来提高I/O性能。

#### Tuple的结构

也可以使用 `heap_page_items` 函数来分析元组。

```sql
# select * from heap_page_items(get_raw_page('test', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |               t_data               
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+------------------------------------
  1 |   8152 |        1 |     40 |    560 |    565 |        0 | (0,1)  |        8194 |       1280 |     24 |        |       | \x010000000000000025faa56e92130200
  2 |   8112 |        1 |     40 |    561 |    565 |        0 | (0,2)  |        8194 |       1280 |     24 |        |       | \x020000000000000049771ca792130200
  3 |   8072 |        1 |     40 |    566 |      0 |        0 | (0,3)  |           2 |       2304 |     24 |        |       | \x0100000000000000dae60fad92130200
  4 |   8032 |        1 |     40 |    568 |      0 |        0 | (0,4)  |           2 |       2304 |     24 |        |       | \x02000000000000005cd95aff92130200
  5 |   7992 |        1 |     40 |    588 |      0 |        0 | (0,5)  |           2 |       2304 |     24 |        |       | \x030000000000000054a12f2aa6130200
(5 rows)
```

每个元组包含关于在页面内的位置、可见性或大小等方面的信息。

- **lp**: The index of the tuple in the page.
- **lp_off**: Offset of the tubple inside the page.
- **lp_flags**: Keeps the status of the item pointer.
- **lp_len**: Length of the tuple.
- **t_xmin**: Transaction number when the tuple was created.
- **t_xmax**: Transaction number when the tuple was deleted.
- **t_field3**: It can contains one of two possible values, t_cid or t_xvac. The t_cid is the CID signature from the insert or delete. The t_xvac is the XID for the VACUMM operation when row version changes.
- **t_ctid**: Current TID.
- **t_infomask2**: Number of attributes and some flag bits.
- **t_infomask**: Some flag bits.
- **t_hoff**: Is the offset where the user data is stored inside the tuple.

![Tuple header layout](2018-07-20-page-layout/tuple-header-layout.jpg?raw=true)

#### TOAST

查看页面大小很容易发现某些数据无法存储在如此小的空间中。对于这些情况，有一种称为[TOAST](https://www.postgresql.org/docs/current/static/storage-toast.html)的机制。

默认情况下，PostgreSQL有两个变量，`toast_tuple_threshold` 和 `toast_tuple_target`，默认为2K。当存储元组并且大于2K时，可使用它的字段类型(不是全部适用于TOAST)存储在TOAST表中。