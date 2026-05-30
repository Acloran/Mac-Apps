#include "CMetrics.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <sys/syscall.h>
#include <unistd.h>

int32_t ResourceBarMemoryFreeLevel(void) {
    int level = -1;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    long result = syscall(SYS_memorystatus_get_level, &level);
#pragma clang diagnostic pop

    if (result != 0 || level < 0 || level > 100) {
        return -1;
    }

    return (int32_t)level;
}

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyDataVers;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyDataKeyInfo;

typedef uint8_t SMCBytes[32];

typedef struct {
    uint32_t key;
    SMCKeyDataVers vers;
    SMCKeyDataPLimit pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    SMCBytes bytes;
} SMCKeyData;

static io_connect_t ResourceBarSMCConnection = IO_OBJECT_NULL;

static uint32_t ResourceBarSMCKey(const char *key) {
    uint32_t value = 0;
    for (int index = 0; index < 4; index += 1) {
        value |= ((uint32_t)(uint8_t)key[index] << (24 - 8 * index));
    }

    return value;
}

static int ResourceBarOpenSMC(void) {
    if (ResourceBarSMCConnection != IO_OBJECT_NULL) {
        return 1;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) {
        return 0;
    }

    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &ResourceBarSMCConnection);
    IOObjectRelease(service);

    if (result != KERN_SUCCESS) {
        ResourceBarSMCConnection = IO_OBJECT_NULL;
        return 0;
    }

    return 1;
}

static kern_return_t ResourceBarSMCCall(SMCKeyData *input, SMCKeyData *output) {
    size_t outputSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(
        ResourceBarSMCConnection,
        2,
        input,
        sizeof(SMCKeyData),
        output,
        &outputSize
    );
}

static int ResourceBarReadSMCKey(const char *key, SMCKeyData *output) {
    if (!ResourceBarOpenSMC()) {
        return 0;
    }

    SMCKeyData input = {0};
    SMCKeyData info = {0};
    input.key = ResourceBarSMCKey(key);
    input.data8 = 9;

    if (ResourceBarSMCCall(&input, &info) != KERN_SUCCESS || info.result != 0) {
        return 0;
    }

    input = (SMCKeyData){0};
    input.key = ResourceBarSMCKey(key);
    input.keyInfo.dataSize = info.keyInfo.dataSize;
    input.data8 = 5;

    if (ResourceBarSMCCall(&input, output) != KERN_SUCCESS || output->result != 0) {
        return 0;
    }

    output->keyInfo = info.keyInfo;
    return 1;
}

static double ResourceBarSMCFloat(const SMCKeyData *value) {
    float result = 0;
    __builtin_memcpy(&result, value->bytes, sizeof(result));
    return result;
}

static double ResourceBarSMCFPE2(const SMCKeyData *value) {
    uint16_t raw = ((uint16_t)value->bytes[0] << 8) | value->bytes[1];
    return raw / 4.0;
}

static double ResourceBarSMCSP78(const SMCKeyData *value) {
    int16_t raw = (int16_t)(((uint16_t)value->bytes[0] << 8) | value->bytes[1]);
    return raw / 256.0;
}

double ResourceBarSMCTemperature(const char *smcKey) {
    if (smcKey == 0 || smcKey[0] == 0 || smcKey[1] == 0 || smcKey[2] == 0 || smcKey[3] == 0) {
        return -273.15;
    }

    SMCKeyData value = {0};
    if (!ResourceBarReadSMCKey(smcKey, &value)) {
        return -273.15;
    }

    if (value.keyInfo.dataType == ResourceBarSMCKey("flt ")) {
        return ResourceBarSMCFloat(&value);
    }

    if (value.keyInfo.dataType == ResourceBarSMCKey("sp78")) {
        return ResourceBarSMCSP78(&value);
    }

    return -273.15;
}

int32_t ResourceBarFanCount(void) {
    SMCKeyData value = {0};
    if (!ResourceBarReadSMCKey("FNum", &value)) {
        return -1;
    }

    return value.bytes[0];
}

