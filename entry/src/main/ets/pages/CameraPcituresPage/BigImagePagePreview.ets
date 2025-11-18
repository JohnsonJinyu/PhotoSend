import { BigImagePage } from './BigImagePage'

@Preview
@Entry
@Component
struct BigImagePagePreview{

  build() {
    Column(){
      BigImagePage()
    }
  }
}