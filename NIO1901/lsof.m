//
//  lsof.m
//  NIO1901
//
//  Created by LiuJie on 2019/5/3.
//  Copyright © 2019 Lojii. All rights reserved.
//

#import "lsof.h"
#import <sys/types.h>
#import <fcntl.h>
#import <errno.h>
#import <sys/param.h>

@implementation lsof

+(void) getlsof
{
    int flags;
    int fd;
    char buf[MAXPATHLEN+1] ;
    int n = 1 ;
    
    for (fd = 0; fd < (int) FD_SETSIZE; fd++) {
        errno = 0;
        flags = fcntl(fd, F_GETFD, 0);
        if (flags == -1 && errno) {
            if (errno != EBADF) {
                return ;
            }
            else
            continue;
        }
        fcntl(fd , F_GETPATH, buf ) ;
//        NSLog( @"File Descriptor %d number %d in use for: %s",fd,n , buf ) ;
        ++n ;
    }
    NSLog(@"<<<<<<<<<<<<<<<文件数:%d>>>>>>>>>>>>>",n);
}

+(void)getlsofArray
{
    int flags;
    int fd;
    char buf[MAXPATHLEN+1] ;
    int n = 1 ;
    NSMutableString *result = [[NSMutableString alloc] init];
    for (fd = 0; fd < (int) FD_SETSIZE; fd++) {
        errno = 0;
        flags = fcntl(fd, F_GETFD, 0);
        if (flags == -1 && errno) {
            if (errno != EBADF) {
                return ;
            }
            else
                continue;
        }
        fcntl(fd , F_GETPATH, buf ) ;
        NSLog( @"fd:%d-%d:%s", fd, n, buf ) ;
//        [result appendString:[NSString stringWithFormat:@"fd:%d-%d: %s\n", fd, n, buf]];
        ++n ;
    }
//    NSLog(@"\n<<<<<<<<<<<<<<<打开文件数>>>>>>>>>>>>>\n%@<<<<<<<<<<<<<<<--End-->>>>>>>>>>>>>",result);
}
@end