double ResourceBarFanRPM(int32_t fanIndex) {
    if (fanIndex < 0 || fanIndex > 9) {
        return -1;
    }

    char key[] = {'F', (char)('0' + fanIndex), 'A', 'c', '\0'};
    SMCKeyData value = {0};
    if (!ResourceBarReadSMCKey(key, &value)) {
        return -1;
    }

    if (value.keyInfo.dataType == ResourceBarSMCKey("flt ")) {
        return ResourceBarSMCFloat(&value);
    }

    if (value.keyInfo.dataType == ResourceBarSMCKey("fpe2")) {
        return ResourceBarSMCFPE2(&value);
    }

    return -1;
}

uint32_t ResourceBarDisplayFramebufferService(uint32_t displayID) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (uint32_t)CGDisplayIOServicePort((CGDirectDisplayID)displayID);
#pragma clang diagnostic pop
}

int32_t ResourceBarDisplayModePixelEncoding(const void *mode, char *buffer, uint32_t bufferLength) {
    if (mode == 0 || buffer == 0 || bufferLength == 0) {
        return 0;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFStringRef pixelEncoding = CGDisplayModeCopyPixelEncoding((CGDisplayModeRef)mode);
#pragma clang diagnostic pop

    if (pixelEncoding == 0) {
        return 0;
    }

    Boolean copied = CFStringGetCString(pixelEncoding, buffer, bufferLength, kCFStringEncodingUTF8);
    CFRelease(pixelEncoding);

    return copied ? 1 : 0;
}

int32_t ResourceBarDisplayGetBrightness(uint32_t framebuffer, float *value) {
    if (framebuffer == IO_OBJECT_NULL || value == 0) {
        return 0;
    }

    io_service_t display = IODisplayForFramebuffer((io_service_t)framebuffer, kNilOptions);
    if (display == IO_OBJECT_NULL) {
        return 0;
    }

    IOReturn result = IODisplayGetFloatParameter(
        display,
        kNilOptions,
        CFSTR(kIODisplayBrightnessKey),
        value
    );

    return result == kIOReturnSuccess ? 1 : 0;
}

int32_t ResourceBarDisplaySetBrightness(uint32_t framebuffer, float value) {
    if (framebuffer == IO_OBJECT_NULL) {
        return 0;
    }

    io_service_t display = IODisplayForFramebuffer((io_service_t)framebuffer, kNilOptions);
    if (display == IO_OBJECT_NULL) {
        return 0;
    }

    IOReturn result = IODisplaySetFloatParameter(
        display,
        kNilOptions,
        CFSTR(kIODisplayBrightnessKey),
        value
    );

    if (result == kIOReturnSuccess) {
        IODisplayCommitParameters(display, kNilOptions);
        return 1;
    }

    return 0;
}

typedef int (*ResourceBarDDCOperation)(IOI2CConnectRef connect, void *context);

static uint64_t ResourceBarNanosecondsToAbsolute(uint64_t nanoseconds) {
    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }

    if (timebase.numer == 0) {
        return nanoseconds;
    }

    return nanoseconds * timebase.denom / timebase.numer;
}

static uint8_t ResourceBarDDCChecksum(uint8_t address, const uint8_t *bytes, size_t length) {
    uint8_t checksum = address;
    for (size_t index = 0; index < length; index += 1) {
        checksum ^= bytes[index];
    }

    return checksum;
}

