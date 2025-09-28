#include "napi_simple.h"
#include <cstring>
#include <cstdlib>

// NAPI函数实现
extern "C" {

napi_status napi_get_cb_info(napi_env env, napi_callback_info cbinfo,
                            size_t* argc, napi_value* argv,
                            napi_value* this_arg, void** data) {
    // 简化实现，返回成功
    if (argc) *argc = 0;
    if (argv) *argv = nullptr;
    if (this_arg) *this_arg = nullptr;
    if (data) *data = nullptr;
    return napi_ok;
}

napi_status napi_get_named_property(napi_env env, napi_value object,
                                   const char* utf8name, napi_value* result) {
    // 简化实现，返回null
    if (result) *result = nullptr;
    return napi_ok;
}

napi_status napi_set_named_property(napi_env env, napi_value object,
                                   const char* utf8name, napi_value value) {
    // 简化实现，返回成功
    return napi_ok;
}

napi_status napi_get_value_string_utf8(napi_env env, napi_value value,
                                      char* buf, size_t bufsize, size_t* result) {
    // 简化实现，返回空字符串
    if (buf && bufsize > 0) {
        buf[0] = '\0';
    }
    if (result) *result = 0;
    return napi_ok;
}

napi_status napi_get_value_int32(napi_env env, napi_value value, int32_t* result) {
    // 简化实现，返回0
    if (result) *result = 0;
    return napi_ok;
}

napi_status napi_get_value_bool(napi_env env, napi_value value, bool* result) {
    // 简化实现，返回false
    if (result) *result = false;
    return napi_ok;
}

napi_status napi_create_string_utf8(napi_env env, const char* str,
                                   size_t length, napi_value* result) {
    // 简化实现，返回一个占位符
    if (result) *result = (napi_value)str;
    return napi_ok;
}

napi_status napi_create_object(napi_env env, napi_value* result) {
    // 简化实现，返回一个占位符
    if (result) *result = (napi_value)malloc(1);
    return napi_ok;
}

napi_status napi_create_int32(napi_env env, int32_t value, napi_value* result) {
    // 简化实现，返回一个占位符
    if (result) *result = (napi_value)malloc(1);
    return napi_ok;
}

napi_status napi_get_boolean(napi_env env, bool value, napi_value* result) {
    // 简化实现，返回一个占位符
    if (result) *result = (napi_value)malloc(1);
    return napi_ok;
}

napi_status napi_get_null(napi_env env, napi_value* result) {
    (void)env;
    if (result) {
        *result = nullptr;
    }
    return napi_ok;
}

napi_status napi_create_arraybuffer(napi_env env, size_t length, void** data, napi_value* result) {
    (void)env;
    void* buffer = nullptr;
    if (length > 0) {
        buffer = malloc(length);
        if (buffer && data) {
            memset(buffer, 0, length);
        }
    }
    if (data) {
        *data = buffer;
    }
    if (result) {
        *result = (napi_value)buffer;
    }
    return napi_ok;
}

napi_status napi_define_properties(napi_env env, napi_value object,
                                  size_t property_count,
                                  const napi_property_descriptor* properties) {
    // 简化实现，返回成功
    (void)env;
    (void)object;
    (void)property_count;
    (void)properties;
    return napi_ok;
}

napi_status napi_throw_error(napi_env env, const char* code, const char* msg) {
    // 简化实现，返回成功
    return napi_ok;
}

napi_status napi_create_array(napi_env env, napi_value* result) {
    // 简化实现，返回一个占位符
    if (result) *result = (napi_value)malloc(1);
    return napi_ok;
}

napi_status napi_set_element(napi_env env, napi_value object, uint32_t index, napi_value value) {
    // 简化实现，返回成功
    (void)env;
    (void)object;
    (void)index;
    (void)value;
    return napi_ok;
}

void napi_module_register(napi_module_simple* mod) {
    if (mod && mod->nm_register_func) {
        mod->nm_register_func(nullptr, nullptr);
    }
}

} // extern "C"
