---
title: 使用BenchmarkSQL测试PostgreSQL
date: 2018-08-25 
categories: 
  - [BenchmarkSQL]
  - [PostgreSQL - 最佳实践]
tags: 
  - BenchmarkSQL
  - PostgreSQL
---



BenchmarkSQL是对OLTP数据库主流测试标准TPC-C的开源实现。

目前最新版本为V5.0，该版本支持Firebird，Oracle和PostgreSQL数据库，测试结果详细信息存储在CSV文件中，并可以将结果转换为HTML报告。

项目地址：

- 下载地址：https://sourceforge.net/projects/benchmarksql/
- Git仓库：https://bitbucket.org/openscg/benchmarksql

#### 使用文档

我下载的是BenchmarkSQL5.0，其他版本对JDK的要求见各版本自己的 `HOW-TO-RUN.txt` 文件，以下是在PG上的运行步骤：

#### 基本要求：
JDK7

#### 在PG上创建benchmarksql用户和数据库，例如：

```sql
createuser -s bmsql -P		-- -P指定密码 bmsql
createdb bmsql -O bmsql
```

#### 使用ant对BenchmarkSQL源码进行编译：
首先如果环境中没有ant，需要先安装ant环境：

```shell
1、从http://ant.apache.org 上下载tar.gz版ant
2、复制到/usr下
3、tar -vxzf apahce-ant-1.9.2-bin.tar.gz
4、vi /etc/profile						# 修改系统配置文件
#set Ant enviroment
export ANT_HOME=/usr/apache-ant-1.9.2
export PATH=$PATH:$ANT_HOME/bin
5、source /etc/proifle   				# 立刻将配置生效
6、ant -version							# 测试ant是否生效
```

也可以使用 `yum install ant` 直接安装

切换到benchmarksql文件夹下，用ant编译程序：

```shell
$ cd benchmarksql
$  ant
Buildfile: /nas1/home/wieck/benchmarksql.git/build.xml
init:
[mkdir] Created dir: /home/wieck/benchmarksql/build
compile:
[javac] Compiling 11 source files to /home/wieck/benchmarksql/build
dist:
[mkdir] Created dir: /home/wieck/benchmarksql/dist
[jar] Building jar: /home/wieck/benchmarksql/dist/BenchmarkSQL-5.0.jar
BUILD SUCCESSFUL
Total time: 1 second
```

编译完成后，就可以使用该程序了。

#### 创建BenchmarkSQL配置文件：
切换到run路径下，复制一个props.pg文件，该文件是设置测试运行参数的文件，需要根据具体的测试要求进行修改：

```shell
$ cd run
$ cp props.pg my_postgres.properties
$ vi my_postgres.properties
```

配置文件重要参数如下：
1）warehouse：
BenchmarkSQL数据库每个warehouse大小大概是100MB，如果该参数设置为10，那整个数据库的大小大概在1000MB。

建议将数据库的大小设置为服务器物理内存的2-5倍，如果服务器内存为16GB，那么warehouse设置建议在328～819之间。
2）terminals：
terminals指的是并发连接数，建议设置为服务器CPU总线程数的2-6倍。如果服务器为双核16线程（单核8线程），那么建议配置在32～96之间。

#### 配置文件详解：

