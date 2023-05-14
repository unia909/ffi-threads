local ffi = require "ffi"
ffi.cdef [[
    void* luaL_newstate();
    void lua_close(void*);
    void luaL_openlibs(void*);
    int luaL_loadstring(void*, const char*);
    void lua_pushinteger(void*, int);
    void lua_settable(void*, int);
    int lua_rawgeti(void*, int, int);
    int lua_pcall(void*, int, int, int);

    typedef struct {
        void *L;
        void *H;
    } _lua_Thread;

    typedef unsigned short WORD;
    typedef unsigned int DWORD;

    typedef DWORD (*LPTHREAD_START_ROUTINE)(void*);

    DWORD GetCurrentThreadId();
    void* CreateThread(void*, size_t, LPTHREAD_START_ROUTINE, void*, DWORD, DWORD*);

    DWORD WaitForSingleObject(void*, DWORD);

    typedef struct {
        union {
          DWORD dwOemId;
          struct {
            WORD wProcessorArchitecture;
            WORD wReserved;
          } DUMMYSTRUCTNAME;
        } DUMMYUNIONNAME;
        DWORD     dwPageSize;
        void*     lpMinimumApplicationAddress;
        void*     lpMaximumApplicationAddress;
        DWORD*    dwActiveProcessorMask;
        DWORD     dwNumberOfProcessors;
        DWORD     dwProcessorType;
        DWORD     dwAllocationGranularity;
        WORD      wProcessorLevel;
        WORD      wProcessorRevision;
    } SYSTEM_INFO;
    void GetSystemInfo(SYSTEM_INFO*);
    void* VirtualAlloc(void*, size_t, DWORD, DWORD);
    int VirtualProtect(void*, size_t, DWORD, DWORD*);

    struct call_data {
        void (*f)(void*, int, int, int);
        void *param;
        void (*free)(void*);
    };

    void *malloc(size_t);
    void free(void*);
]]
local C = ffi.C
local thread_t = ffi.metatype("_lua_Thread", {
    __index = {
        free = function(self)
            C.lua_close(self.L)
        end,
        join = function(self)
            C.WaitForSingleObject(self.H, 0xFFFFFFFF)
        end
    }
})

--[[ Compiled with MinGW 64-bit
DWORD WINAPI foo(void *param) {
    struct call_data *call_data = (struct call_data*)param;
    call_data->f(call_data->param, 0, 0, 0);
    if (call_data->free) {
        call_data->free(param);
    }
    return 0;
}
]]
local x64_bootstrap = "\x55\x48\x89\xE5\x48\x83\xEC\x30\x48\x89\x4D\x10\x48\x8B\x45\x10\x48\x89\x45\xF8\x48\x8B\x45\xF8\x4C\x8B\x10\x48\x8B\x45\xF8\x48\x8B\x40\x08\x41\xB9\x00\x00\x00\x00\x41\xB8\x00\x00\x00\x00\xBA\x00\x00\x00\x00\x48\x89\xC1\x41\xFF\xD2\x48\x8B\x45\xF8\x48\x8B\x40\x10\x48\x85\xC0\x74\x0E\x48\x8B\x45\xF8\x48\x8B\x40\x10\x48\x8B\x4D\x10\xFF\xD0\xB8\x00\x00\x00\x00\xC9\xC3"

local function allocExecutableBuffer(data)
    local system_info = ffi.new("SYSTEM_INFO")
    C.GetSystemInfo(system_info)
    local page_size = system_info.dwPageSize

    local buffer = C.VirtualAlloc(nil, page_size, 0x00001000, 0x04)
    ffi.copy(buffer, data)
    local dummy = ffi.new("DWORD[1]")
    C.VirtualProtect(buffer, #data, 0x20, dummy)

    return buffer
end

local x64_bootstrap_executable = ffi.cast("LPTHREAD_START_ROUTINE", allocExecutableBuffer(x64_bootstrap))

return {
    new = function(code)
        local L = C.luaL_newstate()
        C.luaL_openlibs(L)
        C.lua_pushinteger(L, 0) -- index
        C.luaL_loadstring(L, code)
        C.lua_settable(L, -10002)
        return L
    end,
    run = function(L)
        C.lua_rawgeti(L, -10002, 0)
        local data = ffi.cast("struct call_data*", C.malloc(ffi.sizeof("struct call_data")))
        data[0].f = C.lua_pcall
        data[0].param = L
        data[0].free = C.free
        local hThread = C.CreateThread(nil, 0, x64_bootstrap_executable, data, 0, nil)

        return thread_t(L, hThread)
    end
}
