
为了安全的删除文件所写的shell脚本

## 功能介绍
- 安全删除文件到垃圾站
- 可进行已删除文件的恢复
- 可强制删除文件，不经过垃圾站
- 配合crontab可以实现自动清理垃圾站

## 安装
```shell
wget https://raw.githubusercontent.com/marigold233/srm/refs/heads/main/srm -O  $HOME/.local/bin/srm
```
## 配置（可选）
默认配置
```shell
$ srm -p
TRASH_DIR="$HOME/.trash"
TRASH_DIR_MAX_SIZE="2G"
MAX_FILE_SIZE_TO_TRASH="50M"
MAX_RETENTION_DAYS_IN_TRASH="30"
LOG_FILE="$HOME/.trash/trash.csv"
```
自定义配置
```shell
srm -p > $HOME/.config/srm/config
vim $HOME/.config/srm/config
```

## 使用帮助
```shell
$ srm -h

Usage: srm [OPTION]... [FILE]...
Safely removes file(s) by moving them to a trash bin.
  -p        print default config.
  -e        Empty the trash bin completely.
  -a        Auto clean trash files.
  -c DAYS   Clean trash files older than DAYS.
  -r NAME   Restore a file from trash. NAME can be a partial filename.
  -f FILE   Forcefully and permanently delete FILE (bypassed trash).
  -h        Show this help message.

If no options are given, specified FILEs are moved to the trash bin.

$ for i in {1..5}; do dd if=/dev/zero of="testfile_${i}.dat" bs=10M count=1; done
1+0 records in
1+0 records out
10485760 bytes (10 MB, 10 MiB) copied, 0.019335 s, 542 MB/s
1+0 records in
1+0 records out
10485760 bytes (10 MB, 10 MiB) copied, 0.0149303 s, 702 MB/s
1+0 records in
1+0 records out
10485760 bytes (10 MB, 10 MiB) copied, 0.0161827 s, 648 MB/s
1+0 records in
1+0 records out
10485760 bytes (10 MB, 10 MiB) copied, 0.0442724 s, 237 MB/s
1+0 records in
1+0 records out
10485760 bytes (10 MB, 10 MiB) copied, 0.0465792 s, 225 MB/s
$ ls
testfile_1.dat  testfile_2.dat  testfile_3.dat  testfile_4.dat  testfile_5.dat
$ srm *.dat
.....
$ ls
$ srm -r testfile
0) testfile_1.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
1) testfile_2.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
2) testfile_3.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
3) testfile_4.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
4) testfile_5.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:23)
Please enter the number of the file you want to restore: 1
timestamp=2025-07-21T16:06:58+08:00 level=INFO component=main pid=15629 message=Successfully restored '/home/capy/dir/testfile_2.dat'
$ ls
testfile_2.dat

$ srm -f testfile_2.dat 
Forcefully delete 1 item(s)...
$ srm -r testfile
0) testfile_1.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
1) testfile_3.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
2) testfile_4.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:22)
3) testfile_5.dat (from /home/capy/dir, trashed on 2025-07-21 16:06:23)
Please enter the number of the file you want to restore: 

$ srm -e
Are you sure you want to empty the Recycle Bin?[y/N]: y
timestamp=2025-07-21T16:08:28+08:00 level=INFO component=main pid=15879 message=Trash bin has been emptied successfully
$ srm -r testfile
timestamp=2025-07-21T16:08:36+08:00 level=ERROR component=main pid=15919 message=No files found to restore matching 'testfile'

$ ./srm -l
no    trash_file                                                   trashed_time             
--------------------------------------------------------------------------------------                                                             
1     /home/capy/project/srm/testfile_1.dat                        2025-07-23 09:49:45      
2     /home/capy/project/srm/testfile_2.dat                        2025-07-23 09:49:45      
3     /home/capy/project/srm/testfile_3.dat                        2025-07-23 09:49:45      
4     /home/capy/project/srm/testfile_4.dat                        2025-07-23 09:49:45      
5     /home/capy/project/srm/testfile_5.dat                        2025-07-23 09:49:45 
```
