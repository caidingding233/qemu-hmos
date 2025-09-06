// Minimal stub to keep build green; the real noVNC WebView is used in VNCViewer
@Component
export struct VNCDisplay {
  build() {
    Column() {
      Text('VNCDisplay stub')
        .fontSize(14)
        .fontColor(Color.Grey)
        .padding(12)
    }
  }
}
