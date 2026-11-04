// Persistent, application-scoped WFP filters. No global firewall or proxy changes.
#include <winsock2.h>
#include <windows.h>
#include <initguid.h>
#include <fwpmu.h>
#include <userenv.h>
#include <sddl.h>
#include <iostream>
#include <vector>
#include <string>
#include <stdexcept>
#pragma comment(lib, "fwpuclnt.lib")
#pragma comment(lib, "userenv.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "rpcrt4.lib")
static const GUID provider={0xb05c227a,0x728f,0x4837,{0xa2,0x17,0x5d,0x19,0xc3,0x51,0x14,0x6a}};
static const GUID sublayer={0x828e27bf,0xc822,0x43be,{0x92,0xa6,0x2e,0xa2,0x04,0xb6,0x93,0x7c}};
static void check(DWORD e) { if(e) throw std::runtime_error("WFP error " + std::to_string(e)); }
static void clear(HANDLE h) {
    HANDLE en=nullptr; check(FwpmFilterCreateEnumHandle0(h,nullptr,&en));
    std::vector<UINT64> ids;
    for(;;) { FWPM_FILTER0 **fs=nullptr; UINT32 n=0; DWORD e=FwpmFilterEnum0(h,en,128,&fs,&n);
        if(e){FwpmFilterDestroyEnumHandle0(h,en);check(e);} if(!n){FwpmFreeMemory0((void**)&fs);break;}
        for(UINT32 i=0;i<n;i++) if(fs[i]->providerKey && IsEqualGUID(*fs[i]->providerKey,provider)) ids.push_back(fs[i]->filterId); FwpmFreeMemory0((void**)&fs);
    } FwpmFilterDestroyEnumHandle0(h,en); for(auto id:ids) check(FwpmFilterDeleteById0(h,id));
}
static void add(HANDLE h,const FWPM_FILTER_CONDITION0& identity,UINT16 port,const std::wstring& label) {
    // OR is expressed with separate block filters. The only surviving connect is TCP 127.0.0.1:port.
    for(int rule=0;rule<4;rule++) {
        FWPM_FILTER_CONDITION0 c[2]={identity,{}};
        c[1].matchType=FWP_MATCH_NOT_EQUAL;
        if(rule==0) {c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_ADDRESS;c[1].conditionValue.type=FWP_UINT32;c[1].conditionValue.uint32=0x7f000001;}
        if(rule==1) {c[1].fieldKey=FWPM_CONDITION_IP_REMOTE_PORT;c[1].conditionValue.type=FWP_UINT16;c[1].conditionValue.uint16=port;}
        if(rule==2) {c[1].fieldKey=FWPM_CONDITION_IP_PROTOCOL;c[1].conditionValue.type=FWP_UINT8;c[1].conditionValue.uint8=IPPROTO_TCP;}
        FWPM_FILTER0 f={}; UuidCreate(&f.filterKey); f.displayData.name=const_cast<wchar_t*>(label.c_str());
        f.providerKey=const_cast<GUID*>(&provider); f.subLayerKey=sublayer;
        f.layerKey=rule==3?FWPM_LAYER_ALE_AUTH_CONNECT_V6:FWPM_LAYER_ALE_AUTH_CONNECT_V4;
        f.flags=FWPM_FILTER_FLAG_PERSISTENT; f.action.type=FWP_ACTION_BLOCK;
        f.weight.type=FWP_UINT8; f.weight.uint8=15;
        f.numFilterConditions=rule==3?1:2; f.filterCondition=c;
        UINT64 id=0;check(FwpmFilterAdd0(h,&f,nullptr,&id));
    }
}
int wmain(int argc,wchar_t** argv) {
    HANDLE h=nullptr;bool transaction=false;
    try {
        if(argc<2)throw std::runtime_error("Usage: install [--app path port | --package family port]... | remove | status");
        check(FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,nullptr,&h));
        std::wstring mode=argv[1];
        if(mode==L"status") {
            HANDLE en=nullptr;
            check(FwpmFilterCreateEnumHandle0(h,nullptr,&en));UINT32 total=0;
            for(;;){FWPM_FILTER0** fs=nullptr;UINT32 n=0;check(FwpmFilterEnum0(h,en,128,&fs,&n));for(UINT32 i=0;i<n;i++)if(fs[i]->providerKey && IsEqualGUID(*fs[i]->providerKey,provider))total++;FwpmFreeMemory0((void**)&fs);if(!n)break;}
            FwpmFilterDestroyEnumHandle0(h,en);std::cout<<"persistent_filters="<<total<<std::endl;
        } else {
            if(mode!=L"install"&&mode!=L"remove")throw std::runtime_error("Unknown action");
            if(mode==L"install"&&(argc<5||(argc-2)%3))throw std::runtime_error("Invalid targets");
            check(FwpmTransactionBegin0(h,0));transaction=true;
            if(mode==L"install") {
                FWPM_PROVIDER0 p={};p.providerKey=provider;p.flags=FWPM_PROVIDER_FLAG_PERSISTENT;p.displayData.name=const_cast<wchar_t*>(L"Strict Germany app isolation");
                DWORD e=FwpmProviderAdd0(h,&p,nullptr);if(e!=FWP_E_ALREADY_EXISTS)check(e);
                FWPM_SUBLAYER0 s={};s.subLayerKey=sublayer;s.providerKey=const_cast<GUID*>(&provider);s.flags=FWPM_SUBLAYER_FLAG_PERSISTENT;s.weight=0xffff;s.displayData.name=p.displayData.name;
                e=FwpmSubLayerAdd0(h,&s,nullptr);if(e!=FWP_E_ALREADY_EXISTS)check(e);
            }
            clear(h);
            if(mode==L"install")for(int i=2;i<argc;i+=3) {
                int pn=_wtoi(argv[i+2]);if(pn<1||pn>65535)throw std::runtime_error("Invalid port");
                FWPM_FILTER_CONDITION0 c={};c.matchType=FWP_MATCH_EQUAL;
                std::wstring kind=argv[i];
                if(kind==L"--app") {
                    FWP_BYTE_BLOB* blob=nullptr;check(FwpmGetAppIdFromFileName0(argv[i+1],&blob));
                    c.fieldKey=FWPM_CONDITION_ALE_APP_ID;c.conditionValue.type=FWP_BYTE_BLOB_TYPE;c.conditionValue.byteBlob=blob;
                    try{add(h,c,(UINT16)pn,argv[i+1]);}catch(...){FwpmFreeMemory0((void**)&blob);throw;}FwpmFreeMemory0((void**)&blob);
                }else if(kind==L"--package") {
                    PSID sid=nullptr;check(DeriveAppContainerSidFromAppContainerName(argv[i+1],&sid));
                    c.fieldKey=FWPM_CONDITION_ALE_PACKAGE_ID;c.conditionValue.type=FWP_SID;c.conditionValue.sid=(SID*)sid;
                    try{add(h,c,(UINT16)pn,argv[i+1]);}catch(...){FreeSid(sid);throw;}FreeSid(sid);
                }else throw std::runtime_error("Invalid identity");
            }
            if(mode==L"remove") {check(FwpmSubLayerDeleteByKey0(h,&sublayer));check(FwpmProviderDeleteByKey0(h,&provider));}
            check(FwpmTransactionCommit0(h));transaction=false;std::cout<<"Committed "<<(mode==L"install"?"isolation":"removal")<<std::endl;
        }
        FwpmEngineClose0(h);return 0;
    }catch(const std::exception& e){if(transaction)FwpmTransactionAbort0(h);if(h)FwpmEngineClose0(h);std::cerr<<e.what()<<std::endl;return 1;}
}
