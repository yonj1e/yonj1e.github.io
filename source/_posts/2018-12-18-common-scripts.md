---
title: Shell常用脚本
date: 2018-11-18 
categories: 
  - [Shell]
tags: 
  - Linux
  - Shell
---



#### 文件序号递增

```shell
#!/bin/bash
# ----------------------------------------
# 打包文件，并且序号递增
# ----------------------------------------

FILE=highgo
FILE_NAME=${FILE}.`date '+%Y%m%d'`.tar.gz

NEW_FILE=`ls -rt | sed '/sh/d' | tail -n1`
var=`echo ${NEW_FILE}|awk -F '-' '{print $2}'|awk -F '.' '{print $1}'`

let var+=1

tar zcvf ${FILE}.`date '+%Y%m%d'`-${var}.tar.gz ${FILE}

#./scp.sh ${FILE}.`date '+%Y%m%d'`-${var}.tar.gz yangjie young-90 /work/release
```

#### expect自动输入密码

```shell
#!/usr/bin/expect
# ----------------------------------------
# 使用expect来完成scp时无需输入密码
# ----------------------------------------

set timeout 10
set host [lindex $argv 0]
set username [lindex $argv 1]
set password [lindex $argv 2]
set src_file [lindex $argv 3]
set dest_file [lindex $argv 4]

spawn scp $src_file $username@$host:$dest_file
    expect {
        "(yes/no)?"
        {
        	send "yes\n"
        	expect "*assword:" { send "$password\n"}
        }
        "*assword:"
        {
        	send "$password\n"
        }
    }
expect "100%"
expect eof
```

#### 判断文件夹是否存在

```shell
!/bin/bash

if [ ! -d testmkdir ];
then
  mkdir testmkdir
else
  echo dir exist
fi
```

#### 脚本报错立即退出

```shell
#!/bin/bash

set -o errexit
```

