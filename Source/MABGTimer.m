//
//  MABGTimer.m
//  BackgroundTimer
//
//  Created by Michael Ash on 6/23/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "MABGTimer.h"

@import MachO;
@import ObjectiveC;

@interface MABGTimer ()
{
    __weak id _obj;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    MABGTimerBehavior _behavior;
    NSTimeInterval _nextFireTime;
}
@end

@implementation MABGTimer
@synthesize obj = _obj;
@synthesize queue = _queue;

- (id)initWithObject: (id)obj
{
    return [self initWithObject: obj behavior: MABGTimerCoalesce queueLabel:"com.mikeash.MABGTimer"];
}

- (id)initWithObject: (id)obj behavior: (MABGTimerBehavior)behavior queueLabel:(char const *)queueLabel
{
    if((self = [super init]))
    {
        _obj = obj;
        _behavior = behavior;
        _queue = dispatch_queue_create(queueLabel, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)_cancel
{
    if (_timer)
    {
        dispatch_source_cancel(_timer);
        _timer = NULL;
    }
}    

- (void)_finalize
{
    [self _cancel];
    _queue = nil;
}

- (void)finalize
{
    [self _finalize];
    [super finalize];
}

- (void)dealloc
{
    [self _finalize];
#if !__has_feature(objc_arc) 
    [super dealloc];
#endif
}

- (void)setTargetQueue: (dispatch_queue_t)target
{
    dispatch_set_target_queue(_queue, target);
}

- (NSTimeInterval)_now
{
    static mach_timebase_info_data_t info;
		static dispatch_once_t pred;
		dispatch_once(&pred, ^{
			mach_timebase_info(&info);
		});
		
		NSTimeInterval t = mach_absolute_time();
		t *= info.numer;
		t /= info.denom;
		return t / NSEC_PER_SEC;
}

- (void)afterDelay: (NSTimeInterval)delay do: (void (^)(id self))block
{
    NSTimeInterval requestTime = [self _now];
    
    [self performWhileLocked: ^{

        // adjust delay to take into account time elapsed between the method call and execution of this block
        NSTimeInterval now = [self _now];
        NSTimeInterval adjustedDelay = delay - (now - requestTime);
        if (adjustedDelay < 0.0)
            adjustedDelay = 0.0;

        BOOL hasTimer = _timer != nil;
        
        BOOL shouldProceed = NO;
        if (!hasTimer)
            shouldProceed = YES;
        else if (_behavior == MABGTimerDelay)
            shouldProceed = YES;
        else if (_behavior == MABGTimerCoalesce && [self _now] + adjustedDelay < _nextFireTime)
            shouldProceed = YES;
        
        if(shouldProceed)
        {
            if (!hasTimer)
                _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
            
            dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, adjustedDelay * NSEC_PER_SEC), 0, 0);
            _nextFireTime = [self _now] + adjustedDelay;
            dispatch_source_set_event_handler(_timer, ^{
                block(_obj);
                [self _cancel];
            });
            if(!hasTimer)
                dispatch_resume(_timer);
        }
    }];
}

- (void)performWhileLocked: (dispatch_block_t)block
{
    if (_queue)
        dispatch_sync(_queue, block);
}

- (void)cancel
{
    [self performWhileLocked: ^{
        [self _cancel];
    }];
}

@end
