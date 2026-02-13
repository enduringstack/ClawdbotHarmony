import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CustomSkillDef } from '../model/Models';
import { Constants } from '../common/Constants';
import { LogService } from '../common/LogService';

/**
 * Singleton service for custom skill CRUD and persistence.
 * Custom skills are stored as a JSON array in preferences.
 */

export interface CreateSkillInput {
  name: string;
  description: string;
  prompt: string;
  category?: string;
}

export interface UpdateSkillInput {
  id: string;
  name?: string;
  description?: string;
  prompt?: string;
  enabled?: boolean;
}

export class CustomSkillService {
  private static instance: CustomSkillService | undefined = undefined;
  private log: LogService = LogService.getInstance();
  private readonly TAG = 'CustomSkillSvc';

  static getInstance(): CustomSkillService {
    if (!CustomSkillService.instance) {
      CustomSkillService.instance = new CustomSkillService();
    }
    return CustomSkillService.instance;
  }

  async loadAll(ctx: common.UIAbilityContext): Promise<CustomSkillDef[]> {
    let store = await preferences.getPreferences(ctx, Constants.PREFS_CUSTOM_SKILLS);
    let raw = (await store.get('skills', '[]')) as string;
    let skills = JSON.parse(raw) as CustomSkillDef[];
    return skills;
  }

  async create(ctx: common.UIAbilityContext, input: CreateSkillInput): Promise<CustomSkillDef> {
    let skills = await this.loadAll(ctx);
    // Validate unique name
    for (let s of skills) {
      if (s.name === input.name) {
        throw new Error(`Skill "${input.name}" already exists`);
      }
    }
    let skill: CustomSkillDef = {
      id: `custom_${Date.now()}`,
      name: input.name,
      description: input.description,
      category: input.category ?? 'custom',
      enabled: true,
      prompt: input.prompt,
      createdAt: Date.now()
    };
    skills.push(skill);
    await this.save(ctx, skills);
    this.log.info(this.TAG, `Created skill: ${skill.name} (${skill.id})`);
    return skill;
  }

  async update(ctx: common.UIAbilityContext, input: UpdateSkillInput): Promise<CustomSkillDef> {
    let skills = await this.loadAll(ctx);
    let found: CustomSkillDef | undefined = undefined;
    for (let s of skills) {
      if (s.id === input.id) {
        found = s;
        break;
      }
    }
    if (!found) {
      throw new Error(`Skill not found: ${input.id}`);
    }
    if (input.name !== undefined) found.name = input.name;
    if (input.description !== undefined) found.description = input.description;
    if (input.prompt !== undefined) found.prompt = input.prompt;
    if (input.enabled !== undefined) found.enabled = input.enabled;
    await this.save(ctx, skills);
    this.log.info(this.TAG, `Updated skill: ${found.name} (${found.id})`);
    return found;
  }

  async delete(ctx: common.UIAbilityContext, id: string): Promise<boolean> {
    let skills = await this.loadAll(ctx);
    let remaining: CustomSkillDef[] = [];
    let found = false;
    for (let s of skills) {
      if (s.id === id) {
        found = true;
      } else {
        remaining.push(s);
      }
    }
    if (!found) {
      throw new Error(`Skill not found: ${id}`);
    }
    await this.save(ctx, remaining);
    this.log.info(this.TAG, `Deleted skill: ${id}`);
    return true;
  }

  private async save(ctx: common.UIAbilityContext, skills: CustomSkillDef[]): Promise<void> {
    let store = await preferences.getPreferences(ctx, Constants.PREFS_CUSTOM_SKILLS);
    await store.put('skills', JSON.stringify(skills));
    await store.flush();
  }
}
