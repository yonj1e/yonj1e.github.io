---
title: 源码安装PipelineDB
date: 2018-12-12
categories: 
  - [PipelineDB]
  - [PostgreSQL - 最佳实践]
tags: 
  - PipelineDB
  - PostgreSQL
---



PipelineDB is a PostgreSQL extension for high-performance time-series aggregation, designed to power realtime reporting and analytics applications.

#### 源码编译安装PipelineDB

前提：

[PostgreSQL](https://github.com/postgres/postgres)

```shell
#!/bin/bash

git clone git@github.com:postgres/postgres.git
cd postgres/
git checkout REL_11_STABLE
make clean; make; make install;
cd contrib/
make clean; make; make install;
```

[ZeroMQ](https://github.com/zeromq/libzmq)

```shell
#!/bin/bash

git clone git@github.com:zeromq/libzmq.git
cd libzmq/
./autogen.sh 
# 指定--prefix=/usr，或者修改pipelinedb Makefile
# 添加后面的编译选项，否则编译pipeline报错：xxx can not be used when making a shared object; recompile with -fPIC
./configure --prefix=/usr CPPFLAGS=-DPIC CFLAGS=-fPIC CXXFLAGS=-fPIC LDFLAGS=-fPIC
make; 
# make check;
sudo make install;
sudo ldconfig
```
[PipelineDB](https://github.com/pipelinedb/pipelinedb)

```shell
#!/bin/bash

cd postgres/contrib
git clone git@github.com:pipelinedb/pipelinedb.git
cd pipelinedb
make USE_PGXS=1
make install
```

创建扩展

```sql
# postgresql.conf
shared_preload_libraries = 'pipelinedb' 
$ ./pg_ctl -D ../data start
$ ./psql postgres
psql (11.1)
Type "help" for help.

postgres=# create extension pipelinedb ;
CREATE EXTENSION
postgres=# \dx
                   List of installed extensions
    Name    | Version |   Schema   |         Description          
------------+---------+------------+------------------------------
 pipelinedb | 1.0.0   | public     | PipelineDB
 plpgsql    | 1.0     | pg_catalog | PL/pgSQL procedural language
(2 rows)
```

```shell
10106 pts/1    S      0:00 /work/pgsql/pgsql-11-stable/bin/postgres -D ../data
10108 ?        Ss     0:00 postgres: checkpointer   
10109 ?        Ss     0:00 postgres: background writer   
10110 ?        Ss     0:00 postgres: walwriter   
10111 ?        Ss     0:00 postgres: autovacuum launcher   
10112 ?        Ss     0:00 postgres: stats collector   
10113 ?        Ss     0:00 postgres: scheduler   
10114 ?        Ss     0:00 postgres: logical replication launcher   
10121 ?        SNsl   0:00 postgres: reaper0 [postgres]   
10122 ?        SNsl   0:00 postgres: queue0 [postgres]   
10123 ?        SNsl   0:00 postgres: combiner0 [postgres]   
10124 ?        SNsl   0:00 postgres: worker0 [postgres]
```

