import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'FileTreeDemo';

const STORE_NAME: string = 'filetree_roots';
const KEY_URIS: string = 'picked_uris';
const EMPTY_JSON_ARRAY: string = '[]';

export class PickedRootStore {
  private context: common.UIAbilityContext;
  private store?: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(): Promise<string[]> {
    try {
      const store: preferences.Preferences = await this.open();
      const raw: string = store.getSync(KEY_URIS, EMPTY_JSON_ARRAY) as string;
      const parsed: string[] = JSON.parse(raw) as string[];
      return parsed;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'Reading saved roots failed. Code: %{public}d, message: %{public}s',
        err.code, err.message);
      return [];
    }
  }

  async save(uris: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await this.open();
      store.putSync(KEY_URIS, JSON.stringify(uris));
      await store.flush();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'Saving roots failed. Code: %{public}d, message: %{public}s',
        err.code, err.message);
    }
  }

  private async open(): Promise<preferences.Preferences> {
    const cached: preferences.Preferences | undefined = this.store;
    if (cached !== undefined) {
      return cached;
    }
    try {
      const opened: preferences.Preferences =
        await preferences.getPreferences(this.context, STORE_NAME);
      this.store = opened;
      return opened;
    } catch (e) {
      const err = e as BusinessError;
      throw new Error(`Cannot open the "${STORE_NAME}" store (code ${err.code}): ${err.message}`);
    }
  }
}
