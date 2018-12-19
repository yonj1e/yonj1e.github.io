---
title: Linux常用命令
date: 2018-11-18 
categories: 
  - [Linux]
tags: 
  - Linux
---



#### 批量杀死进程

```shell
# 批量杀死 postgres* 进程

# ps -ef | grep module-  
# 查找关键字包含module-的所有进程
# grep -v module-mxm
# 排除module-mxm的进程
# cut -c 9-15
# 截取第9至15字符（进程id）
# xargs kill -9
# 将截取的9-15字符（进程id）作为kill -9 后的参数
ps -ef | grep module- | grep -v module-mxm | cut -c 9-15 | xargs kill -9
ps -ef | grep aaa | grep -v grep | awk '{print "kill -9 " $2}' | sh
ps -ef | grep postgres | grep -v grep | cut -c 9-15 | xargs kill -9
```

#### 批量删除某后缀的文件

```shell
# 查看指定文件 *.orig
find . -name "*.orig"
find . -name "*.orig" | wc -l

# 批量删除指定后缀的文件
find . -name "*.orig" | xargs rm -rfv
find . -name '*.orig' -type f -print -exec rm -rf {} \;

# 删除一天之前的指定后缀文件
find . -ctime +1 -name "*.orig" -print | xargs rm -f
find . -ctime +1 -name "*.orig" -delete 
```