static int ResourceBarDDCWithFramebuffer(uint32_t framebuffer, ResourceBarDDCOperation operation, void *context) {
    if (framebuffer == IO_OBJECT_NULL || operation == 0) {
        return 0;
    }

    IOItemCount interfaceCount = 0;
    if (IOFBGetI2CInterfaceCount((io_service_t)framebuffer, &interfaceCount) != kIOReturnSuccess) {
        return 0;
    }

    for (IOOptionBits bus = 0; bus < interfaceCount; bus += 1) {
        io_service_t interface = IO_OBJECT_NULL;
        IOReturn copyResult = IOFBCopyI2CInterfaceForBus((io_service_t)framebuffer, bus, &interface);
        if (copyResult != kIOReturnSuccess || interface == IO_OBJECT_NULL) {
            continue;
        }

        IOI2CConnectRef connect = 0;
        IOReturn openResult = IOI2CInterfaceOpen(interface, kNilOptions, &connect);
        IOObjectRelease(interface);

        if (openResult != kIOReturnSuccess || connect == 0) {
            continue;
        }

        int operationResult = operation(connect, context);
        IOI2CInterfaceClose(connect, kNilOptions);

        if (operationResult) {
            return 1;
        }
    }

    return 0;
}

typedef struct {
    uint8_t control;
    uint16_t current;
    uint16_t maximum;
} ResourceBarDDCGetContext;

static int ResourceBarDDCGetOperation(IOI2CConnectRef connect, void *rawContext) {
    ResourceBarDDCGetContext *context = (ResourceBarDDCGetContext *)rawContext;
    uint8_t send[5] = {0x51, 0x82, 0x01, context->control, 0x00};
    send[4] = ResourceBarDDCChecksum(0x6E, send, 4);

    uint8_t reply[16] = {0};
    IOI2CRequest request = {0};
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.replyTransactionType = kIOI2CDDCciReplyTransactionType;
    request.sendAddress = 0x6E;
    request.replyAddress = 0x6F;
    request.minReplyDelay = ResourceBarNanosecondsToAbsolute(50 * 1000 * 1000);
    request.sendBuffer = (vm_address_t)(uintptr_t)send;
    request.sendBytes = sizeof(send);
    request.replyBuffer = (vm_address_t)(uintptr_t)reply;
    request.replyBytes = sizeof(reply);

    IOReturn result = IOI2CSendRequest(connect, kNilOptions, &request);
    if (result != kIOReturnSuccess || request.result != kIOReturnSuccess) {
        return 0;
    }

    uint32_t replyLength = request.replyBytes;
    if (replyLength > sizeof(reply)) {
        replyLength = sizeof(reply);
    }

    for (uint32_t index = 0; index + 10 < replyLength; index += 1) {
        uint8_t lengthByte = reply[index + 1];
        if (reply[index] != 0x6E || (lengthByte & 0x80) == 0 || reply[index + 2] != 0x02) {
            continue;
        }

        if (reply[index + 3] != 0x00 || reply[index + 4] != context->control) {
            continue;
        }

        context->maximum = ((uint16_t)reply[index + 6] << 8) | reply[index + 7];
        context->current = ((uint16_t)reply[index + 8] << 8) | reply[index + 9];
        return 1;
    }

    return 0;
}

int32_t ResourceBarDDCGetVCP(uint32_t framebuffer, uint8_t control, uint16_t *current, uint16_t *maximum) {
    if (current == 0 || maximum == 0) {
        return 0;
    }

    ResourceBarDDCGetContext context = {control, 0, 0};
    if (!ResourceBarDDCWithFramebuffer(framebuffer, ResourceBarDDCGetOperation, &context)) {
        return 0;
    }

    *current = context.current;
    *maximum = context.maximum;
    return 1;
}

typedef struct {
    uint8_t control;
    uint16_t value;
} ResourceBarDDCSetContext;

static int ResourceBarDDCSetOperation(IOI2CConnectRef connect, void *rawContext) {
    ResourceBarDDCSetContext *context = (ResourceBarDDCSetContext *)rawContext;
    uint8_t send[7] = {
        0x51,
        0x84,
        0x03,
        context->control,
        (uint8_t)((context->value >> 8) & 0xFF),
        (uint8_t)(context->value & 0xFF),
        0x00
    };
    send[6] = ResourceBarDDCChecksum(0x6E, send, 6);

    IOI2CRequest request = {0};
    request.sendTransactionType = kIOI2CSimpleTransactionType;
    request.replyTransactionType = kIOI2CNoTransactionType;
    request.sendAddress = 0x6E;
    request.sendBuffer = (vm_address_t)(uintptr_t)send;
    request.sendBytes = sizeof(send);

    IOReturn result = IOI2CSendRequest(connect, kNilOptions, &request);
    return result == kIOReturnSuccess && request.result == kIOReturnSuccess;
}

