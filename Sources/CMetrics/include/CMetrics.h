#ifndef CMETRICS_H
#define CMETRICS_H

#include <stdint.h>

int32_t ResourceBarMemoryFreeLevel(void);
int32_t ResourceBarFanCount(void);
double ResourceBarFanRPM(int32_t fanIndex);
double ResourceBarSMCTemperature(const char *smcKey);

uint32_t ResourceBarDisplayFramebufferService(uint32_t displayID);
int32_t ResourceBarDisplayModePixelEncoding(const void *mode, char *buffer, uint32_t bufferLength);
int32_t ResourceBarDisplayGetBrightness(uint32_t framebuffer, float *value);
int32_t ResourceBarDisplaySetBrightness(uint32_t framebuffer, float value);
int32_t ResourceBarDDCGetVCP(uint32_t framebuffer, uint8_t control, uint16_t *current, uint16_t *maximum);
int32_t ResourceBarDDCSetVCP(uint32_t framebuffer, uint8_t control, uint16_t value);
int32_t ResourceBarDisplayServicesGetBrightness(uint32_t displayID, float *value);
int32_t ResourceBarDisplayServicesSetBrightness(uint32_t displayID, float value);
int32_t ResourceBarCoreDisplayGetUserBrightness(uint32_t displayID, double *value);
int32_t ResourceBarCoreDisplaySetUserBrightness(uint32_t displayID, double value);
int32_t ResourceBarCoreDisplaySetLinearBrightness(uint32_t displayID, double value);
int32_t ResourceBarCoreDisplaySetDynamicLinearBrightness(uint32_t displayID, double value);
int32_t ResourceBarCoreDisplaySetDynamicSliderFactor(uint32_t displayID, double value);

#endif
