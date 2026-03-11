#ifndef LLM_CORE_H
#define LLM_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*LLMCore_TokenCallback)(const char* token, void* userData);
typedef void (*LLMCore_DoneCallback)(void* userData);

typedef struct LLMCore_Config {
    int inferType;
    const char* modelPath;
    const char* weightDir;
    const char* tokenizerPath;
    const char* specModelPath;
    const char* specWeightDir;
    const char* loraCfgPath;
    const char* specLoraCfgPath;
    bool isAsync;
    int maxGenTokens;
    int seed;
    int topK;
    float topP;
    float temperature;
    float repetitionPenalty;
    bool doSample;
    int gamma;
    const char* topHeadStr;
    const char* topKSpecStr;
    float draftThreshold;
    float typicalScaling;
    const char* stopSeqStr;
} LLMCore_Config;

int LLMCore_Init(const LLMCore_Config* config);

int LLMCore_Infer(const char* prompt, 
                  LLMCore_TokenCallback tokenCallback,
                  LLMCore_DoneCallback doneCallback,
                  void* userData);

void LLMCore_Deinit(void);

const char* LLMCore_GetVersion(void);

const char* LLMCore_GetLastError(void);

bool LLMCore_IsInitialized(void);

void LLMCore_StopGeneration(void);

#ifdef __cplusplus
}
#endif

#endif
