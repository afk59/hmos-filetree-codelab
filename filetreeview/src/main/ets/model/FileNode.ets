export interface FileNode {
  name: string;
  path: string;
  isDirectory: boolean;
  size?: number;
  mtime?: number;
  uri?: string;
  loaded?: boolean;
  error?: string;
}

export type FileTreeSort =
  'name-asc' | 'name-desc' | 'size-asc' | 'size-desc' | 'date-asc' | 'date-desc';

export interface FileTreeConfig {
  showHidden?: boolean;
  extWhitelist?: string[];
  extBlacklist?: string[];
  sort?: FileTreeSort;
}
