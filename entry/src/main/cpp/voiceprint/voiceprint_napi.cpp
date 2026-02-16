/**
 * Native module for speaker embedding extraction using sherpa-onnx.
 * Provides voiceprint (speaker identification) capabilities via NAPI.
 *
 * Dependencies: sherpa-onnx with ONNX Runtime
 * Model: 3D-Speaker (192-dim embeddings)
 */
#include <cmath>
#include <cstring>
#include <string>
#include <vector>
#include <napi/native_api.h>

// TODO: Include sherpa-onnx headers when library is integrated
// #include "sherpa-onnx/c-api/c-api.h"

// Embedding dimension for 3D-Speaker model
static constexpr int EMBEDDING_DIM = 192;

// Whether the model has been initialized
static bool g_initialized = false;

// TODO: sherpa-onnx speaker embedding extractor handle
// static const SherpaOnnxSpeakerEmbeddingExtractor *g_extractor = nullptr;

/**
 * initModel(modelDir: string): boolean
 *
 * Initialize the sherpa-onnx speaker embedding extractor.
 * Must be called before extractEmbedding/computeSimilarity.
 *
 * @param modelDir - Path to the directory containing the ONNX model file
 * @returns true if initialization succeeded
 */
static napi_value InitModel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_error(env, nullptr, "initModel requires modelDir string");
        return nullptr;
    }

    // Get model directory path
    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &pathLen);
    std::string modelDir(pathLen, '\0');
    napi_get_value_string_utf8(env, args[0], &modelDir[0], pathLen + 1, &pathLen);

    // TODO: Initialize sherpa-onnx speaker embedding extractor
    // SherpaOnnxSpeakerEmbeddingExtractorConfig config;
    // memset(&config, 0, sizeof(config));
    // config.model = (modelDir + "/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx").c_str();
    // config.num_threads = 2;
    // config.provider = "cpu";
    // g_extractor = SherpaOnnxCreateSpeakerEmbeddingExtractor(&config);

    g_initialized = true; // Stub: always succeed for now

    napi_value result;
    napi_get_boolean(env, g_initialized, &result);
    return result;
}

/**
 * extractEmbedding(pcmData: Float32Array, sampleRate: number): Float32Array | null
 *
 * Extract a 192-dimensional speaker embedding from PCM audio data.
 *
 * @param pcmData - Float32Array of PCM samples (normalized to [-1, 1])
 * @param sampleRate - Sample rate in Hz (expected: 16000)
 * @returns Float32Array of 192 floats, or null on failure
 */
static napi_value ExtractEmbedding(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "extractEmbedding requires (pcmData: Float32Array, sampleRate: number)");
        return nullptr;
    }

    if (!g_initialized) {
        napi_throw_error(env, nullptr, "Model not initialized. Call initModel() first.");
        return nullptr;
    }

    // Get PCM data from Float32Array
    bool isTypedArray = false;
    napi_is_typedarray(env, args[0], &isTypedArray);
    if (!isTypedArray) {
        napi_throw_error(env, nullptr, "pcmData must be a Float32Array");
        return nullptr;
    }

    napi_typedarray_type type;
    size_t length = 0;
    void *data = nullptr;
    napi_value arrayBuffer;
    size_t byteOffset = 0;
    napi_get_typedarray_info(env, args[0], &type, &length, &data, &arrayBuffer, &byteOffset);

    if (type != napi_float32_array) {
        napi_throw_error(env, nullptr, "pcmData must be a Float32Array");
        return nullptr;
    }

    // Get sample rate
    int32_t sampleRate = 16000;
    napi_get_value_int32(env, args[1], &sampleRate);

    float *pcmSamples = static_cast<float *>(data);

    // TODO: Use sherpa-onnx to extract embedding
    // SherpaOnnxOnlineStream *stream = SherpaOnnxSpeakerEmbeddingExtractorCreateStream(g_extractor);
    // SherpaOnnxOnlineStreamAcceptWaveform(stream, sampleRate, pcmSamples, length);
    // SherpaOnnxOnlineStreamInputFinished(stream);
    // const float *embedding = SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding(g_extractor, stream);

    // Stub: return zero embedding
    std::vector<float> embedding(EMBEDDING_DIM, 0.0f);

    // Create Float32Array result
    napi_value outputBuffer;
    void *outputData = nullptr;
    napi_create_arraybuffer(env, EMBEDDING_DIM * sizeof(float), &outputData, &outputBuffer);
    memcpy(outputData, embedding.data(), EMBEDDING_DIM * sizeof(float));

    napi_value resultArray;
    napi_create_typedarray(env, napi_float32_array, EMBEDDING_DIM, outputBuffer, 0, &resultArray);

    // TODO: Free sherpa-onnx resources
    // SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding(embedding);
    // SherpaOnnxDestroyOnlineStream(stream);

    return resultArray;
}

