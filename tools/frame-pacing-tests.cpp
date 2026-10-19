#include "FramePacingStats.h"
#include <cassert>
#include <cstdio>
#include <limits>
#include <atomic>
#include <cstdlib>
#include <new>
static std::atomic<bool> track(false);
static std::atomic<unsigned> allocations(0);
void *operator new(std::size_t size) { if (track) ++allocations; void *p=std::malloc(size?size:1); if(!p)throw std::bad_alloc();return p; }
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete[](void *p) noexcept { std::free(p); }
void operator delete(void *p,std::size_t) noexcept { std::free(p); }
void operator delete[](void *p,std::size_t) noexcept { std::free(p); }
int main()
{
    qvvr::FramePacingStats stats;
    stats.Record(100,90,95,13.89,true);
    stats.Record(114,104,108,13.89,true);
    stats.Record(142,120,132,13.89,true);
    auto result=stats.ReadAndReset();
    assert(result.intervals==2&&result.longGaps==1&&result.averageMs==21&&result.maximumMs==28&&result.p95UpperMs==28);
    assert(result.maximumQueueAgeMs==12&&result.maximumCopySubmitMs==10&&result.periodMs==13.89);
    assert(stats.ReadAndReset().intervals==0);
    stats.Record(200,190,195,13.89,true);
    stats.Record(1000,990,995,13.89,false); // No gap across focus loss.
    stats.Record(2000,1990,1995,13.89,true);
    stats.Record(2014,2004,2009,13.89,true);
    result=stats.ReadAndReset(); assert(result.intervals==1&&result.longGaps==0&&result.maximumMs==14);
    for(int i=0;i<20;i++)stats.Record(100+i*10,90+i*10,95+i*10,13.89,true);
    stats.Record(330,320,325,13.89,true);
    result=stats.ReadAndReset(); assert(result.intervals==20&&result.p95UpperMs==10&&result.maximumMs==40&&result.longGaps==1);
    stats.Record(100,90,95,13.89,true); stats.Record(300,290,295,13.89,true);
    result=stats.ReadAndReset(); assert(result.p95UpperMs==200); // Overflow is conservative, not 127.5.
    stats.Record(std::numeric_limits<double>::quiet_NaN(),0,0,13.89,true);
    assert(stats.ReadAndReset().intervals==0);
    track=true;
    for(int i=0;i<1000;i++)stats.Record(100+i*14,90+i*14,95+i*14,13.89,true);
    result=stats.ReadAndReset();track=false;
    assert(allocations==0&&result.intervals==999&&result.longGaps==0);
    puts("XR cadence policies passed: focused submission intervals, p95 buckets, gaps, queue age, reset, invalid data and zero hot C++ allocations. Not a display/FPS benchmark.");
}
