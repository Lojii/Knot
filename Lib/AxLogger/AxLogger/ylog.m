//
//  ylog.c
//  ylog
//
//  Created by peng(childhood@me.com) on 15-1-6.
//  Copyright (c) 2015年 peng(childhood@me.com). All rights reserved.
//

#include "ylog.h"
#include <string.h>
#include <time.h>
#include <mach/task_info.h>
#include <mach/task.h>
#include <mach/mach_init.h>
#include <stdarg.h>
void ylog_open(ylog_context *ctx,const char *logfile){
    ctx->file=fopen(logfile, "ab");
    if (ctx->file!=NULL) {
        ctx->isopen=1;
    }
}
void ylog_enable_console(ylog_context *ctx){
    ctx->enableconsole=1;
}
void ylog_set_level(ylog_context *ctx,ylog_level level){
    ctx->level=level;
}
void ylog_raw(ylog_context *ctx,const char *msg,uint32_t size){
    fwrite(msg, size, 1, ctx->file);
    fflush(ctx->file);
}
void ylog_log0(ylog_context *ctx,const char *line){
    if (line == NULL || ctx->file == NULL) {
        //fprintf(stderr,"fatt err############");
        return;
    }
    //size_t len = strlen(line);
    //fprintf(stderr,"fatt err############ %zu",len);
    //for
    fprintf(ctx->file, "%s\n",line);
    fflush(ctx->file);
    if (ctx->enableconsole) {
        fprintf(stderr, "%s\n",line);
        fflush(stderr);
    }
}
void ylog_log1(ylog_context *ctx,ylog_level level,char *line){
    if (level>=ctx->level) {
        ylog_log0(ctx, line);
    }
}
void ylog_log2(ylog_context *ctx,ylog_level level,char *format,...){
    va_list   arg_ptr;
    va_start(arg_ptr,format);
    char line[2*1024];
    bzero(line, sizeof(line));
    vsprintf(line, format, arg_ptr);
    va_end(arg_ptr);
    ylog_log1(ctx, level, line);
}
void ylog_log3(ylog_context *ctx,char *category,char *file,int line,ylog_level level,char *fmt,...){
    va_list   arg_ptr;
    va_start(arg_ptr,fmt);
    char msg[2*1024];
    bzero(msg, sizeof(msg));
    vsprintf(msg, fmt, arg_ptr);
    va_end(arg_ptr);
    char data[2*1024];
    sprintf(data, "%ld %s %s(%d) %s",time(NULL),category,file,line,msg);
    ylog_log1(ctx, level, data);
}
void ylog_close(ylog_context *ctx){
    fclose(ctx->file);
    ctx->isopen=0;
}
uint64_t reportMemoryUsed(void)
{
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t err = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vmInfo, &count);
    if (err == KERN_SUCCESS){
        uint64_t size = vmInfo.internal + vmInfo.compressed - vmInfo.purgeable_volatile_pmap;
        //NSLog(@"current memory use  %llu",sizt);
        return size;
    }else {
        return 0;
        //NSLog(@"error %d",err);
    }
    //return static_cast<size_t>(-1);
    
}

NSString* objectClassString(id obj)
{
    NSString *s =  NSStringFromClass([obj class]);
    NSArray *array = [s componentsSeparatedByString:@"."];
    return array.lastObject;
}
