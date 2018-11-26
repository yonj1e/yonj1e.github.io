---
title: 添加默认扩展
date: 2018-11-01 
categories: 
  - [PostgreSQL - Develop]
tags: 
  - PostgreSQL
---



plpgsql是PostgreSQL初始化时默认创建的扩展，我们在开发中，有时候写需要将自己的扩展也设置为默认创建。

以 [pg_audit](https://github.com/pgaudit/pgaudit) 为例

initdb时创建扩展

```c
/*
 * src/bin/initdb/initdb.c
 */

static void load_plpgsql(FILE *cmdfd);
static void load_pgaudit(FILE *cmdfd);

/*
 * load PL/pgSQL server-side language
 */
static void
load_plpgsql(FILE *cmdfd)
{
        PG_CMD_PUTS("CREATE EXTENSION plpgsql;\n\n");
}

/*
 * load pgaudit server-side Compatible packages
 */
static void
load_pgaudit(FILE *cmdfd)
{
    	/*
         * ISSUE: Created by default to information_schema
         */
        PG_CMD_PUTS("set search_path to public;\n\n");
        PG_CMD_PUTS("CREATE EXTENSION pgaudit;\n\n");
}

void
initialize_data_directory(void)
{
    ···
    load_plpgsql(cmdfd);
    load_pgaudit(cmdfd);
    ···
}
```

完成上面步骤，初始化时就会默认创建扩展了！

但是pgaudit会检查参数是否设置，可以注释或者在代码中先加载。

```c
if (!process_shared_preload_libraries_in_progress)
        ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                errmsg("pgaudit must be loaded via shared_preload_libraries")));
/*
 * src/backend/utils/init/miscinit.c
 */

/*
 * process any libraries that should be preloaded at postmaster start
 */
void
process_shared_preload_libraries(void)
{
        process_shared_preload_libraries_in_progress = true;

    	/* load pgaudit */
        load_file("pgaudit", false);

        load_libraries(shared_preload_libraries_string,
                                   "shared_preload_libraries",
                                   false);
        process_shared_preload_libraries_in_progress = false;
}
```

完成！