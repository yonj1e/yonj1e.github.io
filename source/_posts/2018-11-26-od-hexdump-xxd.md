---
title: Linux进制查看工具
date: 2018-11-26 
categories: 
  - [Linux]
tags: 
  - Linux
---



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
