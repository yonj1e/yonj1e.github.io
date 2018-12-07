---
title: 消除编译警告
date: 2017-12-25 
categories: 
  - [C]
tags: 
  - Make
  - C
---



```c
warning: unused variable ‘i’
warning: ‘datadir’ defined but not used
warning: variable ‘hash’ set but not used

说明：  函数中定义变量,但没有使用。
修改：  (1) 删除该变量 
        (2) 在合适的地方使用该变量
```

```c
warning: ‘opcintype’ may be used uninitialized in this function

说明：	还没赋值就使用该值
解决：	赋值
```

```c
warning: no previous prototype for ‘orafnp_session_timezone’

说明：  函数没有声明，只有定义
修改：  在相应的.h文件中添加该函数的声明
```

```c
warning: assignment from incompatible pointer type
warning: passing argument 1 of ‘hgdb_uuid_destroy’ discards ‘const’ qualifier from pointer target type

warning: assignment makes pointer from integer without a cast
warning: passing argument 2 of ‘transformExpressionList’ makes pointer from integer without a cast

说明：  类型不对
解决：  
```

```c
warning: implicit declaration of function ‘heap_deform_tuple’

说明：  (1)在你的.c文件中调用了函数func()，可是你并没有把声明这个函数的相应的.h文件包含进来。
        (2)有可能你在一个.c文件中定义了这个函数体，但并没有在.h中进行声明。

解决：  (1)你可以在调用这种函数的.c文件的一开始处加上：extern func()；
        (2)你可以在调用这种函数的.c文件中包含进声明了函数func()的头文件。
        (3)如果你在一个.c文件中定义了这个函数体，但并没有在.h中进行声明，不嫌麻烦的话，你也可以去生成一个.h文件，加上你的函数声明。
```

```c
warning: enumeration value ‘HGDB_UUID_RC_OK’ not handled in switch

说明：  switch没有default块。
解决：  添加
                default：
                        break;
```

```c
cwarning: the comparison will always evaluate as ‘false’ for the address of ‘hgdb_uuid_clone’ will never be NULL
```
