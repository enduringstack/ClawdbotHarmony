// ============================================================
//  Experience Pack — 经验包
//  一条经验 = 几个 skills + 几条 memory
// ============================================================

/** 技能（与 Anthropic skills 格式一致）*/
export interface Skill {
  name: string;           // 技能名称
  description: string;    // 简短描述
  instructions: string;   // 执行指令 (markdown)
}

/** 记忆 */
export interface Memory {
  key: string;            // 如 "项目路径" / "当前版本"
  value: string;          // 具体值
}

/** 一条经验 = skills + memory */
export interface Experience {
  id: string;
  name: string;           // 经验名称，如 "ClawdBotHarmony 开发"
  description: string;    // 简述
  skills: Skill[];        // 相关技能
  memory: Memory[];       // 相关记忆
  createdAt: number;
  updatedAt: number;
}

/** 经验包 */
export interface ExperiencePack {
  version: number;        // schema 版本
  updatedAt: number;      // 最后更新时间
  syncedAt: number;       // 最后同步时间 (0 = 未同步)
  experiences: Experience[];
}

/** 生成唯一 ID */
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
}

/** 创建空的经验包 */
export function createDefaultExperiencePack(): ExperiencePack {
  return {
    version: 3,
    updatedAt: Date.now(),
    syncedAt: 0,
    experiences: [],
  };
}

/** 创建新经验 */
export function createExperience(name: string, description: string): Experience {
  return {
    id: generateId(),
    name,
    description,
    skills: [],
    memory: [],
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

/** 创建新技能 */
export function createSkill(name: string, description: string, instructions: string): Skill {
  return {
    name,
    description,
    instructions,
  };
}

/** 创建新记忆 */
export function createMemory(key: string, value: string): Memory {
  return {
    key,
    value,
  };
}
