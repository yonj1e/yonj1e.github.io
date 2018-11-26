---
title: Git实践
date: 2018-04-02
categories: 
  - [Git]
tags: 
  - Git
---



### Git上多次commit合并成一个patch ### 

---

**1. 基于当前已经修改过的分支 `master` 创建新分支 `fix`  切换到分支 `fix`**

```java
git branch fix

git checkout gix
```

**2. `git log` 查看提交记录 假如当前提交记录为：**

```java
commit 5

commit 4

commit 3

commit 2

commit 1

commit first
```

**3. 自己新提交的有五次 使用 `git reset` 命令彻底回退到某个版本 这里回退到 `commit first`**

```java
git reset --hard first
```

**4. `git merge`**

```java
git merge master --squash
```

**5. 再编辑一下commit信息**

```java
git commit -m " new message "
```

**6. `git log` 查看合并好的提交**

**7. 制作补丁**

```java
git format-patch HEAD^
```



### git使用push或者pull命令每次都需要输入用户名和密码？

---

**1、使用git remote -v命令，显示如下：**

```java
[yangjie@young-1 test-pgagent]$ git remote -v
origin  https://gitee.com/yonj1e/pgagent-test.git (fetch)
origin  https://gitee.com/yonj1e/pgagent-test.git (push)
```

**2、原因已经找到是使用了`https`的方式来`push`了，改成`ssh`方式就可以解决问题；**

**3、输入命令：`git remote remove origin`，移除原来的连接；**

```java
[yangjie@young-1 test-pgagent]$ git remote remove origin
[yangjie@young-1 test-pgagent]$ git remote -v
```

**4、建立新的连接**

```java
[yangjie@young-1 test-pgagent]$ git remote add origin git@gitee.com:yonj1e/pgagent-test.git
[yangjie@young-1 test-pgagent]$ git remote -v
origin  git@gitee.com:yonj1e/pgagent-test.git (fetch)
origin  git@gitee.com:yonj1e/pgagent-test.git (push)
```

**5、`git push`**

```java
[yangjie@young-1 test-pgagent]$ git push -u origin master
Branch master set up to track remote branch master from origin.
Everything up-to-date
```
