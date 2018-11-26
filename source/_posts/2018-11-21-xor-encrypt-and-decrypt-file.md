---
title: 使用异或xor加解密文件
date: 2018-11-21
categories: 
  - [C语言-Demo]
tags: 
  - C-Demo
---

[原文](https://blog.csdn.net/fdipzone/article/details/20413631)

```c
/*
 * XOR 加密/解密文件 
 * xor_encrypt.c
 */
 
#define TRUE 1
#define FALSE 0
 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <io.h>     // 如果在/usr/include/找不到,可以在/usr/include/sys/复制过去
 
 
// 输出信息
void msg_log(char *str);
 
// 判断文件是否存在
int file_exists(char *filename);

// 主函数
int main(int argc, char *argv[]){
 
    int keylen, index=0;
    char *source, *dest, *key, fBuffer[1], tBuffer[20], ckey;
 
    FILE *fSource, *fDest;
 
    source = argv[1]; // 原文件
    dest = argv[2];   // 目的文件
    key = argv[3];    // 加密字串
 
    // 检查参数
    if(source==NULL || dest==NULL || key==NULL){
        msg_log("param error\nusage:xor_encrypt source dest key\ne.g ./xor_encrypt o.txt d.txt 123456");
        exit(0);
    }
 
    // 判断原文件是否存在
    if(file_exists(source)==FALSE){
        sprintf(tBuffer,"%s not exists",source);
        msg_log(tBuffer);
        exit(0);
    }
 
    // 获取key长度
    keylen = strlen(key);
 
    fSource = fopen(source, "rb");
    fDest = fopen(dest, "wb");
 
    while(!feof(fSource)){
        
        fread(fBuffer, 1, 1, fSource);    // 读取1字节
        
        if(!feof(fSource)){
            ckey = key[index%keylen];     // 循环获取key
            *fBuffer = *fBuffer ^ ckey;   // xor encrypt
            fwrite(fBuffer, 1, 1, fDest); // 写入文件
            index ++;
        }
    
    }
 
    fclose(fSource);
    fclose(fDest);
 
    msg_log("success");
 
    exit(0);
}
 
//输出信息
void msg_log(char *str){
    printf("%s\n", str);
}
 
// 判断文件是否存在
int file_exists(char *filename){
    return (access(filename, 0)==0);
}
```

