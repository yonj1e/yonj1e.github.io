---
title: 添加语法
date: 2018-06-22 
categories: 
  - [PostgreSQL - Develop]
tags: 
  - Parse
  - PostgreSQL
---



#### 目的

实现闪回查询功能

实现闪回语法：

```sql
# select * from test flashback timestamp '2018-07-10 15:12:25';
```

#### 添加语法步骤

gram.y

		--- 定义语法，关键字

kwlist.h

		--- 标识关键字是保留字或非保留字

parsenodes.h

		--- 定义语法中结构体变量

nodes.h

		--- 定义结构体宏变量（用于识别语法调用函数）

analyze.c

		--- 根据宏变量，调用处理函数

flashback.h 

		--- 调用函数声明

flashback.c

		--- 调用函数的定义



#### 详细步骤如下：

1. 语法中关键字的添加

  (1) gram.y中，%token <keyword> 添加关键字FLASHBACK

  ```c
  /* ordinary key words in alphabetical order */
  %token <keyword> ABORT_P ABSOLUTE_P ACCESS ACTION ADD_P ADMIN AFTER
          AGGREGATE ALL ALSO ALTER ALWAYS ANALYSE ANALYZE AND ANY ARRAY AS ASC
          ASSERTION ASSIGNMENT ASYMMETRIC AT ATTACH ATTRIBUTE AUTHORIZATION
  
  		··· 
  
          FALSE_P FAMILY FETCH FILTER FIRST_P FLASHBACK FLOAT_P FOLLOWING FOR
          FORCE FOREIGN FORWARD FREEZE FROM FULL FUNCTION FUNCTIONS
  
  		···
  ```

  (2) gram.y文件的reserved_keyword段添加关键字FLASHBACK

  ```c
  /* Reserved keyword --- these keywords are usable only as a ColLabel.
   *
   * Keywords appear here if they could not be distinguished from variable,
   * type, or function names in some contexts.  Don't put things here unless
   * forced to.
   */
  reserved_keyword:
                            ALL
                          | ANALYSE
  						···
                          | FETCH
                          | FLASHBACK
                          | FOR
  						···
  ```

  (3) kwlist.h文件,添加语句：PG_KEYWORD("hash", HASH, RESERVED_KEYWORD)

  ```c
  ···
  PG_KEYWORD("first", FIRST_P, UNRESERVED_KEYWORD)
  PG_KEYWORD("flashback", FLASHBACK, RESERVED_KEYWORD)
  PG_KEYWORD("float", FLOAT_P, COL_NAME_KEYWORD)
  ···
  ```

2.  reserved_keyword -- 保留关键字，该关键字不能命名表名等

   unreserved_keyword -- 非保留关键字，可以命名表名



**解决语法冲突**

在gram.y中添加或修改语法时，可能会碰到冲突的问题。

执行下面命令：

```shell
bison -rall  ./src/backend/parser/gram.y
```

会在当前目录生成gram.output文件，可以根据此文件来确定冲突的地方在哪儿。

```c
Terminals unused in grammar

   DOT_DOT


State 1261 conflicts: 1 shift/reduce
State 2817 conflicts: 1 shift/reduce


Grammar

    0 $accept: stmtblock $end
```

跟踪1261可查看形成冲突的原因。