/**
 * computeSimilarity(embedding1: Float32Array, embedding2: Float32Array): number
 *
 * Compute cosine similarity between two speaker embeddings.
 *
 * @param embedding1 - First 192-dim embedding
 * @param embedding2 - Second 192-dim embedding
 * @returns Cosine similarity in range [-1, 1]
 */
static napi_value ComputeSimilarity(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "computeSimilarity requires two Float32Array embeddings");
        return nullptr;
    }

    // Get embedding 1
    void *data1 = nullptr;
    size_t len1 = 0;
    napi_typedarray_type type1;
    napi_value ab1;
    size_t offset1;
    napi_get_typedarray_info(env, args[0], &type1, &len1, &data1, &ab1, &offset1);

    // Get embedding 2
    void *data2 = nullptr;
    size_t len2 = 0;
    napi_typedarray_type type2;
    napi_value ab2;
    size_t offset2;
    napi_get_typedarray_info(env, args[1], &type2, &len2, &data2, &ab2, &offset2);

    if (type1 != napi_float32_array || type2 != napi_float32_array) {
        napi_throw_error(env, nullptr, "Both embeddings must be Float32Array");
        return nullptr;
    }

    if (len1 != EMBEDDING_DIM || len2 != EMBEDDING_DIM) {
        napi_throw_error(env, nullptr, "Embeddings must have 192 dimensions");
        return nullptr;
    }

    float *emb1 = static_cast<float *>(data1);
    float *emb2 = static_cast<float *>(data2);

    // Cosine similarity: dot(a,b) / (norm(a) * norm(b))
    double dot = 0.0, norm1 = 0.0, norm2 = 0.0;
    for (int i = 0; i < EMBEDDING_DIM; i++) {
        dot += emb1[i] * emb2[i];
        norm1 += emb1[i] * emb1[i];
        norm2 += emb2[i] * emb2[i];
    }

    double similarity = 0.0;
    if (norm1 > 0 && norm2 > 0) {
        similarity = dot / (std::sqrt(norm1) * std::sqrt(norm2));
    }

    napi_value result;
    napi_create_double(env, similarity, &result);
    return result;
}

/**
 * getEmbeddingDim(): number
 *
 * @returns The embedding dimension (192 for 3D-Speaker)
 */
static napi_value GetEmbeddingDim(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_int32(env, EMBEDDING_DIM, &result);
    return result;
}

/**
 * isModelLoaded(): boolean
 *
 * @returns Whether the model has been initialized
 */
static napi_value IsModelLoaded(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, g_initialized, &result);
    return result;
}

// Module registration
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initModel", nullptr, InitModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"extractEmbedding", nullptr, ExtractEmbedding, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"computeSimilarity", nullptr, ComputeSimilarity, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getEmbeddingDim", nullptr, GetEmbeddingDim, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isModelLoaded", nullptr, IsModelLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module voiceprintModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "voiceprint",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVoiceprintModule(void) {
    napi_module_register(&voiceprintModule);
}