```shell
db=postgres    
# 数据库类型，postgres代表我们对PG数据库进行测试，不需要更改
driver=org.postgresql.Driver    
# 驱动，不需要更改
conn=jdbc:postgresql://localhost:5432/bmsql    
# PG数据库连接字符串，正常情况下，需要更改localhost为对应PG服务IP、5432位对应PG服务端口、postgres为对应测试数据库名
user=bmsql   
# 数据库用户名，通常建议用默认，这就需要我们提前在数据库中建立benchmarksql用户
password=bmsql   
# 如上用户密码

warehouses=1    
# 仓库数量，数量根据实际服务器内存配置，配置方法见第3步
loadWorkers=4    
# 用于在数据库中初始化数据的加载进程数量，默认为4，实际使用过程中可以根据实际情况调整，加载速度会随worker数量的增加而有所提升
terminals=1    
# 终端数，即并发客户端数量，通常设置为CPU线程总数的2～6倍
# 每个终端（terminal）运行的固定事务数量，例如：如果该值设置为10，意味着每个terminal运行10个事务，如果有32个终端，那整体运行320个事务后，测试结束。该参数配置为非0值时，下面的runMins参数必须设置为0
runTxnsPerTerminal=10
# 要测试的整体时间，单位为分钟，如果runMins设置为60，那么测试持续1小时候结束。该值设置为非0值时，runTxnsPerTerminal参数必须设置为0。这两个参数不能同时设置为正整数，如果设置其中一个，另一个必须为0，主要区别是runMins定义时间长度来控制测试时间；runTxnsPerTerminal定义事务总数来控制时间。
runMins=0
# 每分钟事务总数限制，该参数主要控制每分钟处理的事务数，事务数受terminals参数的影响，如果terminals数量大于limitTxnsPerMin值，意味着并发数大于每分钟事务总数，该参数会失效，想想也是如此，如果有1000个并发同时发起，那每分钟事务数设置为300就没意义了，上来就是1000个并发，所以要让该参数有效，可以设置数量大于并发数，或者让其失效，测试过程中目前采用的是默认300。
# 测试过程中的整体逻辑通过一个例子来说明：假如limitTxnsPerMin参数使用默认300，termnals终端数量设置为150并发，实际会计算一个值A=limitTxnsPerMin/terminals=2（此处需要注意，A为int类型，如果terminals的值大于limitTxnsPerMin，得到的A值必然为0，为0时该参数失效），此处记住A=2；接下来，在整个测试运行过程中，软件会记录一个事务的开始时间和结束时间，假设为B=2000毫秒；然后用60000（毫秒，代表1分钟）除以A得到一个值C=60000/2=30000，假如事务运行时间B<C，那么该事务执行完后，sleep C-B秒再开启下一个事务；假如B>C，意味着事务超过了预期时间，那么马上进行下一个事务。在本例子中，每分钟300个事务，设置了150个并发，每分钟执行2个并发，每个并发执行2秒钟完成，每个并发sleep 28秒，这样可以保证一分钟有两个并发，反推回来整体并发数为300/分钟。
limitTxnsPerMin=300
# 终端和仓库的绑定模式，设置为true时可以运行4.x兼容模式，意思为每个终端都有一个固定的仓库。设置为false时可以均匀的使用数据库整体配置。TPCC规定每个终端都必须有一个绑定的仓库，所以一般使用默认值true。
terminalWarehouseFixed=true
# 下面五个值的总和必须等于100，默认值为：45, 43, 4, 4 & 4 ，与TPC-C测试定义的比例一致，实际操作过程中，可以调整比重来适应各种场景。
newOrderWeight=45
paymentWeight=43
orderStatusWeight=4
deliveryWeight=4
stockLevelWeight=4
# 测试数据生成目录，默认无需修改，默认生成在run目录下面，名字形如my_result_xxxx的文件夹。
resultDirectory=my_result_%tY-%tm-%td_%tH%tM%tS
# 操作系统性能收集脚本，默认无需修改，需要操作系统具备有python环境
osCollectorScript=./misc/os_collector_linux.py
# 操作系统收集操作间隔，默认为1秒
osCollectorInterval=1
# 操作系统收集所对应的主机，如果对本机数据库进行测试，该参数保持注销即可，如果要对远程服务器进行测试，请填写用户名和主机名。
# osCollectorSSHAddr=user@dbhost
# 操作系统中被收集服务器的网卡名称和磁盘名称，例如：使用ifconfig查看操作系统网卡名称，找到测试所走的网卡，名称为enp1s0f0，那么下面网卡名设置为net_enp1s0f0（net_前缀固定）；使用df -h查看数据库数据目录，名称为（/dev/sdb                33T   18T   16T   54% /hgdata），那么下面磁盘名设置为blk_sdb（blk_前缀固定）
osCollectorDevices=net_eth0 blk_sda
```

