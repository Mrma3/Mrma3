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




###################################—————————————————————————— 分割线—————————————————————————————————####################################################################
# 下面这部分是配置文件需要单独复制出来放到/mnt 下面也就是该脚本运行的地方
# 将其命名为redis-7001.conf
###################################—————————————————————————— 分割线—————————————————————————————————####################################################################


#绑定主机IP，默认值为127.0.0.1?
bind 0.0.0.0
#设置密码
requirepass 123456
masterauth 123456
#要是配置里没有指定bind和密码,开启该参数后,redis只能本地进行访问,要是开启了密码和bind,可以开启.否则最好设置为no。
protected-mode yes
#端口号
port 7001
 
# 差异
tcp-keepalive 300
always-show-logo no
set-proc-title yes
proc-title-template "{title} {listen-addr} {server-mode}"
rdb-del-sync-files no
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-diskless-load disabled
repl-disable-tcp-nodelay no
replica-priority 100
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no
lazyfree-lazy-user-del yes
lazyfree-lazy-user-flush no
oom-score-adj no
oom-score-adj-values 0 200 800
disable-thp yes
aof-use-rdb-preamble yes
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
jemalloc-bg-thread yes
maxmemory 134217728
maxmemory-policy allkeys-random
 
#和内核参数/proc/sys/net/core/somaxconn值一样,redis默认511,而内核默认值128,高并发场景将其增大,内核参数也增大
tcp-backlog 1024
#客户端闲置多少秒后,断开连接为0,则服务端不会主动断开连接
timeout 0
#是否在后台执行
daemonize yes
supervised no
#redis进程文件
pidfile /mnt/redis/conf/cluster/7001/redis-7001.pid
#日志的级别,包括:debug,verbose,notice(默认适合生产环境),warn（只有非常重要的信息）
loglevel notice
#指定日志文件
logfile "/mnt/redis/conf/cluster/7001/redis-7001.log"
#数据库的数量,默认使用的数据库是DB 0,可以通过”SELECT “命令选择一个db
databases 16
# -------------------- SLOW LOG --------------------
#slog log是用来记录慢查询,执行时间比slowlog-log-slower-than大的请求记录到slowlog里面,1000000=1秒
slowlog-log-slower-than 1000
 
#慢查询日志长度。当一个新的命令被写进日志的时候，最老的那个记录会被删掉。这个长度没有限制。只要有足够的内存就行。你可以通过 SLOWLOG RESET 来释放内存。
slowlog-max-len 128
 
# -------------------- rdb Persistence --------------------
#当有一条Keys数据被改变时，900秒刷新到disk一次
save 900 1
#当有10条Keys数据被改变时，300秒刷新到disk一次
save 300 10
#当有1w条keys数据被改变时，60秒刷新到disk一次
save 60 10000
#当RDB持久化出现错误后,是否依然进行继续进行工作
stop-writes-on-bgsave-error yes
#使用压缩rdb文件,压缩需要一些cpu的消耗,不压缩需要更多的磁盘空间
rdbcompression yes
##是否校验rdb文件,校验会有大概10%的性能损耗
#rdbchecksum yes
##rdb文件的名称
dbfilename dump7001.rdb
 
##数据目录,数据库的写入会在这个目录。rdb、aof文件也会写在这个目录
dir /mnt/redis/conf/cluster/7001
# -------------------- AOF Persistence --------------------
#Append Only File是另一种持久化方式,可以提供更好的持久化特性.Redis会把每次写入的数据在接收后都写入 appendonly.aof 文件,每次启动时Redis都会先把这个文件的数据读入内存里,先忽略RDB文件
appendonly yes
#aof文件名
appendfilename "appendonly7001.aof"
#aof持久化策略,no表示不执行fsync,由操作系统保证数据同步到磁盘,速度最快.
#always表示每次写入都执行fsync,以保证数据同步到磁盘
#everysec表示每秒执行一次fsync,可能会导致丢失这1s数据
appendfsync everysec
#设置为yes表示rewrite期间对新写操作不fsync,暂时存在内存中,等rewrite完成后再写入,默认为no最安全,建议yes.Linux的默认fsync策略是30秒.可能丢失30秒数据.
no-appendfsync-on-rewrite no
#aof自动重写配置,前AOF文件大小是上次AOF文件大小的二倍（设置为100）时,自动启动新的日志重写过程
auto-aof-rewrite-percentage 100
#设置允许重写的最小aof文件大小，避免了达到约定百分比但尺寸仍然很小的情况还要重写
auto-aof-rewrite-min-size 64mb
#aof文件可能在尾部是不完整的,如果选择的是yes,当截断的aof文件被导入的时候,会自动发布一个log给客户端然后load
aof-load-truncated yes
# 如果达到最大时间限制（毫秒），redis会记个log，然后返回error。当一个脚本超过了最大时限。只有SCRIPT KILL和SHUTDOWN NOSAVE可以用。第一个可以杀没有调write命令的东西。要是已经调用了write，只能用第二个命令杀。
lua-time-limit 5000
 
# -------------------- REDIS CLUSTER --------------------
##集群开关，默认是不开启集群模式。
cluster-enabled yes
 
#集群配置文件的名称，每个节点都有一个集群相关的配置文件，持久化保存集群的信息。这个文件并不需要手动配置，这个配置文件有Redis生成并更新，每个Redis集群节点需要一个单独的配置文件，请确保与实例运行的系统中配置文件名称不冲突
cluster-config-file /mnt/redis/conf/cluster/7001/nodes-7001.conf
 
#节点互连超时的阀值。集群节点超时毫秒数
cluster-node-timeout 5000
 
#在进行故障转移的时候，全部slave都会请求申请为master，但是有些slave可能与master断开连接一段时间了，导致数据过于陈旧，这样的slave不应该被提升为master。
##如果节点超时时间为三十秒, 并且slave-validity-factor为10,假设默认的repl-ping-slave-period是10秒，即如果超过310秒slave将不会尝试进行故障转移
cluster-slave-validity-factor 10
 
#当某个主节点的从节点挂掉裸奔后,会从其他富余的主节点分配一个从节点过来，确保每个主节点都有至少一个从节点
#分配后仍然剩余migration barrier个从节点的主节点才会触发节点分配,默认是1,生产环境建议维持默认值,这样才能最大可能的确保集群稳定
cluster-migration-barrier 1
