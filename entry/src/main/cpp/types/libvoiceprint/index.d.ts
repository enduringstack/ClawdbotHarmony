/**
 * Native voiceprint module - speaker embedding extraction via sherpa-onnx.
 */

/**
 * Initialize the speaker embedding model.
 * Must be called before extractEmbedding or computeSimilarity.
 * @param modelDir - Path to directory containing the ONNX model file
 * @returns true if initialization succeeded
 */
export const initModel: (modelDir: string) => boolean;

/**
 * Extract a 192-dimensional speaker embedding from PCM audio.
 * @param pcmData - Float32Array of PCM samples normalized to [-1, 1]
 * @param sampleRate - Sample rate in Hz (expected: 16000)
 * @returns Float32Array of 192 floats, or throws on failure
 */
export const extractEmbedding: (pcmData: Float32Array, sampleRate: number) => Float32Array;

/**
 * Compute cosine similarity between two speaker embeddings.
 * @param embedding1 - First 192-dim Float32Array embedding
 * @param embedding2 - Second 192-dim Float32Array embedding
 * @returns Cosine similarity in range [-1, 1]
 */
export const computeSimilarity: (embedding1: Float32Array, embedding2: Float32Array) => number;

/**
 * Get the embedding dimension (192 for 3D-Speaker model).
 * @returns Embedding dimension
 */
export const getEmbeddingDim: () => number;

/**
 * Check if the model has been loaded.
 * @returns true if initModel() has been called successfully
 */
export const isModelLoaded: () => boolean;
