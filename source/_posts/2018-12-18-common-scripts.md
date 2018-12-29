---
title: Shell常用脚本
date: 2018-12-18 
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

var=`ls *\`date '+%Y%m%d'\`*|wc -l`
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

set timeout 300
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

#### 多行注释

```shell
#!/bin/bash

:<<EOF
# Multiline comment
# Multiline comment
# Multiline comment
EOF

echo a
```

#### sed 替换路径

```shell
#!/bin/bash

OLD_VARPATH="/opt/HighGo/db"
NEW_VARPATH="/work/hgdb/hgdb5"
OLD_VARPATHSED=$(echo ${OLD_VARPATH} |sed -e 's/\//\\\//g' )
NEW_VARPATHSED=$(echo ${NEW_VARPATH} |sed -e 's/\//\\\//g' )

sed -i "s/${OLD_VARPATHSED}/${NEW_VARPATHSED}/g" ./output.txt
```

