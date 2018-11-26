---
title: PostgreSQL的COPY导入导出CSV
date: 2018-11-22
categories: 
  - [PostgreSQL - Usage]
tags: 
  - PostgreSQL
  - COPY
---

[原文](https://segmentfault.com/a/1190000008328676)

PostgreSQL 的 `COPY` 命令，它用来在文件和数据库之间复制数据，效率非常高，并且支持 CSV 。

#### 导出 CSV

以前做类似的事情都是用程序语言写，比如用程序读取数据库的数据，然后用 CSV 模块写入文件，当数据量大的时候还要控制不要一次读太多，比如一次读 5000 条，处理完再读 5000 条之类。

PostgreSQL 的 `COPY TO` 直接可以干这个事情，而且导出速度是非常快的。下面例子是把 `products` 表导出成 CSV ：

```sql
COPY products
TO '/path/to/output.csv'
WITH csv;
```

可以导出指定的属性：

```sql
COPY products (name, price)
TO '/path/to/output.csv'
WITH csv;
```

也可以配合查询语句，比如最常见的 `SELECT` ：

```sql
COPY (
  SELECT name, category_name
  FROM products
  LEFT JOIN categories ON categories.id = products.category_id
)
TO '/path/to/output.csv'
WITH csv;
```

#### 导入 CSV

跟上面的导出差不多，只是把 `TO` 换成 `FROM` ，举例：

```sql
COPY products
FROM '/path/to/input.csv'
WITH csv;
```

这个命令做导入是非常高效的，在开头那篇博客作者的测试中，`COPY` 只花了 `INSERT` 方案 1/3 的时间，而后者还用 prepare statement 优化过。

#### 总结

`COPY` 还有一些其他配置，比如把输入输出源指定成 STDIN/STDOUT 和 shell 命令，或者指定 CSV 的 header 等等。这里不再赘述。数据库也有很多细节可挖，有些简单却非常实用。合理使用能大大提高效率。

#### 参考资料

[PostgreSQL: COPY](https://www.postgresql.org/docs/current/static/sql-copy.html)