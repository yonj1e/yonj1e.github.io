---
title: 数据文件解析pg_filedump
date: 2018-11-26 
categories: 
  - [PostgreSQL - 最佳实践]
tags: 
  - pg_filedump
  - PostgreSQL
---



最初看这方面是因为验证添加的加密功能，所以用linux进制查看工具直接查看数据文件是否加密。

查看PostgreSQL数据文件

```sql
test=# insert into tt values (1, 'aaaaaaa');
INSERT 0 1

test=# select * from tt ;
 id |   tx    
----+---------
  1 | aaaaaaa
(1 row)

test=# SELECT relname, oid, relfilenode FROM pg_class WHERE relname = 'tt';
 relname |  oid  | relfilenode 
---------+-------+-------------
 tt      | 16388 |       16394
(1 row)
```

linux进制查看工具

```shell
# hexdump
$ hexdump -C 16394
00000000  00 00 00 00 50 52 73 01  00 00 00 00 1c 00 d8 1f  |....PRs.........|
00000010  00 20 04 20 00 00 00 00  d8 9f 48 00 00 00 00 00  |. . ......H.....|
00000020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001fd0  00 00 00 00 00 00 00 00  34 02 00 00 00 00 00 00  |........4.......|
00001fe0  00 00 00 00 00 00 00 00  01 00 02 00 02 08 18 00  |................|
00001ff0  01 00 00 00 11 61 61 61  61 61 61 61 00 00 00 00  |.....aaaaaaa....|
00002000

# od
$ xxd 16394
···
0001fb0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
0001fc0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
0001fd0: 0000 0000 0000 0000 3402 0000 0000 0000  ........4.......
0001fe0: 0000 0000 0000 0000 0100 0200 0208 1800  ................
0001ff0: 0100 0000 1161 6161 6161 6161 0000 0000  .....aaaaaaa....

# xxd
$ od -c 16394
0000000  \0  \0  \0  \0   P   R   s 001  \0  \0  \0  \0 034  \0 330 037
0000020  \0     004      \0  \0  \0  \0 330 237   H  \0  \0  \0  \0  \0
0000040  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0
*
0017720  \0  \0  \0  \0  \0  \0  \0  \0   4 002  \0  \0  \0  \0  \0  \0
0017740  \0  \0  \0  \0  \0  \0  \0  \0 001  \0 002  \0 002  \b 030  \0
0017760 001  \0  \0  \0 021   a   a   a   a   a   a   a  \0  \0  \0  \0
0020000
```

后来发现pg有提供数据文件解析的工具

[pg_filedump wiki](https://wiki.postgresql.org/wiki/Pg_filedump)

```sql
postgres=# create table test(id int, info text);
CREATE TABLE
postgres=# insert into test values (1, 'aaa');
INSERT 0 1
postgres=# insert into test values (2, 'bbb');
INSERT 0 1
postgres=# insert into test values (3, 'ccc');
INSERT 0 1
postgres=# select * from test;
 id | info 
----+------
  1 | aaa
  2 | bbb
  3 | ccc
(3 rows)

postgres=# select pg_relation_filepath('test');
 pg_relation_filepath 
----------------------
 base/13212/16445
(1 row)
```

解析数据文件

```shell
./pg_filedump -i -D int,text -f ../data/base/13212/16445|less
*******************************************************************
* PostgreSQL File/Block Formatted Dump Utility - Version 11.0
*
* File: ../data/base/13212/16445
* Options used: -i -D int,text -f 
*
* Dump created on: Fri Dec 28 10:15:22 2018
*******************************************************************

Block    0 ********************************************************
<Header> -----
 Block Offset: 0x00000000         Offsets: Lower      36 (0x0024)
 Block: Size 8192  Version    4            Upper    8096 (0x1fa0)
 LSN:  logid      0 recoff 0x016deef8      Special  8192 (0x2000)
 Items:    3                      Free Space: 8060
 Checksum: 0x0000  Prune XID: 0x00000000  Flags: 0x0000 ()
 Length (including item array): 36

  0000: 00000000 f8ee6d01 00000000 2400a01f  ......m.....$...
  0010: 00200420 00000000 e09f4000 c09f4000  . . ......@...@.
  0020: a09f4000                             ..@.            

<Data> ------ 
 Item   1 -- Length:   32  Offset: 8160 (0x1fe0)  Flags: NORMAL
  XMIN: 583  XMAX: 0  CID|XVAC: 0
  Block Id: 0  linp Index: 1   Attributes: 2   Size: 24
  infomask: 0x0802 (HASVARWIDTH|XMAX_INVALID) 

  1fe0: 47020000 00000000 00000000 00000000  G...............
  1ff0: 01000200 02081800 01000000 09616161  .............aaa

COPY: 1 aaa
 Item   2 -- Length:   32  Offset: 8128 (0x1fc0)  Flags: NORMAL
  XMIN: 584  XMAX: 0  CID|XVAC: 0
  Block Id: 0  linp Index: 2   Attributes: 2   Size: 24
  infomask: 0x0802 (HASVARWIDTH|XMAX_INVALID) 

  1fc0: 48020000 00000000 00000000 00000000  H...............
  1fd0: 02000200 02081800 02000000 09626262  .............bbb

COPY: 2 bbb
 Item   3 -- Length:   32  Offset: 8096 (0x1fa0)  Flags: NORMAL
  XMIN: 585  XMAX: 0  CID|XVAC: 0
  Block Id: 0  linp Index: 3   Attributes: 2   Size: 24
  infomask: 0x0802 (HASVARWIDTH|XMAX_INVALID) 

  1fa0: 49020000 00000000 00000000 00000000  I...............
  1fb0: 03000200 02081800 03000000 09636363  .............ccc

COPY: 3 ccc


*** End of File Encountered. Last Block Read: 0 ***
:
```

