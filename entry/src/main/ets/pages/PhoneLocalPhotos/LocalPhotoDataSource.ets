// LocalPhotoDataSource实现了IDataSource接口，用于管理listener监听，以及通知LazyForEach数据更新

class LocalPhotoDataSource implements IDataSource{

  totalCount(): number {
    throw new Error('Method not implemented.');
  }

  getData(index: number): any {
    throw new Error('Method not implemented.');
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    throw new Error('Method not implemented.');
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    throw new Error('Method not implemented.');
  }

}