#### 创建数据库表并加载数据：
执行 `runDatabaseBuild.sh` 脚本，脚本后跟上面编辑好的配置文件，例如：

```shell
$ ./runDatabaseBuild.sh my_postgres.properties
# ------------------------------------------------------------
# Loading SQL file ./sql.common/tableCreates.sql
# ------------------------------------------------------------
create table bmsql_config (
cfg_name    varchar(30) primary key,
cfg_value   varchar(50)
);
create table bmsql_warehouse (
w_id        integer   not null,
w_ytd       decimal(12,2),
[...]
Starting BenchmarkSQL LoadData
driver=org.postgresql.Driver
conn=jdbc:postgresql:# localhost:5432/benchmarksql
user=benchmarksql
password=***********
warehouses=30
loadWorkers=10
fileLocation (not defined)
csvNullValue (not defined - using default 'NULL')
Worker 000: Loading ITEM
Worker 001: Loading Warehouse      1
Worker 002: Loading Warehouse      2
Worker 003: Loading Warehouse      3
[...]
Worker 000: Loading Warehouse     30 done
Worker 008: Loading Warehouse     29 done
# ------------------------------------------------------------
# Loading SQL file ./sql.common/indexCreates.sql
# ------------------------------------------------------------
alter table bmsql_warehouse add constraint bmsql_warehouse_pkey
primary key (w_id);
alter table bmsql_district add constraint bmsql_district_pkey
primary key (d_w_id, d_id);
[...]
vacuum analyze;
```

#### 运行测试：
执行脚本 `runBenchmark.sh`，后面紧跟上面定义的配置文件作为参数，例如：

```shell
$ ./runBenchmark.sh my_postgres.properties
The benchmark should run for the number of configured concurrent
connections (terminals) and the duration or number of transactions.
The end result of the benchmark will be reported like this:
01:58:09,081 [Thread-1] INFO   jTPCC : Term-00,
01:58:09,082 [Thread-1] INFO   jTPCC : Term-00, Measured tpmC (NewOrders) = 179.55
01:58:09,082 [Thread-1] INFO   jTPCC : Term-00, Measured tpmTOTAL = 329.17
01:58:09,082 [Thread-1] INFO   jTPCC : Term-00, Session Start     = 2016-05-25 01:58:07
01:58:09,082 [Thread-1] INFO   jTPCC : Term-00, Session End       = 2016-05-25 01:58:09
01:58:09,082 [Thread-1] INFO   jTPCC : Term-00, Transaction Count = 10
```

至此整个测试流程完成。

#### 重新运行测试：
执行 `runDatabaseDestroy.sh` 脚本带配置文件可以将所有的数据和表都删除，然后再重新修改配置文件，重新运行 `runDatabaseBuild.sh` 和 `runBenchmark.sh` 脚本进行新一轮测试。

```shell
$ ./runDatabaseDestroy.sh my_postgres.properties
$ ./runDatabaseBuild.sh my_postgres.properties
```

#### 生成结果报告：
BenchmarkSQL测试会收集详细的性能指标，如果配置了操作系统参数收集，同样也会收集操作系统级别网卡和磁盘的性能指标，默认生成的数据在run/my_result_xx目录下。

生成的报告，可以通过脚本文件`generateReport.sh + my_result_xx` 生成带有图形的HTML文件。生成图形的脚本`generateReport.sh`要求操作系统环境中已经安装了R语言，R语言的安装在这里不赘述。

#### 日志：
如果运行过程中产生日志和错误，都会存储在run目录下，可以打开看是否有报错退出。