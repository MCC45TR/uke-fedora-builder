/* SPDX-License-Identifier: MIT
 * COPR-only test of the actual unmodified Fedora shared library. No TEE.
 * C is required for the upstream C11 atomic interface. No private values logged.
 */
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>
#include <cbor.h>
#include <stdarg.h>
#include <linux/tee.h>
#include <MinkCom.h>
#include <qcomtee_object_types.h>

static uint64_t credential_id;
static unsigned registration_calls, release_calls, callback_calls;

/* Kernel/secure-world double beneath the actual Fedora shared library and
 * unchanged MINK adapter. This catches both the rejected privileged-register
 * route and the incorrect zero output flags without duplicating the parser.
 */
static int fake_tee_call(int fd, unsigned long operation, ...)
{
    assert(fd >= 0);
    va_list ap;
    va_start(ap, operation);
    struct tee_ioctl_buf_data *buffer = va_arg(ap, struct tee_ioctl_buf_data *);
    va_end(ap);
    if (operation == TEE_IOC_OBJECT_INVOKE) {
        struct tee_ioctl_object_invoke_arg *request = (void *)(uintptr_t)buffer->buf_ptr;
        struct tee_ioctl_param *parameters = (void *)(request + 1);
        if (request->op == 2) {
            assert(++registration_calls == 1 && request->id == UINT64_MAX && request->num_params == 2);
            assert(buffer->buf_len == sizeof(*request) + 2 * sizeof(*parameters));
            assert(parameters[0].attr == 11 && parameters[0].a != UINT64_MAX && parameters[0].b == 2 && !parameters[0].c);
            credential_id = parameters[0].a;
            assert(parameters[1].attr == 12 && !parameters[1].a && !parameters[1].b && !parameters[1].c);
            parameters[1].a = 7;
            parameters[1].b = 1; /* TEE object, not a user callback. */
            request->ret = 0;
        } else {
            assert(++release_calls == 1 && request->op == 65535 && request->id == 7 && !request->num_params);
            request->ret = 0;
        }
        return 0;
    }
    assert(operation == TEE_IOC_SUPPL_RECV && ++callback_calls == 1);
    struct tee_iocl_supp_recv_arg *request = (void *)(uintptr_t)buffer->buf_ptr;
    struct tee_ioctl_param *parameters = (void *)(request + 1);
    request->func = 65535; /* Secure world releases the exported credential. */
    request->num_params = 1;
    parameters[0].a = credential_id;
    parameters[0].b = 1;
    parameters[0].c = 0;
    return 0;
}

static uint64_t milliseconds(void)
{
    struct timeval now;
    assert(gettimeofday(&now, NULL) == 0);
    return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_usec / 1000;
}

int main(void)
{
    /* Unexported callback: a public root shell needs no secure-world handle. */
    struct qcomtee_object root = {0}, *object = NULL;
    root.object_type = QCOMTEE_OBJECT_TYPE_ROOT;
    atomic_init(&root.refs, 1);
    const uint64_t before = milliseconds();
    assert(qcomtee_object_credentials_init(&root, &object) == 0);
    const uint64_t after = milliseconds();
    assert(object && object->root == &root && atomic_load(&root.refs) == 2);
    struct qcomtee_param length = {.attr = QCOMTEE_UBUF_OUTPUT};
    assert(object->ops->dispatch(object, 0, &length, 1) == QCOMTEE_OK);
    assert(length.ubuf.size == sizeof(size_t));
    const size_t size = *(size_t *)length.ubuf.addr;
    assert(size > 4 && size <= 4096);
    uint64_t offset = 0;
    struct qcomtee_param parameters[2] = {
        {.attr = QCOMTEE_UBUF_INPUT, .ubuf = {&offset, sizeof(offset)}},
        {.attr = QCOMTEE_UBUF_OUTPUT, .ubuf = {NULL, size}},
    };
    assert(object->ops->dispatch(object, 1, parameters, 2) == QCOMTEE_OK);
    assert(parameters[1].ubuf.size == size);
    struct cbor_load_result result;
    cbor_item_t *map = cbor_load(parameters[1].ubuf.addr, size, &result);
    assert(map && result.error.code == CBOR_ERR_NONE && result.read == size);
    assert(cbor_isa_map(map) && cbor_map_size(map) == 2);
    struct cbor_pair *pairs = cbor_map_handle(map);
    int uid_seen = 0, time_seen = 0;
    for (size_t i = 0; i < 2; ++i) {
        assert(cbor_isa_uint(pairs[i].key) && cbor_isa_uint(pairs[i].value));
        const uint64_t key = cbor_get_int(pairs[i].key);
        const uint64_t value = cbor_get_int(pairs[i].value);
        if (key == 1) { assert(value == getuid()); ++uid_seen; }
        else { assert(key == 6 && value >= before && value <= after); ++time_seen; }
    }
    assert(uid_seen == 1 && time_seen == 1);
    cbor_decref(&map);
    offset = size;
    assert(object->ops->dispatch(object, 1, parameters, 2) == QCOMTEE_ERROR_INVALID);
    assert(object->ops->dispatch(object, 0, &length, 0) == QCOMTEE_ERROR_INVALID);
    assert(object->ops->dispatch(object, 2, parameters, 2) == QCOMTEE_ERROR_INVALID);
    /* Never exported: release directly, without a kernel namespace operation. */
    object->ops->release(object);
    assert(atomic_fetch_sub(&root.refs, 1) == 2);

    struct qcomtee_object *real_root = qcomtee_object_root_init("/dev/null", fake_tee_call, NULL, NULL);
    assert(real_root);
    Object root_object = { .invoke = NULL, .context = real_root }, environment = Object_NULL;
    assert(MinkCom_getClientEnvObject(root_object, &environment) == Object_OK && !Object_isNull(environment));
    assert(Object_release(environment) == Object_OK);
    assert(qcomtee_object_process_one(real_root) == 0);
    assert(atomic_load(&real_root->refs) == 1);
    qcomtee_object_refs_dec(real_root);
    assert(registration_calls == 1 && release_calls == 1 && callback_calls == 1);
    puts("{\"original_fedora_credentials_checked\":true,\"actual_mink_and_fedora_marshalling\":true,\"ordinary_operation_2_nonnull_user_credential\":true,\"tee_output_flag_1\":true,\"exported_callback_released\":true,\"firmware_called\":false}");
    return 0;
}
