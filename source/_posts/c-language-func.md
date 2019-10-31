---
title: PGSQL中的C语言函数
date: 2018-08-20
categories: 
  - [PostgreSQL]
tags: 
  - C-Language Functions
---

[官方文档](https://www.postgresql.org/docs/current/static/xfunc-c.html)

之前在做定时任务时，用到了C语言函数。

contrib目录下很多插件都是用到了c语言函数。

以扩展中使用c语言函数为例：

1. sql文件创建函数
2. c文件编写函数实现
3. 编译扩展生成.so文件，create extension时调用sql创建函数。

## 简单示例

```c
CREATE FUNCTION xfunc_add(bigint, bigint)
RETURNS bigint 
AS '$libdir/xfunc', 'xfunc_add'
LANGUAGE C STRICT;
```

$libdir/xfunc是生成的xfunc.so的路径，xfunc就是指xfunc.so文件，xfunc_add是C函数中的函数名

```c
//xfunc.c
#include "postgres.h"
#include "fmgr.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(xfunc_add);

Datum
xfunc_add(PG_FUNCTION_ARGS)
{
        int     a = 0;
        int     b = 0;
        int     c = 0;

        a = PG_GETARG_INT32(0);
        b = PG_GETARG_INT32(1);
        c = a + b;c
        PG_RETURN_INT32(c);
}
```

从PostgreSQL 8.2 开始，动态 载入的函数要求有一个magic block。要包括一个 magic block，在写上包括 头文件fmgr.h的语句之后，在该模块的源文件写上一下内容：

```c
#ifdef PG_MODULE_MAGIC

PG_MODULE_MAGIC;

#endif
```

如果代码不需要针对 8.2 之前的PostgreSQL 发行版进行编译，则#ifdef可以省略

## 官方示例worker_spi

这个示例实际是spi_conn和动态创建扩展的示例。

关于bgworker的介绍及开发可看这篇[博客](https://yonj1e.github.io/young/bgworker/)。

```c
/* src/test/modules/worker_spi/worker_spi--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION worker_spi" to load this file. \quit

CREATE FUNCTION worker_spi_launch(bigint)
RETURNS bigint STRICT
AS 'MODULE_PATHNAME'
LANGUAGE C;
#include "postgres.h"

/* These are always necessary for a bgworker */
#include "miscadmin.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/lwlock.h"
#include "storage/proc.h"
#include "storage/shmem.h"

/* these headers are used by this particular worker's code */
#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "pgstat.h"
#include "utils/builtins.h"
#include "utils/snapmgr.h"
#include "tcop/utility.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(worker_spi_launch);

/*
 * Dynamically launch an SPI worker.
 */
Datum
worker_spi_launch(PG_FUNCTION_ARGS)
{
	int32		i = PG_GETARG_INT32(0);
	BackgroundWorker worker;
	BackgroundWorkerHandle *handle;
	BgwHandleStatus status;
	pid_t		pid;

	memset(&worker, 0, sizeof(worker));
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS |
		BGWORKER_BACKEND_DATABASE_CONNECTION;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = BGW_NEVER_RESTART;
	sprintf(worker.bgw_library_name, "worker_spi");
	sprintf(worker.bgw_function_name, "worker_spi_main");
	snprintf(worker.bgw_name, BGW_MAXLEN, "worker %d", i);
	worker.bgw_main_arg = Int32GetDatum(i);
	/* set bgw_notify_pid so that we can use WaitForBackgroundWorkerStartup */
	worker.bgw_notify_pid = MyProcPid;

	if (!RegisterDynamicBackgroundWorker(&worker, &handle))
		PG_RETURN_NULL();

	status = WaitForBackgroundWorkerStartup(handle, &pid);

	if (status == BGWH_STOPPED)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_RESOURCES),
				 errmsg("could not start background process"),
				 errhint("More details may be available in the server log.")));
	if (status == BGWH_POSTMASTER_DIED)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_RESOURCES),
				 errmsg("cannot start background processes without postmaster"),
				 errhint("Kill all remaining database processes and restart the database.")));
	Assert(status == BGWH_STARTED);

	PG_RETURN_INT32(pid);
}
```
## 触发器函数

[Writing Trigger Functions in C](https://www.postgresql.org/docs/12/trigger-interface.html)

在规则表发生变化时，出发reload,j将数据更新到内存

```c
CREATE FUNCTION check_balance.cb_reload()
RETURNS trigger
AS '$libdir/check_balance', 'cb_reload'
LANGUAGE C ;

CREATE TRIGGER cb_rules_changes
after INSERT OR UPDATE OR DELETE
ON check_balance.rules FOR EACH ROW
EXECUTE PROCEDURE check_balance.cb_reload();
```

```c
PG_FUNCTION_INFO_V1(cb_reload);
Datum cb_reload(PG_FUNCTION_ARGS);

Datum
cb_reload(PG_FUNCTION_ARGS)
{
	TriggerData	*trigdata = (TriggerData *) fcinfo->context;
	TupleDesc	tupdesc;
	HeapTuple	rettuple;
	HeapTuple	newtuple;
	HeapTuple	trigtuple;
	HeapTuple	spi_tuple;
	SPITupleTable *spi_tuptable;
	TupleDesc spi_tupdesc;
	int		ret;
	int		ntup;
	int		i, j;
	StringInfoData	buf;
	char		**tup = NULL;
	ruledesc        *rules = NULL; 
	bool		isupdate, isinsert, isdelete;

	/* make sure it's called as a trigger at all */
	if (!CALLED_AS_TRIGGER(fcinfo))
		elog(ERROR, "trigf: not called by trigger manager");

	/* tuple to return to executor */
	if (TRIGGER_FIRED_BY_UPDATE(trigdata->tg_event))
		rettuple = trigdata->tg_newtuple;
	else
		rettuple = trigdata->tg_trigtuple;

	tupdesc = trigdata->tg_relation->rd_att;
	newtuple = trigdata->tg_newtuple;
	trigtuple = trigdata->tg_trigtuple;

	SPI_connect();

	isupdate = TRIGGER_FIRED_BY_UPDATE(trigdata->tg_event);
	isdelete = TRIGGER_FIRED_BY_DELETE(trigdata->tg_event);
	isinsert = TRIGGER_FIRED_BY_INSERT(trigdata->tg_event);
	
	initStringInfo(&buf);
	if (isupdate)
	{
		appendStringInfo(&buf, "select * from check_balance.rules where id != %s;", 
						SPI_getvalue(newtuple, tupdesc, 1));
	}

	if (isdelete)
	{
		appendStringInfo(&buf, "select * from check_balance.rules where id != %s;",
						SPI_getvalue(trigtuple, tupdesc, 1));
	}

	if (isinsert)
	{
		appendStringInfoString(&buf, "select * from check_balance.rules;");
	}

	ret = SPI_execute(buf.data, true, 0);
	pfree(buf.data);

	if (ret != SPI_OK_SELECT)
		elog(FATAL, "SPI_execute failed: error code %d", ret);

	ntup = SPI_processed;

	tup = (char**)palloc0(sizeof(char*) * tupdesc->natts);

	if (ntup != 0 && SPI_tuptable != NULL)
	{
		spi_tuptable = SPI_tuptable;
		spi_tupdesc = spi_tuptable->tupdesc;
		for (j = 0; j < ntup; j++)
		{
			rules = &rd[j];
			spi_tuple = spi_tuptable->vals[j];

			memset(&rd[j], 0, sizeof(ruledesc));

			for (i = 1; i <= spi_tupdesc->natts; i++)
			{
				tup[i-1] = SPI_getvalue(spi_tuple, spi_tupdesc, i);
			}

			memcpy(rules->username, pstrdup(tup[1]), strlen(pstrdup(tup[1])));
			memcpy(rules->startime, pstrdup(tup[2]), strlen(pstrdup(tup[2])));
			memcpy(rules->endtime, pstrdup(tup[3]), strlen(pstrdup(tup[3])));
			memcpy(rules->datname, pstrdup(tup[4]), strlen(pstrdup(tup[4])));
			memcpy(rules->relnsp, pstrdup(tup[5]), strlen(pstrdup(tup[5])));
			memcpy(rules->relname, pstrdup(tup[6]), strlen(pstrdup(tup[6])));
			memcpy(rules->cmdtype, pstrdup(tup[7]), strlen(pstrdup(tup[7])));

			*tup = NULL;

			elog(LOG, "w:%d,%s,%s,%s,%s,%s,%s,%s", 
				j,rules->username,rules->startime,rules->endtime,
				rules->datname,rules->relnsp,rules->relname,rules->cmdtype);
		}
	}

	/*
 	 * trigger record
 	 */ 
	if (isupdate || isinsert)
	{
		rules = &rd[ntup];

		memset(&rd[ntup], 0, sizeof(ruledesc));

		for (i = 1; i <= tupdesc->natts; i++)
		{
			if (isupdate)
				tup[i-1] = SPI_getvalue(newtuple, tupdesc, i);
			if (isinsert)
				tup[i-1] = SPI_getvalue(trigtuple, tupdesc, i);
		}

		memcpy(rules->username, pstrdup(tup[1]), strlen(pstrdup(tup[1])));
		memcpy(rules->startime, pstrdup(tup[2]), strlen(pstrdup(tup[2])));
		memcpy(rules->endtime, pstrdup(tup[3]), strlen(pstrdup(tup[3])));
		memcpy(rules->datname, pstrdup(tup[4]), strlen(pstrdup(tup[4])));
		memcpy(rules->relnsp, pstrdup(tup[5]), strlen(pstrdup(tup[5])));
		memcpy(rules->relname, pstrdup(tup[6]), strlen(pstrdup(tup[6])));
		memcpy(rules->cmdtype, pstrdup(tup[7]), strlen(pstrdup(tup[7])));

		*tup = NULL;

		elog(LOG, "w:%d,%s,%s,%s,%s,%s,%s,%s",
			ntup,rules->username,rules->startime,rules->endtime,
			rules->datname,rules->relnsp,rules->relname,rules->cmdtype);
	}

	SPI_finish();

	return PointerGetDatum(rettuple);
}
```

