---
title: 添加系统表
date: 2017-10-27 
categories: 
  - [PostgreSQL - 开发笔记]
tags: 
  - System Catalogs
  - PostgreSQL
---




```shell
# Makefile for backend/catalog
#
# src/backend/catalog/Makefile
```
POSTGRES_BKI_SRCS 添加系统表名 pg_hba


```c
/*-------------------------------------------------------------------------
 *
 * pg_hba.h
 *
 * src/include/catalog/pg_hba.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_HBA_H
#define PG_HBA_H

#include "catalog/genbki.h"

/* ----------------
 *		pg_hba definition.  cpp turns this into
 *		typedef struct FormData_pg_hba
 * ----------------
 */
#define HbaRelationId	6666

CATALOG(pg_hba,6666) BKI_WITHOUT_OIDS
{
	text		hbatype;
	text		hbadbname;
	text		hbauser;
	text		hbaipmask;
	text		hbamethod;
	text		hbaoptions;
} FormData_pg_hba;

/* ----------------
 *		Form_pg_hba corresponds to a pointer to a tuple with
 *		the format of pg_hba relation.
 * ----------------
 */
typedef FormData_pg_hba *Form_pg_hba;

/* ----------------
 *		compiler constants for pg_hba
 * ----------------
 */
#define Natts_pg_hba					6
#define Anum_pg_hba_hbatype				1
#define Anum_pg_hba_hbadbname			2
#define Anum_pg_hba_hbauser				3
#define Anum_pg_hba_hbaipmask			4
#define Anum_pg_hba_hbamethod			5
#define Anum_pg_hba_hbaoptions			6

/* ----------------
 *		initial contents of pg_hba
 * ----------------
 */

#endif   /* PG_HBA_H */
```
