import 'dart:convert';
import 'package:archive/archive.dart';

List<int> samplePdf() {
  const text = 'BT /F1 24 Tf 50 700 Td (Hello Technical Book) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${text.length} >>\nstream\n$text\nendstream',
    '<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 1 >>',
    '<< /Title (Second chapter) /Parent 7 0 R /Dest [4 0 R /Fit] >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (final (i, object) in objects.indexed) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n$object\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return ascii.encode(buffer.toString());
}

List<int> sampleEpub({
  String image = 'picture.png',
  bool vertical = false,
  int paragraphs = 1,
}) {
  final archive = Archive();
  void add(String name, String text) =>
      archive.addFile(ArchiveFile.string(name, text));
  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>',
  );
  add(
    'OEBPS/book.opf',
    '<package><metadata><title>测试</title><creator>作者</creator></metadata><manifest><item id="a" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>',
  );
  add(
    'OEBPS/style.css',
    vertical ? 'body{writing-mode:vertical-rl}' : 'body{}',
  );
  add(
    'OEBPS/chapter.xhtml',
    '<html><head><link rel="stylesheet" href="style.css"/><title>章节</title></head><body><h1>第一章</h1><p>中文正文</p><ruby>漢<rt>hàn</rt></ruby><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"><rect width="120" height="40" fill="#008080"/><text x="5" y="25">Diagram</text></svg><pre><code>docker run hello-world\n  --example</code></pre><img src="$image"/>${List.filled(paragraphs, '<p>阅读示例文字，保留章节内的分页及位置。</p>').join()}<script>alert(1)</script><iframe src="https://evil.test"/><p style="background:url(https://evil.test)">结束</p></body></html>',
  );
  final picture = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAANwAAABaCAIAAABc0a8TAAABvElEQVR4nO3SwUlDYRBG0dRkBy7cW4kNpU4RsspWnr4HEZK58T9wCxi+OafPr4uU6jR+gbQJSuWCUrmgVC4olQtK5YJSuaBULiiVC0rlglK5oFQuKJULSuWCUrmgVC4olQtK5YJSz4by7eP87xv/gdmhvGEdKEdmhxLK3OxQQpmbHUooc7NDCWVudiihzM0OJZS52aGEMjc7lFDmZocSytzsUEKZmx1KKHOzQwllbnYooczNDuUAypfXd7NDmUN57HLx2aEcQ3ngcvHZoZxEuedy8dmhHEb5q8vFZ4dyHuVPl4vPDmUC5cbl4rNDWUH53eXis0N53iMy2PgmDwjKo8YJQgnltnGCUEK5bZwglFBuGycIJZQ3rHOn9iyaHcoWSrND2UJpdihbKM0OZQul2aFsoTQ7lC2UZoeyhdLsUP5xnakWnx1KKHOzQwllbnYooczNDiWUudmhhDI3O5RQ5maHEsrc7FBCmZsdSihzs0MJZW52KKHMzQ4llLnZoYQyNzuUUD4bSunxQalcUCoXlMoFpXJBqVxQKheUygWlckGpXFAqF5TKBaVyQalcUCoXlMoFpXJBqVxQ6lLrCvDATx2my6NXAAAAAElFTkSuQmCC',
  );
  archive.addFile(ArchiveFile('OEBPS/picture.png', picture.length, picture));
  return ZipEncoder().encode(archive);
}
