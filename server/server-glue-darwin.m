#import <Foundation/Foundation.h>

void wonder_playground_start_run_loop (void);
void wonder_playground_stop_run_loop (void);

static volatile BOOL wonder_playground_running = NO;

void
wonder_playground_start_run_loop (void)
{
  NSRunLoop * loop = [NSRunLoop mainRunLoop];

  wonder_playground_running = YES;
  while (wonder_playground_running && [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])
    ;
}

void
wonder_playground_stop_run_loop (void)
{
  wonder_playground_running = NO;
  CFRunLoopStop ([[NSRunLoop mainRunLoop] getCFRunLoop]);
}
