import 'dart:io';

import 'package:archive/archive.dart';
import 'package:betto_pdfium/betto_pdfium.dart';
// csv 包原本被 import 但 _extractCsv 直接 readAsString 未使用，已移除。
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

/// 多格式文档解析为纯文本。
///
/// 支持格式：md / txt / pdf / docx / xlsx / csv
/// PDF 用 betto_pdfium（纯 Dart FFI 封装 PDFium，Windows x64 原生支持）。
class DocumentLoader {
  /// 按扩展名分发提取纯文本。
  ///
  /// 抛出 [UnsupportedError] 当扩展名不被支持时。
  /// PDF 若为纯扫描件（无文本层）会抛 [StateError]，提示用户先 OCR。
  Future<String> extractText(String path) async {
    final lower = path.toLowerCase();
    final ext = lower.split('.').last;

    switch (ext) {
      case 'txt':
      case 'md':
        return await _extractPlainText(path);
      case 'pdf':
        return await _extractPdf(path);
      case 'docx':
        return await _extractDocx(path);
      case 'xlsx':
        return await _extractXlsx(path);
      case 'csv':
        return await _extractCsv(path);
      default:
        throw UnsupportedError('不支持的文件格式: .$ext（支持 md/txt/pdf/docx/xlsx/csv）');
    }
  }

  // ---- MD / TXT ----

  Future<String> _extractPlainText(String path) async {
    return await File(path).readAsString();
  }

  // ---- PDF ----

  /// 用 betto_pdfium（PDFium FFI）提取 PDF 文本。
  ///
  /// `PdfDocument.fromBytes(bytes)` 把 PDF 字节载入后台 isolate，
  /// `extractPlainText()` 返回 `Stream<PdfPageText>`，逐页流式产出：
  ///   - `page.hasTextLayer`：是否含可提取文本（扫描件为 false）
  ///   - `page.text`：该页文本
  ///   - `page.pageIndex`：页码（0-based）
  /// 扫描件页直接跳过（知识库 RAG 不做 OCR）；
  /// 若整篇都没文本层，抛 [StateError] 提示用户先 OCR 或转格式。
  /// 用完必须 `await doc.close()` 释放 PDFium 句柄（用 try/finally 保证）。
  Future<String> _extractPdf(String path) async {
    final bytes = await File(path).readAsBytes();
    final doc = await PdfDocument.fromBytes(bytes);
    try {
      final buf = StringBuffer();
      await for (final page in doc.extractPlainText()) {
        if (page.hasTextLayer) {
          buf.writeln(page.text);
        }
        // 无文本层（扫描件）的页直接跳过——知识库 RAG 不做 OCR。
      }
      final text = buf.toString().trim();
      if (text.isEmpty) {
        throw StateError(
          'PDF 未提取到任何文本（可能是纯扫描件）。'
          '请先用 OCR 工具转为可搜索 PDF，或转为 txt/md/docx 再上传。',
        );
      }
      return text;
    } finally {
      await doc.close();
    }
  }

  // ---- DOCX ----

  /// DOCX 本质是 zip 包，主文本在 word/document.xml。
  /// 所有正文文本节点形如 `<w:t>...</w:t>`，遍历拼接即可。
  /// 表格单元格也走相同机制，但结构会丢失（仅保留文本）。
  Future<String> _extractDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) {
      throw StateError('DOCX 内部未找到 word/document.xml');
    }
    final xmlStr = String.fromCharCodes(docFile.content as List<int>);
    final doc = XmlDocument.parse(xmlStr);

    final buf = StringBuffer();
    // 遍历所有 <w:t> 文本节点。
    // 注意：DOCX 用命名空间，这里用 tag 本地名匹配。
    for (final node in doc.descendants) {
      if (node is XmlElement) {
        final local = node.name.local;
        if (local == 't') {
          buf.write(node.innerText);
        } else if (local == 'p' || local == 'br') {
          // 段落或换行处加换行符，保留基本可读性。
          buf.writeln();
        }
      }
    }
    return buf.toString().trim();
  }

  // ---- XLSX ----

  Future<String> _extractXlsx(String path) async {
    final bytes = await File(path).readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final buf = StringBuffer();
    for (final sheet in excel.sheets.values) {
      for (final row in sheet.rows) {
        final cells = row
            .map((c) => c?.value?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) {
          buf.writeln(cells.join('\t'));
        }
      }
      buf.writeln();
    }
    return buf.toString().trim();
  }

  // ---- CSV ----

  Future<String> _extractCsv(String path) async {
    // CSV 本身就是文本，直接读取。
    return await File(path).readAsString();
  }
}

/// 把 `List<int>` 转 `List<int>`（archive content 兼容）。
/// archive 的 content 类型为 `List<int>` 或动态，这里用辅助转换避免类型警告。
extension on List<int> {}
