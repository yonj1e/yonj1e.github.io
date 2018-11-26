---
title: 编译脚本
date: 2017-03-26 
categories: 
  - [Scripts]
tags: 
  - Configure
  - Scripts
---



源码编译PostgreSQL时，执行configure时可能会报错缺少相应的包。

Redhat/CentOS

```shell
#!/bin/bash   

yum install bison \
flex \
perl-ExtUtils-Embed -y \
readline-devel \
zlib-devel \
openssl-devel \
libxml2-devel \
libxslt-devel \
uuid-devel \
openldap-devel \
python-devel \
krb5-devel \
tcl-devel \
pam-devel \
gettext-devel \
gcc-c++ \
gtk2-devel \
automake \
```



Debian/Ubuntu

```shell
#!/bin/bash

apt-get install \
libreadline-dev \
zlib1g-dev \
libssl-dev \
libxml2-dev \
libxslt-dev \
libldap2-dev \
gettext libgettextpo-dev \
libperl-dev \
python-dev \
```
