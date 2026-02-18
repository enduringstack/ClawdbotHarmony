/**
 * ExperienceStorage — 经验包存储服务
 * 一条经验 = skills + memory
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Constants } from '../common/Constants';
import { LogService } from '../common/LogService';
import {
  ExperiencePack,
  Experience,
  Skill,
  Memory,
  createDefaultExperiencePack,
  generateId,
} from '../model/ExperiencePack';

const TAG = 'ExperienceStorage';
const STORE_KEY = 'experience_pack_v3';

export class ExperienceStorage {
  private static instance: ExperienceStorage | undefined = undefined;
  private log: LogService = LogService.getInstance();
  private _pack: ExperiencePack | undefined = undefined;

  static getInstance(): ExperienceStorage {
    if (!ExperienceStorage.instance) {
      ExperienceStorage.instance = new ExperienceStorage();
    }
    return ExperienceStorage.instance;
  }

  get pack(): ExperiencePack | undefined {
    return this._pack;
  }

  // ==================== 核心存储 ====================

  async load(context: common.UIAbilityContext): Promise<ExperiencePack | null> {
    try {
      let store = await preferences.getPreferences(context, Constants.PREFS_EXPERIENCE);
      let json = (await store.get(STORE_KEY, '')) as string;
      if (json.length === 0) {
        this.log.info(TAG, 'No experience pack found');
        return null;
      }
      let parsed: ExperiencePack = JSON.parse(json) as ExperiencePack;
      this._pack = parsed;
      this.log.info(TAG, `Loaded: ${parsed.experiences.length} experiences`);
      return parsed;
    } catch (err) {
      this.log.error(TAG, `Load failed: ${(err as Error).message ?? ''}`);
      return null;
    }
  }

  async save(context: common.UIAbilityContext, pack: ExperiencePack): Promise<void> {
    try {
      pack.updatedAt = Date.now();
      let store = await preferences.getPreferences(context, Constants.PREFS_EXPERIENCE);
      await store.put(STORE_KEY, JSON.stringify(pack));
      await store.flush();
      this._pack = pack;
      this.log.info(TAG, 'Experience pack saved');
    } catch (err) {
      this.log.error(TAG, `Save failed: ${(err as Error).message ?? ''}`);
    }
  }

  async ensureLoaded(context: common.UIAbilityContext): Promise<ExperiencePack> {
    if (this._pack) return this._pack;
    let loaded = await this.load(context);
    if (loaded) return loaded;
    let fresh = createDefaultExperiencePack();
    await this.save(context, fresh);
    return fresh;
  }

  // ==================== Experience 操作 ====================

  async addExperience(context: common.UIAbilityContext, exp: Experience): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let idx = pack.experiences.findIndex((e: Experience) => e.id === exp.id);
    if (idx >= 0) {
      pack.experiences[idx] = exp;
    } else {
      pack.experiences.push(exp);
    }
    await this.save(context, pack);
  }

  async updateExperience(context: common.UIAbilityContext, id: string, updates: Partial<Experience>): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let idx = pack.experiences.findIndex((e: Experience) => e.id === id);
    if (idx >= 0) {
      let exp = pack.experiences[idx];
      if (updates.name !== undefined) exp.name = updates.name;
      if (updates.description !== undefined) exp.description = updates.description;
      if (updates.skills !== undefined) exp.skills = updates.skills;
      if (updates.memory !== undefined) exp.memory = updates.memory;
      exp.updatedAt = Date.now();
      await this.save(context, pack);
    }
  }

  async removeExperience(context: common.UIAbilityContext, id: string): Promise<void> {
    let pack = await this.ensureLoaded(context);
    pack.experiences = pack.experiences.filter((e: Experience) => e.id !== id);
    await this.save(context, pack);
  }

  getExperienceById(id: string): Experience | undefined {
    if (!this._pack) return undefined;
    return this._pack.experiences.find((e: Experience) => e.id === id);
  }

  getExperienceByName(name: string): Experience | undefined {
    if (!this._pack) return undefined;
    return this._pack.experiences.find((e: Experience) => e.name === name);
  }

  // ==================== Skill 操作 (在 Experience 内) ====================

  async addSkillToExperience(context: common.UIAbilityContext, expId: string, skill: Skill): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let exp = pack.experiences.find((e: Experience) => e.id === expId);
    if (exp) {
      let idx = exp.skills.findIndex((s: Skill) => s.name === skill.name);
      if (idx >= 0) {
        exp.skills[idx] = skill;
      } else {
        exp.skills.push(skill);
      }
      exp.updatedAt = Date.now();
      await this.save(context, pack);
    }
  }

  async removeSkillFromExperience(context: common.UIAbilityContext, expId: string, skillName: string): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let exp = pack.experiences.find((e: Experience) => e.id === expId);
    if (exp) {
      exp.skills = exp.skills.filter((s: Skill) => s.name !== skillName);
      exp.updatedAt = Date.now();
      await this.save(context, pack);
    }
  }

  // ==================== Memory 操作 (在 Experience 内) ====================

  async addMemoryToExperience(context: common.UIAbilityContext, expId: string, mem: Memory): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let exp = pack.experiences.find((e: Experience) => e.id === expId);
    if (exp) {
      let idx = exp.memory.findIndex((m: Memory) => m.key === mem.key);
      if (idx >= 0) {
        exp.memory[idx] = mem;
      } else {
        exp.memory.push(mem);
      }
      exp.updatedAt = Date.now();
      await this.save(context, pack);
    }
  }

  async removeMemoryFromExperience(context: common.UIAbilityContext, expId: string, key: string): Promise<void> {
    let pack = await this.ensureLoaded(context);
    let exp = pack.experiences.find((e: Experience) => e.id === expId);
    if (exp) {
      exp.memory = exp.memory.filter((m: Memory) => m.key !== key);
      exp.updatedAt = Date.now();
      await this.save(context, pack);
    }
  }

  // ==================== 同步状态 ====================

  async markSynced(context: common.UIAbilityContext): Promise<void> {
    let pack = await this.ensureLoaded(context);
    pack.syncedAt = Date.now();
    await this.save(context, pack);
  }

  // ==================== 导入导出 ====================

  exportToJson(): string {
    if (!this._pack) return '{}';
    return JSON.stringify(this._pack, null, 2);
  }

  async importFromJson(context: common.UIAbilityContext, json: string): Promise<boolean> {
    try {
      let parsed: ExperiencePack = JSON.parse(json) as ExperiencePack;
      if (!Array.isArray(parsed.experiences)) {
        this.log.warn(TAG, 'Import failed: invalid structure');
        return false;
      }
      parsed.version = 3;
      parsed.updatedAt = Date.now();
      parsed.syncedAt = 0;
      await this.save(context, parsed);
      this.log.info(TAG, 'Experience pack imported');
      return true;
    } catch (err) {
      this.log.error(TAG, `Import failed: ${(err as Error).message ?? ''}`);
      return false;
    }
  }

  // ==================== 清除 ====================

  async clear(context: common.UIAbilityContext): Promise<void> {
    try {
      let store = await preferences.getPreferences(context, Constants.PREFS_EXPERIENCE);
      await store.delete(STORE_KEY);
      await store.flush();
      this._pack = undefined;
      this.log.info(TAG, 'Experience pack cleared');
    } catch (err) {
      this.log.error(TAG, `Clear failed: ${(err as Error).message ?? ''}`);
    }
  }

  // ==================== 服务端合并更新 ====================

  async mergeUpdate(context: common.UIAbilityContext, partial: Record<string, Object>): Promise<void> {
    let pack = await this.ensureLoaded(context);

    if (partial['experiences'] && Array.isArray(partial['experiences'])) {
      let newExps = partial['experiences'] as Experience[];
      for (let i = 0; i < newExps.length; i++) {
        let exp = newExps[i];
        if (!exp.id) exp.id = generateId();
        if (!exp.createdAt) exp.createdAt = Date.now();
        if (!exp.updatedAt) exp.updatedAt = Date.now();

        let idx = pack.experiences.findIndex((e: Experience) => e.name === exp.name);
        if (idx >= 0) {
          // 合并：新的更晚时覆盖
          if (exp.updatedAt > pack.experiences[idx].updatedAt) {
            pack.experiences[idx] = exp;
          }
        } else {
          pack.experiences.push(exp);
        }
      }
    }

    await this.save(context, pack);
    this.log.info(TAG, 'Merged server update');
  }

  // ==================== 统计 ====================

  getExperiencesCount(): number {
    return this._pack?.experiences.length ?? 0;
  }

  getTotalSkillsCount(): number {
    if (!this._pack) return 0;
    let count = 0;
    for (let i = 0; i < this._pack.experiences.length; i++) {
      count += this._pack.experiences[i].skills.length;
    }
    return count;
  }

  getTotalMemoryCount(): number {
    if (!this._pack) return 0;
    let count = 0;
    for (let i = 0; i < this._pack.experiences.length; i++) {
      count += this._pack.experiences[i].memory.length;
    }
    return count;
  }

  getLastSyncTime(): string {
    if (!this._pack || this._pack.syncedAt === 0) {
      return '从未';
    }
    return new Date(this._pack.syncedAt).toLocaleString();
  }
}
