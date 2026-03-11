/**
 * Native CANN LLM module - on-device LLM inference
 * 
 * Provides Pangu 7B model inference with speculative decoding
 */

export interface CANNConfig {
  modelPath: string;
  weightDir: string;
  tokenizerPath: string;
  specModelPath: string;
  specWeightDir: string;
  loraCfgPath: string;
  maxGenTokens?: number;
  temperature?: number;
}

/**
 * Check if CANN LLM is available (so files exist).
 * Returns false if using stub module.
 * @returns true if full functionality is available
 */
export const isAvailable: () => boolean;

/**
 * Load and initialize the LLM model.
 * @param config - Configuration object with model paths
 * @returns Status message string
 */
export const loadmodel: (config: CANNConfig) => string;

/**
 * Check if model is initialized.
 * @returns true if initialized
 */
export const isInitialized: () => boolean;

/**
 * Get last error message.
 * @returns Error message string
 */
export const getLastError: () => string;

/**
 * Register callback for receiving tokens during inference.
 * Must be called before modelinfer().
 * @param callback - Function called with each generated token
 */
export const answerget: (callback: (token: string) => void) => void;

/**
 * Run inference on the given prompt.
 * Uses thread-safe callback registered via answerget().
 * @param prompt - Input prompt string (should be formatted for the model)
 */
export const modelinfer: (prompt: string) => void;

/**
 * Deinitialize the model and free resources.
 */
export const deinitmodel: () => void;
