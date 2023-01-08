//
//  pmain.h
//  NIO2022
//
//  Created by LiuJie on 2022/3/5.
//

#ifndef pmain_h
#define pmain_h


#endif /* pmain_h */

int man_run(int listenerCount,
          char *listenerList[],
          char *crtPath,
          char *keyPath,
          char *logsPath,
          char *rulePath,
          char *taskId);

int maintest(void);

int man_stop(void);

int man_reopen(int listenerCount, char *listenerList[]);

int cacert_generate(char *commonName,
                    char *countryCode,
                    int validDay, // 3650 十年
                    char *path);

int init_self_signed_cert(char *path); // 生成自签证书，用于检测CA是否被信任

// 对swift接口
long long unsigned int maxConnNum(char *taskId);
long long unsigned int initInBytes(char *taskId);
long long unsigned int initOutBytes(char *taskId);
// 保存更新task
void saveTask(char* task_id, long long unsigned int  conn_count, long long unsigned int  out_bytes, long long unsigned int  in_bytes, double start_time, double stop_time);
void updateTask(char* task_id, long long unsigned int  conn_count, long long unsigned int  out_bytes, long long unsigned int  in_bytes, double start_time, double stop_time,char* req_line);
// 解析http文件
int parse_http(char *file_path);


int testGetaddrinfo(void);
