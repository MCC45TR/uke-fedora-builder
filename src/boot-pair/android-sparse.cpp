// SPDX-License-Identifier: MIT
// Host-only Android sparse codec. Every logical block is RAW or explicit FILL;
// never DONT_CARE. Accept only bounded regular files and new regular outputs.
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static constexpr uint32_t magic=0xed26ff3a, block=4096;
static constexpr uint16_t raw=0xcac1, fill=0xcac2;
static constexpr uint64_t limit=4ULL*1024*1024*1024;
static void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
static void io(int fd, void *buffer, size_t bytes, bool write) {
    auto *at=static_cast<unsigned char *>(buffer);
    while (bytes) {
        const auto count=write ? ::write(fd,at,bytes) : ::read(fd,at,bytes);
        if (count<0 && errno==EINTR) continue;
        require(count>0,"Short or failed I/O"); at+=count; bytes-=count;
    }
}
static uint32_t get(const unsigned char *p, unsigned bytes) {
    uint32_t value=0; for (unsigned i=0;i<bytes;++i) value|=uint32_t(p[i])<<(i*8); return value;
}
static void put(unsigned char *p,uint32_t value,unsigned bytes) {
    for (unsigned i=0;i<bytes;++i) p[i]=value>>(i*8);
}
static uint64_t size(int fd) {
    struct stat st {}; require(!fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_size>0 &&
                             uint64_t(st.st_size)<=limit,"Input must be a bounded regular file"); return st.st_size;
}
static void chunk(int out,uint16_t type,uint32_t blocks,uint32_t payload) {
    std::array<unsigned char,12> header {};
    put(header.data(),type,2); put(header.data()+4,blocks,4); put(header.data()+8,12+payload,4);
    io(out,header.data(),header.size(),true);
}
static uint32_t uniform(const std::array<unsigned char,block> &data,bool &same) {
    const uint32_t value=get(data.data(),4); same=true;
    for (size_t i=4;i<data.size();i+=4) if (get(data.data()+i,4)!=value) { same=false; break; }
    return value;
}
static void encode(int in,int out,uint64_t bytes) {
    require(bytes%block==0,"Raw image must be aligned to 4096 bytes");
    std::array<unsigned char,28> header {};
    put(header.data(),magic,4); put(header.data()+4,1,2); put(header.data()+8,28,2);
    put(header.data()+10,12,2); put(header.data()+12,block,4); put(header.data()+16,bytes/block,4);
    io(out,header.data(),header.size(),true);
    uint32_t count=0, run=0, pattern=0; bool fill_run=false;
    std::vector<unsigned char> payload; payload.reserve(1024*1024);
    auto flush=[&] {
        if (!run) return;
        chunk(out,fill_run?fill:raw,run,fill_run?4:payload.size());
        if (fill_run) { std::array<unsigned char,4> word {}; put(word.data(),pattern,4); io(out,word.data(),4,true); }
        else io(out,payload.data(),payload.size(),true);
        ++count; run=0; payload.clear();
    };
    for (uint64_t i=0;i<bytes/block;++i) {
        std::array<unsigned char,block> data {}; io(in,data.data(),data.size(),false);
        bool same; const auto value=uniform(data,same);
        if (run && (same!=fill_run || (same && value!=pattern) || (!same && payload.size()>=1024*1024))) flush();
        if (!run) { fill_run=same; pattern=value; }
        ++run; if (!same) payload.insert(payload.end(),data.begin(),data.end());
    }
    flush(); put(header.data()+20,count,4);
    require(lseek(out,0,SEEK_SET)==0,"Header seek failed"); io(out,header.data(),header.size(),true);
    std::cout << "Logical blocks=" << bytes/block << " chunks=" << count << " DONT_CARE=0\n";
}
static void decode(int in,int out,uint64_t input_bytes) {
    std::array<unsigned char,28> header {}; io(in,header.data(),header.size(),false);
    require(get(header.data(),4)==magic && get(header.data()+4,2)==1 && get(header.data()+6,2)==0 &&
            get(header.data()+8,2)==28 && get(header.data()+10,2)==12 &&
            get(header.data()+12,4)==block && get(header.data()+24,4)==0,"Unsupported sparse header");
    const uint64_t total=get(header.data()+16,4); const uint32_t chunks=get(header.data()+20,4);
    require(total && total*block<=limit && chunks && chunks<=total,"Invalid sparse bounds");
    uint64_t produced=0,consumed=28;
    for (uint32_t i=0;i<chunks;++i) {
        std::array<unsigned char,12> ch {}; io(in,ch.data(),ch.size(),false); consumed+=12;
        const auto type=get(ch.data(),2), blocks=get(ch.data()+4,4), stored=get(ch.data()+8,4);
        require(!get(ch.data()+2,2) && blocks && blocks<=total-produced,"Invalid sparse chunk bounds");
        const uint64_t bytes=uint64_t(blocks)*block;
        require((type==raw && bytes<=UINT32_MAX-12 && stored==bytes+12) ||
                (type==fill && stored==16),"Unsupported chunk, including DONT_CARE");
        require(stored<=input_bytes-consumed+12,"Truncated sparse chunk");
        std::array<unsigned char,block> data {};
        if (type==fill) { io(in,data.data(),4,false); consumed+=4; for (size_t at=4;at<block;at+=4) std::memcpy(data.data()+at,data.data(),4); }
        for (uint32_t j=0;j<blocks;++j) {
            if (type==raw) { io(in,data.data(),block,false); consumed+=block; }
            io(out,data.data(),block,true);
        }
        produced+=blocks;
    }
    require(produced==total && consumed==input_bytes,"Incomplete coverage or trailing data");
    std::cout << "Decoded bytes=" << produced*block << " complete logical coverage\n";
}
int main(int argc,char **argv) {
    int in=-1,out=-1; bool created=false;
    try {
        require(argc==4 && (std::string(argv[1])=="encode" || std::string(argv[1])=="decode"),
                "Usage: android-sparse encode|decode INPUT NEW_OUTPUT");
        in=open(argv[2],O_RDONLY|O_NOFOLLOW|O_CLOEXEC); require(in>=0,"Cannot open regular input");
        const auto bytes=size(in);
        out=open(argv[3],O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0644);
        require(out>=0,"Output must be new"); created=true;
        if (std::string(argv[1])=="encode") encode(in,out,bytes); else decode(in,out,bytes);
        require(!fsync(out),"Output flush failed"); close(out); close(in); return 0;
    } catch (const std::exception &error) {
        if (out>=0) close(out);
        if (in>=0) close(in);
        if (created) unlink(argv[3]);
        std::cerr << error.what() << '\n'; return 1;
    }
}
