import { FileNode } from '../model/FileNode';

export interface FileTreeDataSource {
  getRoots(): Promise<FileNode[]>;

  listChildren(node: FileNode): Promise<FileNode[]>;
}
