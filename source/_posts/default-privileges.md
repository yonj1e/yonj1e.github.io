---
title: ALTER DEFAULT PRIVILEGES使用
date: 2019-04-27
categories:
  - [PostgreSQL]
tags:
  - PostgreSQL
  - DEFAULT PRIVILEGES
  - Grant
---

ALTER DEFAULT PRIVILEGES 允许您设置将应用于将来创建的对象的权限。（它不会影响分配给已存在对象的权限）

您只能为将由您自己或您所属的角色创建的对象更改默认权限。

测试下 alter default privileges for role

添加只读用户，赋予select权限

```sql
`yangjie=# create role r with login;``CREATE ROLE``yangjie=# grant SELECT on ALL tables in schema ``public` `to r;``GRANT` `yangjie=# alter ``default` `privileges in schema ``public` `grant select on tables to r;``ALTER DEFAULT PRIVILEGES`
```

repmgr用户创建一张表

```sql
`yangjie``@young``:~ $ psql -U repmgr -d yangjie``psql (``11.3``)``Type ``"help"` `for` `help.` `yangjie=# \d``               ``List of relations`` ``Schema |        Name        | Type  |  Owner ``--------+--------------------+-------+---------`` ``public` `| pg_stat_statements | view  | yangjie`` ``public` `| test               | table | yangjie``(``2` `rows)` `yangjie=# create table tr(id ``int``, info text);``CREATE TABLE``yangjie=# insert into tr select generate_series(``1``,``10``);``INSERT ``0` `10`
```

用户r查询repmgr创建的表，不能访问

```sql
`yangjie``@young``:~ $ psql -U r -d yangjie``psql (``11.3``)``Type ``"help"` `for` `help.` `yangjie=> \d``               ``List of relations`` ``Schema |        Name        | Type  |  Owner ``--------+--------------------+-------+---------`` ``public` `| pg_stat_statements | view  | yangjie`` ``public` `| test               | table | yangjie`` ``public` `| tr                 | table | repmgr``(``3` `rows)` `yangjie=> select * from tr ;``ERROR:  permission denied ``for` `table tr`
```

对于随后由角色repmgr创建的所有表赋予查询权限

```sql
`yangjie``@young``:~ $ psql``psql (``11.3``)``Type ``"help"` `for` `help.`  `yangjie=# alter ``default` `privileges ``for` `role repmgr in schema ``public` `grant select on tables to r;``ALTER DEFAULT PRIVILEGES`
```

repmgr用户新建表

```sql
`yangjie``@young``:~ $ psql -U repmgr -d yangjie``psql (``11.3``)``Type ``"help"` `for` `help.`  `yangjie=# create table nt(id ``int``, info text);``CREATE TABLE`
```

r用户这次可以查询了

```sql
`yangjie``@young``:~ $ psql -U r -d yangjie``psql (``11.3``)``Type ``"help"` `for` `help.` `yangjie=> select * from tr ;``ERROR:  permission denied ``for` `table tr``yangjie=> select * from nt ;`` ``id | info``----+------``(``0` `rows)`
```

Use [psql](https://www.postgresql.org/docs/11/app-psql.html)'s `\dp` command to obtain information about existing privileges for tables and columns. For example:

```sql
`=> \dp mytable``                              ``Access privileges`` ``Schema |  Name   | Type  |   Access privileges   | Column access privileges``--------+---------+-------+-----------------------+--------------------------`` ``public` `| mytable | table | miriam=arwdDxt/miriam | col1:``                          ``: =r/miriam             :   miriam_rw=rw/miriam``                          ``: admin=arw/miriam       ``(``1` `row)`
```



The entries shown by `\dp` are interpreted thus:

```sql
`rolename=xxxx -- privileges granted to a role    -- 授予给一个角色的权限``        ``=xxxx -- privileges granted to PUBLIC    -- 授予给``public``的权限` `            ``r -- SELECT (``"read"``)``            ``w -- UPDATE (``"write"``)``            ``a -- INSERT (``"append"``)``            ``d -- DELETE``            ``D -- TRUNCATE``            ``x -- REFERENCES``            ``t -- TRIGGER``            ``X -- EXECUTE``            ``U -- USAGE``            ``C -- CREATE``            ``c -- CONNECT``            ``T -- TEMPORARY``      ``arwdDxt -- ALL PRIVILEGES (``for` `tables, varies ``for` `other objects)``            ``* -- grant option ``for` `preceding privilege` `        ``/yyyy -- role that granted ``this` `privilege    -- 授予该权限的角色`
```

看一下上面的栗子

```sql
`yangjie=# \dp tr``                              ``Access privileges`` ``Schema | Name | Type  |   Access privileges   | Column privileges | Policies``--------+------+-------+-----------------------+-------------------+----------`` ``public` `| tr   | table | yangjie=r/repmgr     +|                   |``        ``|      |       | repmgr=arwdDxt/repmgr |                   |``(``1` `row)` `yangjie=# \dp nt``                              ``Access privileges`` ``Schema | Name | Type  |   Access privileges   | Column privileges | Policies``--------+------+-------+-----------------------+-------------------+----------`` ``public` `| nt   | table | yangjie=r/repmgr     +|                   |``        ``|      |       | repmgr=arwdDxt/repmgr+|                   |``        ``|      |       | r=r/repmgr            |                   |``(``1` `row)`  `yangjie=# \dpp``                                      ``Access privileges`` ``Schema |        Name        | Type  |    Access privileges    | Column privileges | Polici``es``--------+--------------------+-------+-------------------------+-------------------+-------``---`` ``public` `| nt                 | table | yangjie=r/repmgr       +|                   |``        ``|                    |       | repmgr=arwdDxt/repmgr  +|                   |``        ``|                    |       | r=r/repmgr              |                   |`` ``public` `| test               | table | yangjie=arwdDxt/yangjie+|                   |``        ``|                    |       | r=r/yangjie             |                   |`` ``public` `| tr                 | table | yangjie=r/repmgr       +|                   |``        ``|                    |       | repmgr=arwdDxt/repmgr   |                   |``(``3` `rows)` `# nt 是alter ``default` `privileges ``for` `role repmgr in schema ``public` `grant select on tables to r;之后由repmgr创建的表，默认有访问权限``r=r/repmgr    -- repmgr 授予 r 读权限`  `# tr 是 grant SELECT on ALL tables in schema ``public` `to r; alter ``default` `privileges in schema ``public` `grant select on tables to r; （``for` `role 默认yangjie）``# 之后由repmgr建的表，所以r没有权限，yangjie=r/repmgr`
```

drop user 

删除default privilege要用赋权用户revoke之后才能删除用户

```sql
`yangjie=# drop user r;``ERROR:  role ``"r"` `cannot be dropped because some objects depend on it``DETAIL: ``privileges ``for` `default` `privileges on ``new` `relations belonging to role yangjie in schema ``public``privileges ``for` `default` `privileges on ``new` `sequences belonging to role yangjie in schema ``public``privileges ``for` `default` `privileges on ``new` `relations belonging to role repmgr in schema ``public``yangjie=# \ddp``            ``Default access privileges``  ``Owner  | Schema |   Type   | Access privileges``---------+--------+----------+-------------------`` ``repmgr  | ``public` `| table    | yangjie=r/repmgr +``         ``|        |          | r=r/repmgr`` ``yangjie | ``public` `| sequence | r=r/yangjie`` ``yangjie | ``public` `| table    | yangjie=r/yangjie+``         ``|        |          | r=r/yangjie``(``3` `rows)` `# user yangjie``yangjie=# alter ``default` `privileges in schema ``public` `revoke select ON tables FROM r;``yangjie=# alter ``default` `privileges in schema ``public` `revoke select ON sequences FROM r;`  `# user repmgr``yangjie=# alter ``default` `privileges in schema ``public` `revoke select ON tables FROM r;`  `yangjie=# drop user r;``DROP ROLE`
```

drop owned 删除当前数据库中指定角色之一所拥有的所有对象。授予当前数据库中对象的给定角色的任何权限也将被撤销。

```sql
`yangjie=# \ddp``          ``Default access privileges``  ``Owner  | Schema | Type  | Access privileges``---------+--------+-------+-------------------`` ``repmgr  | ``public` `| table | yangjie=r/repmgr`` ``yangjie | ``public` `| table | yangjie=r/yangjie+``         ``|        |       | r=arwdDxt/yangjie``(``2` `rows)` `yangjie=# drop owned BY r;``DROP OWNED``yangjie=# \ddp``          ``Default access privileges``  ``Owner  | Schema | Type  | Access privileges``---------+--------+-------+-------------------`` ``repmgr  | ``public` `| table | yangjie=r/repmgr`` ``yangjie | ``public` `| table | yangjie=r/yangjie``(``2` `rows)`
```