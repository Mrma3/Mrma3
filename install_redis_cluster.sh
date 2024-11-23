#!/bin/bash
  
# 进入/mnt目录  
cd /mnt/ || { echo "无法进入/mnt目录"; exit 1; }  
  

#跟着脚本启动的配置文件路径
config_path="/mnt/redis-7001.conf"

# 定义一些变量
REDIS_TAR="redis-6.2.12.tar.gz"  
REDIS_URL="http://download.redis.io/releases/$REDIS_TAR"  
REDIS_DIR="/mnt/redis"
REDIS_USER="redis"
PWD=/mnt
#需要变量命令的结果来做变量需要用（）而不是“” “”号是固定的他不会去运行这个命令或者用``
result=$(cat /etc/passwd | grep redis | awk -F: '{print $1}')
make_file="/mnt/redis-6.2.12/src/zmalloc.o"
redis_config_file="/mnt/redis/conf/cluster/7001/redis-7001.conf"
ip=`ip a | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1'`

# 下载必要软件（适用于CentOS 7.9）  
packages="wget curl jq net-tools telnet gcc tcl make openssl nfs-utils pcre pcre-devel perl-IPC-Cmd perl-Data-Dumper"
installed_packages=""
not_installed_packages=""
for package in $packages; do
        # if 语句会默认对比 上次命令的操作码 来判断执行then还是else 一般情况下不用特别写 if [ $? -eq 0] 这种
    if rpm -q $package >/dev/null 2>&1; then
        echo "$package 必须软件已经安装"
        installed_packages="$installed_packages $package"
    else
        echo “正在安装...”
        yum install -y $package
        not_installed_packages="$not_installed_packages $package"
    fi
done
echo "已安装的软件包：$installed_packages"
echo "本次安装的软件包：$not_installed_packages"  


# 检查redis压缩包是否已经存在  
if [ ! -f "$REDIS_TAR" ]; then  
    # 如果不存在，下载  
    echo "1.正在下载Redis压缩包..."  
    wget "$REDIS_URL"  
# $? 是用来检测上个上个命令推出状态的 -ne 是不等于的意思 这里就是不等于0
    if [ $? -ne 0 ]; then  
        echo "下载Redis压缩包失败"  
        exit 1  
    fi  
else  
    echo "Redis压缩包已存在"  
fi  
  
# 检查/mnt/redis目录是否已经存在  
# -d 用来检测目录 -f用来检测文件
if [ -d "$REDIS_DIR" ]; then  
    echo "redis文件夹已经存在"  
else  
    # 如果不存在，则创建redis目录并解压文件  
    echo "正在创建redis目录并解压文件..."  
    mkdir -p "$REDIS_DIR"  
    tar -zxf "$REDIS_TAR" -C /mnt/  
    if [ ! -d "$REDIS_DIR" ]; then  
        echo "解压后未找到redis目录"  
        exit 1  
    fi  
fi  
  


# 创建redis用户
if [[ "$result" == "redis" ]]; then
    echo "redis 用户已存在"
    chown -R $REDIS_USER:$REDIS_USER $REDIS_DIR /mnt/redis-6.2.12
    echo "3.已刷新redis权限"

else 
    useradd $REDIS_USER
# 检测是否创建成功
   if [ $? -ne 0 ]; then
       echo "创建 redis 用户失败"
       exit 1
   else
       chown -R $REDIS_USER:$REDIS_USER $REDIS_DIR /mnt/redis-6.2.12
       echo "3.redis用户创建成功并刷新权限"
   fi
fi


# 切换到 Redis 目录
cd /mnt/redis-6.2.12

# 检查编译文件是否存在
if [ -f "$make_file" ]; then
    echo "文件已经编译"
else
    # 使用完整的路径来执行 make
    echo "开始编译..."
    # 使用 sudo -u 切换用户，并重定向输出
    sudo -u "$REDIS_USER" /usr/bin/make > make.log 2>&1

    # 检查 make 是否成功
    if [ $? -eq 0 ]; then
        echo "编译成功"

        # 执行安装，并重定向输出
        echo "开始安装..."
        sudo -u "$REDIS_USER" /usr/bin/make install PREFIX=/mnt/redis > make_install.log 2>&1

        # 检查安装是否成功
        if [ $? -eq 0 ]; then
            echo "安装成功"
        else
            echo "安装失败，请检查 make_install.log 日志文件"
        fi
    else
        echo "编译失败，请检查 make.log 日志文件"
    fi
fi

cd /mnt/redis

if [ -f $redis_config_file ]; then
        echo "配置文件已经存在"
else
        sudo -u "$REDIS_USER" mkdir -pv /mnt/redis/conf/cluster/{7001,7002,7003}
        cd /mnt/redis/conf/cluster/7001
        echo "创建配置文件"
        cp $config_path .

        sudo -u "$REDIS_USER" sed 's@7001@7002@g' $redis_config_file > /mnt/redis/conf/cluster/7002/redis-7002.conf
        sudo -u "$REDIS_USER" sed 's@7001@7003@g' $redis_config_file > /mnt/redis/conf/cluster/7003/redis-7003.conf
fi

# 检查 Redis 是否已经运行在 7001 端口上
# ! 号是逻辑非操作符号，就是相当于 如果后面的命令成功了实际上表达式是错误的执行then 如果执行成功了就代表表达式是正确的执行else
if ! netstat -lnpt | grep -q ":7001"; then
    echo "没有启动redis，启动中..."
    sudo -u "$REDIS_USER" /mnt/redis/bin/redis-server /mnt/redis/conf/cluster/7001/redis-7001.conf
    sudo -u "$REDIS_USER" /mnt/redis/bin/redis-server /mnt/redis/conf/cluster/7002/redis-7002.conf
    sudo -u "$REDIS_USER" /mnt/redis/bin/redis-server /mnt/redis/conf/cluster/7003/redis-7003.conf
    echo "已经启动redis,正在创建集群"
    sudo -u "$REDIS_USER" /mnt/redis/bin/redis-cli --cluster  create $ip:7001 $ip:7002 $ip:7003 $ip:7001 $ip:7002 $ip:7003 --cluster-replicas 1 -a 123456
    echo "已经成功创建集群"
else
    echo "匹配到端口 7001，redis已启动"
fi

# 检查 Redis 集群是否已经创建
if ! netstat -lnpt | grep -q ":17001"; then
    echo "没有创建集群，创建中..."
    sleep 3 # 给Redis一些时间来完全启动
    sudo -u "$REDIS_USER" /mnt/redis/bin/redis-cli --cluster  create $ip:7001 $ip:7002 $ip:7003 $ip:7001 $ip:7002 $ip:7003 --cluster-replicas 1 -a 123456
else
    echo "匹配到端口 17001，已经创建集群"
fi

echo "/mnt/redis/bin/redis-cli -h 127.0.0.1 -p 7001 连接查看"
echo "auth 123456"
echo "cluster info"