int32_t ResourceBarDDCSetVCP(uint32_t framebuffer, uint8_t control, uint16_t value) {
    ResourceBarDDCSetContext context = {control, value};
    return ResourceBarDDCWithFramebuffer(framebuffer, ResourceBarDDCSetOperation, &context) ? 1 : 0;
}

static void *ResourceBarOpenFramework(const char *path) {
    void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (handle != 0) {
        return handle;
    }

    return dlopen(path, RTLD_LAZY);
}

static void *ResourceBarDisplayServicesSymbol(const char *symbolName) {
    static void *handle = 0;
    if (handle == 0) {
        handle = ResourceBarOpenFramework("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices");
    }

    return handle == 0 ? 0 : dlsym(handle, symbolName);
}

int32_t ResourceBarDisplayServicesGetBrightness(uint32_t displayID, float *value) {
    if (value == 0) {
        return 0;
    }

    typedef int32_t (*GetBrightnessFunction)(uint32_t displayID, float *value);
    GetBrightnessFunction function = (GetBrightnessFunction)ResourceBarDisplayServicesSymbol("DisplayServicesGetBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

int32_t ResourceBarDisplayServicesSetBrightness(uint32_t displayID, float value) {
    typedef int32_t (*SetBrightnessFunction)(uint32_t displayID, float value);
    SetBrightnessFunction function = (SetBrightnessFunction)ResourceBarDisplayServicesSymbol("DisplayServicesSetBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

static void *ResourceBarCoreDisplaySymbol(const char *symbolName) {
    static void *handle = 0;
    if (handle == 0) {
        handle = ResourceBarOpenFramework("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay");
    }

    return handle == 0 ? 0 : dlsym(handle, symbolName);
}

int32_t ResourceBarCoreDisplayGetUserBrightness(uint32_t displayID, double *value) {
    if (value == 0) {
        return 0;
    }

    typedef int32_t (*GetBrightnessFunction)(uint32_t displayID, double *value);
    GetBrightnessFunction function = (GetBrightnessFunction)ResourceBarCoreDisplaySymbol("CoreDisplay_Display_GetUserBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

int32_t ResourceBarCoreDisplaySetUserBrightness(uint32_t displayID, double value) {
    typedef int32_t (*SetBrightnessFunction)(uint32_t displayID, double value);
    SetBrightnessFunction function = (SetBrightnessFunction)ResourceBarCoreDisplaySymbol("CoreDisplay_Display_SetUserBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

int32_t ResourceBarCoreDisplaySetLinearBrightness(uint32_t displayID, double value) {
    typedef int32_t (*SetBrightnessFunction)(uint32_t displayID, double value);
    SetBrightnessFunction function = (SetBrightnessFunction)ResourceBarCoreDisplaySymbol("CoreDisplay_Display_SetLinearBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

int32_t ResourceBarCoreDisplaySetDynamicLinearBrightness(uint32_t displayID, double value) {
    typedef int32_t (*SetBrightnessFunction)(uint32_t displayID, double value);
    SetBrightnessFunction function = (SetBrightnessFunction)ResourceBarCoreDisplaySymbol("CoreDisplay_Display_SetDynamicLinearBrightness");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}

int32_t ResourceBarCoreDisplaySetDynamicSliderFactor(uint32_t displayID, double value) {
    typedef int32_t (*SetBrightnessFunction)(uint32_t displayID, double value);
    SetBrightnessFunction function = (SetBrightnessFunction)ResourceBarCoreDisplaySymbol("CoreDisplay_Display_SetDynamicSliderFactor");
    if (function == 0) {
        return 0;
    }

    return function(displayID, value) == 0 ? 1 : 0;
}
